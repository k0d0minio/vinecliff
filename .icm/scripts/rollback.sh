#!/usr/bin/env bash
# rollback.sh — PREPARE a recovery from a bad merge, then stop. A human merges or clicks. (TEMPLATE-OWNED)
#
# Fix-forward stays the default (`_shared/ci.md`). When production is wrong after a merge — a
# `- production: ERROR` line from deploy-status.sh, a Vercel failure email, a client report —
# this script makes the two recoveries AVAILABLE and named, and executes neither:
#
#   --revert   a branch `claude/hotfix-revert-<slug>` off origin/main carrying
#              `git revert -m 1 <merge-sha>`, a hotfix-lane run folder with the incident lines,
#              and the hotfix-lane PR opened READY through new-run.sh (the only script that opens
#              a PR). The operator reads it, smoke-tests the preview, and merges it — or closes it.
#   --vercel   for every product project in the deploy block, the previous READY production
#              deployment (from the same read deploy-status.sh makes) and the EXACT CLI and REST
#              call that would promote it back. Printed, never called: the rollback endpoint is
#              never reached from a script.
#
# It WARNS when the merge carried a migration and the repo declares `migrations.reversible: false`
# (`.icm/project.json`): "the schema moved forward; the reverted code must tolerate it" — the
# forward-only migration discipline means a code rollback is not a data rollback.
#
# Never: merges, calls the rollback endpoint, force-pushes, rewrites history, or touches
# production. RESULT: PREPARED <what> is a description of files and commands, not of a state.
#
# Usage:
#   .icm/scripts/rollback.sh <slug> [--revert] [--vercel] [--dry-run]
#   .icm/scripts/rollback.sh --sha <merge-sha> [--revert] [--vercel] [--dry-run]
#   (at least one of --revert / --vercel; --dry-run prints what would be prepared and writes nothing)
#
# Verdict (stdout, last line):
#   RESULT: PREPARED <revert PR #n | vercel rollback for p1, p2 | …>   exit 0
#   RESULT: DRY-RUN <the same>                                          exit 0
#   RESULT: SKIP                                                        exit 0  — --vercel with no deploy block
set -euo pipefail

command -v git >/dev/null || { echo "git not found" >&2; exit 1; }
command -v jq  >/dev/null || { echo "jq not found"  >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { echo "error: $*" >&2; exit 1; }

slug=""; sha=""; do_revert=0; do_vercel=0; dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --sha)     sha="${2:-}"; shift 2 ;;
    --revert)  do_revert=1; shift ;;
    --vercel)  do_vercel=1; shift ;;
    --dry-run) dry=1; shift ;;
    --*)       die "unknown flag: $1" ;;
    *)         [ -z "$slug" ] && slug="$1" || die "unexpected argument: $1"; shift ;;
  esac
done
[ -n "$slug" ] || [ -n "$sha" ] || die "usage: rollback.sh <slug> | --sha <merge-sha> [--revert] [--vercel] [--dry-run]"
[ "$do_revert" -eq 1 ] || [ "$do_vercel" -eq 1 ] || die "name at least one recovery: --revert and/or --vercel"

# shellcheck source=lib/project.sh
source "$here/lib/project.sh"

git_c() { git -C "$repo_root" "$@"; }

# --- the merge commit ---------------------------------------------------------------------------------------

if [ -z "$sha" ]; then
  run_md="$repo_root/.icm/runs/$slug/run.md"
  [ -f "$run_md" ] || run_md="$repo_root/$runs_archive_rel/$slug/run.md"
  [ -f "$run_md" ] || die "no run.md for '$slug' — pass --sha <merge-sha>"
  pr="$(grep -m1 '^- pr:' "$run_md" | sed -E 's/^- pr:[[:space:]]*//; s/[[:space:]]+#.*$//; s#^.*/pull/##; s/^#//; s/[^0-9].*$//' || true)"
  [ -n "$pr" ] || die "run.md for '$slug' has no usable '- pr:' line — pass --sha <merge-sha>"
  # shellcheck source=lib/gh.sh
  source "$here/lib/gh.sh"
  gh_require "reading PR #$pr"
  resp="$(gh_api GET "/repos/${repo}/pulls/${pr}")" || exit 1
  [ "$(printf '%s' "$resp" | tail -n1)" = "200" ] || die "PR #$pr returned HTTP $(printf '%s' "$resp" | tail -n1)"
  [ "$(printf '%s' "$resp" | sed '$d' | jq -r '.merged')" = "true" ] || die "PR #$pr has not merged — there is nothing on main to roll back"
  sha="$(printf '%s' "$resp" | sed '$d' | jq -r '.merge_commit_sha')"
fi
[ -z "$slug" ] && slug="${sha:0:7}"
git_c fetch origin main --quiet 2>/dev/null || die "git fetch origin main failed — the revert must be cut from current main"
git_c cat-file -e "${sha}^{commit}" 2>/dev/null || die "commit $sha is not in this clone (fetch it first)"
short="${sha:0:7}"
prepared=()

# --- did the merge carry a migration? --------------------------------------------------------------------

changed="$(git_c diff-tree --no-commit-id --name-only -r "$sha" 2>/dev/null || true)"
mig_hit=""
while IFS= read -r p; do
  [ -n "$p" ] || continue
  hit="$(printf '%s\n' "$changed" | grep -E "^${p%/}/" || true)"
  [ -z "$hit" ] || mig_hit="${mig_hit:+$mig_hit, }$(printf '%s' "$hit" | head -3 | paste -sd',' -)"
done < <(migrations_paths; printf '%s\n' "$changed" | grep -iE '(^|/)migrations?/' | xargs -rn1 dirname 2>/dev/null | sort -u)
if [ -n "$mig_hit" ]; then
  if [ "$(migrations_reversible)" = "true" ]; then
    echo "[WARN] the merge $short carried a migration ($mig_hit); migrations.reversible is true — run its down alongside the revert, and say so in the hotfix notes"
  else
    echo "[WARN] the merge $short carried a migration ($mig_hit) and migrations.reversible is false: the schema moved forward; the reverted code must tolerate it. A code revert is not a data rollback."
  fi
fi

# --- --revert: a branch, a lane run folder, a READY hotfix PR ----------------------------------------------

if [ "$do_revert" -eq 1 ]; then
  rslug="hotfix-revert-${slug}"
  branch="claude/${rslug}"
  if [ "$dry" -eq 1 ]; then
    echo "would: git checkout -b $branch origin/main && git revert -m 1 $sha && write .icm/runs/$rslug/lane/output/notes.md && new-run.sh $rslug --lane hotfix --summary \"Revert $slug ($short)\""
    prepared+=("revert branch $branch (dry run)")
  else
    [ -z "$(git_c status --porcelain)" ] || die "working tree is not clean — commit or set aside your changes before preparing a revert"
    git_c rev-parse --verify --quiet "refs/heads/$branch" >/dev/null && die "branch $branch already exists — a revert was already prepared; resolve it first"
    git_c checkout -q -b "$branch" origin/main
    if ! git_c revert --no-edit -m 1 "$sha" >/dev/null 2>&1; then
      # A squash-merge is a plain commit, not a merge — retry without -m.
      git_c revert --abort >/dev/null 2>&1 || true
      git_c revert --no-edit "$sha" >/dev/null 2>&1 || die "git revert $sha did not apply cleanly on origin/main — resolve by hand on $branch, then run new-run.sh $rslug --lane hotfix"
    fi
    mkdir -p "$repo_root/.icm/runs/$rslug/lane/output"
    cat > "$repo_root/.icm/runs/$rslug/lane/output/notes.md" <<NOTES
# Hotfix: $rslug

- incident: <what broke, when, who reported — fill in before the merge>
- recovery: revert $sha
- migration: ${mig_hit:+carried by the merge ($mig_hit) — schema moved forward; reversible: $(migrations_reversible)}${mig_hit:-none in the merge}
- changelog: audience: internal
NOTES
    "$here/new-run.sh" "$rslug" --lane hotfix --summary "Revert $slug ($short) — production recovery" \
      --steps $'1. Open the production-app preview the lane reported and confirm the fault is gone\n2. Squash-merge from GitHub — the merge button is the gate' \
      || die "new-run.sh could not open the hotfix PR — the branch $branch carries the revert; open it by hand with new-run.sh"
    prepared+=("revert PR on $branch")
  fi
fi

# --- --vercel: the previous READY deployment and the exact call -------------------------------------------

if [ "$do_vercel" -eq 1 ]; then
  # shellcheck source=lib/vercel.sh
  source "$here/lib/vercel.sh"
  if ! vercel_declared; then
    echo "production: not declared (no deploy block) — nothing to name for --vercel"
    [ "${#prepared[@]}" -gt 0 ] || { echo "RESULT: SKIP"; exit 0; }
  else
    vercel_require "naming the previous deployment"
    team="$(deploy_team)"
    while IFS= read -r pj; do
      [ -n "$pj" ] || continue
      name="$(printf '%s' "$pj" | jq -r '.name')"
      class="$(printf '%s' "$pj" | jq -r '.class // "product"')"
      [ "$class" = "product" ] || continue
      id="$(vercel_project_id "$name")"
      deps="$(vercel_deployments "$name" --target production --limit 20)"
      cur="$(printf '%s' "$deps" | jq -r --arg s "$sha" '[.[] | select((.meta.githubCommitSha // "") == $s)] | sort_by(-.created) | first | (.uid // .id) // empty')"
      prev="$(printf '%s' "$deps" | jq -r --arg s "$sha" '[.[] | select(((.state // .readyState) == "READY") and ((.meta.githubCommitSha // "") != $s))] | sort_by(-.created) | first | (.uid // .id) // empty')"
      echo "$name: current ${cur:-<not found for $short>} · previous READY ${prev:-<none found in the last 20>}"
      if [ -n "$prev" ]; then
        echo "  CLI : vercel rollback $prev${team:+ --scope $team}"
        echo "  REST: POST ${VERCEL_API}/v1/projects/${id}/rollback/${prev}${team:+?teamId=$team}   (Authorization: Bearer \$${vercel_token_name})"
        prepared+=("vercel rollback for $name")
      fi
    done < <(deploy_projects)
  fi
fi

echo "Nothing was merged, promoted or rolled back — the recovery above is prepared for a human to take."
if [ "$dry" -eq 1 ]; then echo "RESULT: DRY-RUN $(printf '%s; ' "${prepared[@]}" | sed 's/; $//')"
else echo "RESULT: PREPARED $(printf '%s; ' "${prepared[@]}" | sed 's/; $//')"; fi
