#!/usr/bin/env bash
# promote-uat.sh — the UAT batch: what is on it, the client's sign-off, the promotion to production (TEMPLATE-OWNED).
#
# Only where the repo declares a UAT environment (.icm/project.json → uat: {branch, url} — /setup
# asks; decision D31; the contract is .icm/uat/CONTEXT.md). Without one every verb prints one line
# and `RESULT: SKIP`, exit 0: the run's PR targets main and Release ships to production directly,
# as it always did.
#
# The UAT environment is PERSISTENT: one long-lived branch (`uat` by convention) that every run's
# PR targets instead of main, deployed by Vercel like any branch and reachable at ONE fixed address
# — a domain assigned to that branch in the project's settings, or the branch alias — the same
# address every day, never a per-batch preview. What is on it at any moment is the BATCH: the runs
# squash-merged into the branch since the last promotion, recorded by close-out.sh in
# .icm/uat/batch.json (`stubs`), a file that lives on the UAT branch itself. The client tests the
# batch as a whole; the operator records the client's sign-off; the batch reaches production as
# ONE promotion PR the operator merges from GitHub. Nothing here merges anything.
#
# Verbs:
#   status                  the batch as the UAT branch holds it, cross-checked against git (runs
#                           archived on the UAT branch and not on main), the fixed address, the
#                           sign-off state, an open promotion PR if there is one, and how far main
#                           has moved ahead (a hotfix or knowledge-lane change UAT lacks). Read-only.
#                                                        RESULT: UAT <n> stub(s) · <state> · main ahead <k>
#   init                    writes .icm/uat/batch.json when missing and prints the one-time checklist
#                           the OPERATOR completes by hand — push the branch once, protect it like
#                           main, point a domain at it in Vercel, add the type:promote label. Creates
#                           no branch and touches no service. Idempotent.  RESULT: INIT | UNCHANGED
#   approve --by "<who>" [--note "<text>"] [--dry-run]
#                           THE OPERATOR'S ACT — the client said yes, and this records it. Cuts
#                           `claude/promote-uat-<date>` from origin/<uat>, brings origin/main in (a
#                           merge commit; a conflict STOPs), writes the sign-off into batch.json
#                           (client_approved, approved_by, approved_on, approved_head — the UAT head
#                           that was approved; a run merged after it is the next batch's), writes the
#                           promote lane run's notes, opens the promotion PR READY into main through
#                           new-run.sh (the only script that opens a PR; label type:promote), closes
#                           the run out on the branch, pushes, and STOPS. The operator merges from
#                           GitHub. Refuses an empty batch, a dirty tree, an approval without --by.
#                                                                          RESULT: OPENED #<pr>
#   sync [--dry-run]        AFTER the promotion PR merged — and, REQUIRED, after any hotfix or
#                           knowledge-lane change that merged into main: until it runs, the board
#                           (which reads the UAT branch — the ticket base branch, D38) shows that
#                           work's stub as open. Brings origin/main into the UAT branch in a throwaway worktree
#                           (one merge commit; when that merge carries an approved batch that reached
#                           production, batch.json is reset for the next batch in the same commit, the
#                           promotion logged under `promotions`), pushes the UAT branch, and — where
#                           reporting.announce_from is `session` and a promotion landed — announces it
#                           through report.sh; where it is `ci`, the release workflow already did. A
#                           conflict STOPs with the resolution named.   RESULT: SYNCED <k> | UP-TO-DATE
#
# What never happens here: no verb merges a PR, ticks a gate, or decides that the client approved.
# `approve` is run by the operator — or by a session the operator told, in that session, that the
# client approved and who said so — never inferred from a message, a comment or a file. No verb
# creates the UAT branch, protects it or touches Vercel: those are the operator's one-time acts, and
# `init` lists them. Nothing is scheduled; nothing watches.
#
# Config: .icm/project.json through lib/project.sh (uat.branch, uat.url, deploy, reporting, the
# archive path). GitHub through lib/gh.sh — for `approve` (new-run.sh) and, optionally, to name an
# open promotion PR in `status` and `sync`. Nothing outside the repo is read.
#
# Usage: .icm/scripts/promote-uat.sh <status|init|approve|sync> [--by "<who>"] [--note "<text>"] [--dry-run]
# Exit:  0 reported, prepared or skipped · 2 usage / a tool missing / a failed git step · 3 STOP (a refusal, named on stderr)
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root" || exit 2
die()  { echo "error: $*" >&2; exit 2; }
stop() { echo "$*" >&2; echo "RESULT: STOP"; exit 3; }
command -v jq  >/dev/null 2>&1 || die "jq not found"
command -v git >/dev/null 2>&1 || die "git not found"

verb="${1:-}"; shift || true
by=""; note=""; dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --by)      by="${2:-}"; shift 2 ;;
    --note)    note="${2:-}"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    -h|--help) sed -n '2,52p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown argument: $1 (usage: promote-uat.sh <status|init|approve|sync> [--by \"<who>\"] [--note \"<text>\"] [--dry-run])" ;;
  esac
done
case "$verb" in status|init|approve|sync) : ;; -h|--help) sed -n '2,52p' "${BASH_SOURCE[0]}"; exit 0 ;; *) die "usage: promote-uat.sh <status|init|approve|sync> [--by \"<who>\"] [--note \"<text>\"] [--dry-run]" ;; esac

# shellcheck source=lib/project.sh
source "$here/lib/project.sh"

if ! uat_declared; then
  echo "no UAT environment is declared in .icm/project.json (uat.branch is empty) — every run merges into main and Release ships it on the merge; /setup declares one (.icm/uat/CONTEXT.md)"
  echo "RESULT: SKIP"; exit 0
fi
ub="$(uat_branch)"; uu="$(uat_url)"; bf=".icm/uat/batch.json"; archive="$runs_archive_rel"
today="$(date -u +%F)"
git_c()   { git -C "$repo_root" "$@"; }
fetch()   { GIT_TERMINAL_PROMPT=0 git_c fetch origin --quiet >/dev/null 2>&1; }
has_ref() { git_c rev-parse --verify -q "$1" >/dev/null 2>&1; }
empty_batch='{stubs: [], client_approved: false, approved_by: "", approved_on: "", approved_head: "", approved_note: "", promotions: []}'

# --- small readers ----------------------------------------------------------------------------------------
read_at()    { if [ -n "$1" ]; then git_c show "$1:$2" 2>/dev/null; else [ -f "$2" ] && cat "$2"; fi; return 0; }
ls_dirs_at() { if [ -n "$1" ]; then git_c ls-tree --name-only -d "$1:${2%/}" 2>/dev/null; else local d; for d in "$2"/*/; do [ -d "$d" ] && basename "$d"; done; fi; return 0; }
h1_title()   { awk '/^# / { sub(/^# +/, ""); sub(/^[A-Za-z]+: +/, ""); print; exit }'; }
humanise()   { printf '%s' "$1" | sed -E 's/[-_]+/ /g' | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }'; }
title_at() { # <ref> <slug> → the run's title from its spec, else the slug in words
  local sub t=""
  while IFS= read -r sub; do
    case "$sub" in *define) t="$(read_at "$1" "$archive/$2/$sub/output/spec.md" | h1_title)"; [ -n "$t" ] && break ;; esac
  done < <(ls_dirs_at "$1" "$archive/$2")
  [ -n "$t" ] && printf '%s' "$t" || humanise "$2"
}
batch_at() { # <ref> → batch.json as JSON, '{}' when absent or invalid
  local j; j="$(read_at "$1" "$bf")"
  if printf '%s' "$j" | jq -e . >/dev/null 2>&1; then printf '%s' "$j"; else printf '{}'; fi
}
stubs_of() { printf '%s' "$1" | jq -r '(.stubs // [])[] | if type == "object" then (.slug // empty) else . end'; }
# A merge of main that conflicts ONLY on batch.json is settled here, not by the operator: the file
# is this script's to rewrite (approve and sync both overwrite it), and the UAT branch is where the
# batch is true — main's copy is a promotion's snapshot, stale by design once the promotion PR was
# squash-merged. Anything else in conflict is the operator's, and the merge is aborted.
batch_only_conflict() { # <git dir args...> → 0 when the only conflicted path is batch.json, resolved with ours
  local conflicted; conflicted="$(git "$@" diff --name-only --diff-filter=U 2>/dev/null)"
  [ "$conflicted" = "$bf" ] || return 1
  git "$@" checkout --ours -- "$bf" >/dev/null 2>&1 && git "$@" add "$bf" >/dev/null 2>&1
}
# GitHub is optional here: a route when there is one, silence when not (never a die from status).
gh_ok=0; gh_repo=""
gh_probe() {
  git_c remote get-url origin >/dev/null 2>&1 || return 1
  # shellcheck source=lib/gh.sh
  source "$here/lib/gh.sh" 2>/dev/null || return 1
  gh_repo="$repo"
  if [ -n "${gh_token:-}" ] || (command -v gh >/dev/null 2>&1 && env -u GITHUB_TOKEN -u GH_TOKEN gh auth status >/dev/null 2>&1); then gh_ok=1; fi
  [ "$gh_ok" -eq 1 ]
}
open_promotion_pr() { # → "<number>\t<url>\t<head>" of an open claude/promote-uat-* PR, or nothing
  [ "$gh_ok" -eq 1 ] || return 0
  local resp
  resp="$(gh_api GET "/repos/${gh_repo}/pulls?state=open&per_page=50" 2>/dev/null)" || return 0
  [ "$(printf '%s' "$resp" | tail -n1)" = "200" ] || return 0
  printf '%s' "$resp" | sed '$d' | jq -r '[.[] | select(.head.ref | startswith("claude/promote-uat-"))] | first // empty | "\(.number)\t\(.html_url)\t\(.head.ref)"' 2>/dev/null
}

# ===========================================================================================================
case "$verb" in

# --- init ---------------------------------------------------------------------------------------------------
init)
  changed=0
  if [ -f "$bf" ]; then
    jq -e . "$bf" >/dev/null 2>&1 && echo "$bf present ($(jq -r '(.stubs // []) | length' "$bf") stub(s) in the batch)" || die "$bf exists but is not valid JSON — fix it by hand"
  else
    mkdir -p .icm/uat; jq -n "$empty_batch" > "$bf"; changed=1; echo "created $bf (empty batch) — commit it (a words-only .icm/ commit)"
  fi
  fetch || echo "note: git fetch origin failed — the branch check below reads the refs as last fetched" >&2
  echo
  echo "One-time setup the operator completes by hand (this script does none of it):"
  if has_ref "origin/$ub"; then echo "  [OK]   branch $ub exists on origin"; else echo "  [TODO] create the branch once, from main:   git push origin main:$ub"; fi
  echo "  [TODO] protect $ub like main — the same required status checks (PRs into it carry them) — and allow the operator's own identity to push to it directly (sync pushes one merge commit)"
  if [ -n "$uu" ]; then echo "  [TODO] Vercel → the product project(s) → Settings → Domains: add the host of $uu and assign it to the git branch '$ub' — the address never changes, the deployment under it does"
  else echo "  [TODO] uat.url is empty in .icm/project.json — the fixed address the client opens (a domain assigned to the branch '$ub' in Vercel, or the branch alias)"; fi
  if [ "$(database_provider)" = neon ] && [ -n "$(neon_uat_branch)" ]; then
    echo "  [INFO] the UAT branch's database is the Neon branch $(neon_uat_branch), created by the Vercel integration on the branch's first deployment (a copy of production then; the build applies the branch's migrations) — .icm/scripts/db-env.sh status reads it, db-env.sh init lists the integration toggle, db-env.sh reset-uat resets it from production"
  else
    echo "  [TODO] the UAT branch deploys on the PREVIEW environment's variables unless a custom environment is attached to it in Vercel — decide which data the client tests against (a Neon project with previews: vercel gives it a branch of its own — .icm/uat/CONTEXT.md → The UAT database)"
  fi
  if [ -f .github/labels.yml ] && grep -q 'type:promote' .github/labels.yml; then echo "  [OK]   type:promote in .github/labels.yml"; else echo "  [TODO] add type:promote to .github/labels.yml and create the label in GitHub once (new-run.sh dies without it)"; fi
  echo "  [TODO] if a ruleset on $ub requires status checks, keep the admin bypass on it — a ticket PR (only .icm/ markdown) merges into $ub at once through it, waiting for no check (D38; the pr-conventions skill → The ticket PR)"
  echo "  [INFO] run branches are cut from origin/$ub (with origin/main brought in); PRs target $ub; tickets are cut and closed on $ub (the ticket base branch, D38); production is one promotion PR per batch — .icm/uat/CONTEXT.md"
  [ "$changed" -eq 1 ] && echo "RESULT: INIT" || echo "RESULT: UNCHANGED"
  exit 0 ;;

# --- status -------------------------------------------------------------------------------------------------
status)
  fetch || echo "note: git fetch origin failed — reading the refs as last fetched" >&2
  ref="origin/$ub"
  if ! has_ref "$ref"; then
    echo "UAT: $uu — branch '$ub' does not exist on origin yet (promote-uat.sh init lists the one-time steps)"
    echo "RESULT: UAT 0 stub(s) · no branch"; exit 0
  fi
  head_full="$(git_c rev-parse "$ref")"; head_short="${head_full:0:7}"
  bj="$(batch_at "$ref")"
  [ "$bj" != "{}" ] || echo "[WARN] no valid $bf on $ub — promote-uat.sh init writes it; commit it to $ub (or let the first close-out carry it)" >&2
  mapfile -t stubs < <(stubs_of "$bj")
  echo "UAT: ${uu:-<uat.url empty>} — branch $ub at $head_short"
  echo "batch ($bf on $ub): ${#stubs[@]} stub(s)"
  declare -A in_batch=()
  for s in "${stubs[@]+"${stubs[@]}"}"; do
    in_batch[$s]=1
    if git_c cat-file -e "$ref:$archive/$s/run.md" 2>/dev/null; then echo "  - $s — $(title_at "$ref" "$s")"
    else echo "  - $s — $(humanise "$s")   [WARN] in batch.json but no archived run on $ub"; fi
  done
  if has_ref origin/main; then
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      [ -n "${in_batch[$s]:-}" ] && continue
      git_c cat-file -e "origin/main:$archive/$s/run.md" 2>/dev/null && continue
      echo "  - $s — $(title_at "$ref" "$s")   [WARN] archived on $ub, not on main, not in batch.json — on UAT all the same (close-out.sh adds a run when its PR targets $ub)"
    done < <(ls_dirs_at "$ref" "$archive")
  fi
  approved="$(printf '%s' "$bj" | jq -r '.client_approved // false')"
  if [ "$approved" = "true" ]; then
    a_by="$(printf '%s' "$bj" | jq -r '.approved_by // ""')"; a_on="$(printf '%s' "$bj" | jq -r '.approved_on // ""')"; a_head="$(printf '%s' "$bj" | jq -r '.approved_head // ""')"
    if [ "$a_head" = "$head_full" ]; then echo "sign-off: approved by ${a_by:-?} on ${a_on:-?} at $head_short (the current head)"
    else echo "sign-off: approved by ${a_by:-?} on ${a_on:-?} at ${a_head:0:7} — $ub has moved since ($(git_c rev-list --count "${a_head}..$ref" 2>/dev/null || echo '?') newer commit(s)); a promotion cut at that approval does not carry them"; fi
    state="approved"
  else
    echo "sign-off: not yet — the client has not signed this batch off (when they do: .icm/scripts/promote-uat.sh approve --by \"<who>\")"
    state="unapproved"
  fi
  if gh_probe; then
    pr="$(open_promotion_pr)"
    if [ -n "$pr" ]; then echo "promotion PR: #${pr%%$'\t'*} open ($(printf '%s' "$pr" | cut -f2)) — merge it from GitHub, then: .icm/scripts/promote-uat.sh sync"; fi
  fi
  ahead=0; behind=0
  if has_ref origin/main; then
    ahead="$(git_c rev-list --count "$ref..origin/main" 2>/dev/null || echo 0)"
    behind="$(git_c rev-list --count "origin/main..$ref" 2>/dev/null || echo 0)"
    [ "$ahead" -gt 0 ] && echo "main is ahead of $ub by $ahead commit(s) — a hotfix or a knowledge-lane change UAT lacks, and the board shows its stub open until it lands: .icm/scripts/promote-uat.sh sync brings them in (the next run's new-run.sh does too)"
    if [ "$behind" -gt 0 ]; then
      if [ "${#stubs[@]}" -gt 0 ]; then echo "$ub is ahead of main by $behind commit(s) — the batch, waiting for the promotion"
      else echo "$ub is ahead of main by $behind commit(s) — bookkeeping only (a sync's merge and the batch reset); the batch is empty"; fi
    fi
  fi
  echo "RESULT: UAT ${#stubs[@]} stub(s) · $state · main ahead $ahead"
  exit 0 ;;

# --- approve ------------------------------------------------------------------------------------------------
approve)
  [ -n "$by" ] || die "--by \"<who signed off>\" is required — the approval is the client's word, recorded by the operator (never inferred)"
  fetch || die "git fetch origin failed — the promotion cuts from origin/$ub and needs the network"
  has_ref "origin/$ub" || stop "branch '$ub' does not exist on origin — promote-uat.sh init lists the one-time steps; nothing to promote"
  has_ref origin/main || die "origin/main does not resolve"
  ref="origin/$ub"
  bj="$(batch_at "$ref")"
  mapfile -t stubs < <(stubs_of "$bj")
  [ "${#stubs[@]}" -gt 0 ] || stop "the batch is empty — nothing has merged into $ub since the last promotion (promote-uat.sh status)"
  head_full="$(git_c rev-parse "$ref")"; head_short="${head_full:0:7}"
  if [ "$(printf '%s' "$bj" | jq -r '.client_approved // false')" = "true" ] && [ "$(printf '%s' "$bj" | jq -r '.approved_head // ""')" = "$head_full" ]; then
    stop "this batch is already approved at $head_short by $(printf '%s' "$bj" | jq -r '.approved_by // "?"') — the promotion PR should be open (promote-uat.sh status names it); after it merges, promote-uat.sh sync"
  fi
  cur="$(git_c symbolic-ref --quiet --short HEAD || true)"
  slug="promote-uat-$today"
  if has_ref "origin/claude/$slug" || [ -d ".icm/runs/$slug" ] || git_c cat-file -e "origin/main:$archive/$slug/run.md" 2>/dev/null; then slug="promote-uat-$today-$(date -u +%H%M)"; fi
  branch="claude/$slug"
  titles=(); for s in "${stubs[@]}"; do titles+=("$(title_at "$ref" "$s")"); done
  summary="UAT batch of $today approved by $by: ${#stubs[@]} change(s) — $(printf '%s; ' "${titles[@]}" | sed 's/; $//')"
  [ "${#summary}" -le 240 ] || summary="${summary:0:237}…"
  if [ "$dry" -eq 1 ]; then
    echo "would: git checkout -b $branch $ref && git merge --no-edit origin/main"
    echo "would: write $bf → client_approved true, approved_by \"$by\", approved_on $today, approved_head $head_short${note:+, approved_note \"$note\"}"
    echo "would: write .icm/runs/$slug/lane/output/notes.md listing the batch, then new-run.sh $slug --lane promote --ready --base main --summary \"$summary\""
    echo "would: close-out.sh $slug, push $branch, and stop — the operator merges from GitHub"
    echo "RESULT: DRY-RUN"; exit 0
  fi
  dirty="$(git_c status --porcelain 2>/dev/null || true)"
  [ -z "$dirty" ] || stop "the working tree has uncommitted changes — approve switches branches; commit or discard first:"$'\n'"$dirty"
  git_c checkout -q -b "$branch" "$ref" || die "could not create $branch from $ref"
  restore() { [ -n "$cur" ] && git_c checkout -q "$cur" 2>/dev/null || true; }
  if ! git_c merge --no-edit origin/main >/dev/null 2>&1; then
    if batch_only_conflict -C "$repo_root" && git_c commit -q --no-edit >/dev/null 2>&1; then
      echo "note: $bf differed on main (a squash-merged promotion leaves its snapshot there) — kept the UAT branch's copy; the approval rewrites it" >&2
    else
      git_c merge --abort >/dev/null 2>&1 || true; restore; git_c branch -D "$branch" >/dev/null 2>&1 || true
      stop "origin/main does not merge cleanly into $ub — resolve that on the UAT branch first (promote-uat.sh sync merges main into $ub; a conflict there is the operator's, on $ub), then approve again"
    fi
  fi
  tmpf="$(mktemp)"
  jq --arg by "$by" --arg on "$today" --arg head "$head_full" --arg note "$note" \
     '.client_approved = true | .approved_by = $by | .approved_on = $on | .approved_head = $head | .approved_note = $note | .promotions = (.promotions // [])' \
     <<<"$( [ -f "$bf" ] && cat "$bf" || jq -n "$empty_batch")" > "$tmpf" || { rm -f "$tmpf"; restore; die "could not write $bf"; }
  mkdir -p "$(dirname "$bf")"; mv "$tmpf" "$bf"
  mkdir -p ".icm/runs/$slug/lane/output"
  {
    echo "# Promote: $slug"
    echo
    echo "- approved-by: $by"
    echo "- approved-on: $today"
    echo "- uat-head: $head_short"
    echo "- url: ${uu:-<uat.url empty>}"
    echo "- note: ${note:-none}"
    echo
    echo "## Batch"
    echo
    i=0; for s in "${stubs[@]}"; do echo "- $s — ${titles[$i]}"; i=$((i + 1)); done
    echo
    echo "## After the merge"
    echo
    echo "- \`.icm/scripts/promote-uat.sh sync\` — $ub takes main, the batch resets, the promotion is announced (session repos)"
    echo "- \`.icm/scripts/deploy-status.sh --sha <merge-sha>\` — one read of production, the operator's call"
  } > ".icm/runs/$slug/lane/output/notes.md"
  git_c add "$bf" && git_c commit -q -m "chore: $slug — UAT batch approved by $by (${#stubs[@]} change(s))" || { restore; die "could not commit the approval"; }
  steps="1. The client signed this batch off on UAT (${uu:-the UAT address}) — approved by $by on $today; nothing further to smoke-test."$'\n'"2. Merge from GitHub (a merge commit keeps $ub and main sharing history; a squash also works), then run .icm/scripts/promote-uat.sh sync."
  if ! "$here/new-run.sh" "$slug" --lane promote --ready --base main --title "Promote the UAT batch of $today to production" --summary "$summary" --steps "$steps"; then
    if grep -qE '^- pr:' ".icm/runs/$slug/run.md" 2>/dev/null; then
      echo "[WARN] new-run.sh opened the PR but did not finish (the type:promote label is the usual cause — create it in GitHub, then .icm/scripts/project-labels.sh is not for lanes: PUT it by hand or leave it); carrying on" >&2
    else
      restore; die "new-run.sh could not open the promotion PR — read its message; the branch $branch keeps the approval commit"
    fi
  fi
  "$here/close-out.sh" "$slug" || { restore; die "close-out.sh could not archive the promote run — fix and re-run close-out.sh $slug on $branch, then push"; }
  git_c push -q origin "$branch" || { restore; die "git push $branch failed after the close-out — push it by hand"; }
  pr_line="$(grep -m1 '^- pr:' "$archive/$slug/run.md" 2>/dev/null | grep -oE '[0-9]+' | head -n1 || true)"
  restore
  gh_probe >/dev/null 2>&1 || true
  echo "promotion PR opened READY${pr_line:+: #$pr_line}${gh_repo:+ — https://github.com/$gh_repo/pull/${pr_line:-}} (branch $branch → main; batch of ${#stubs[@]} approved by $by at $head_short)"
  echo "next: the operator merges it from GitHub; then .icm/scripts/promote-uat.sh sync"
  echo "RESULT: OPENED #${pr_line:-?}"
  exit 0 ;;

# --- sync ---------------------------------------------------------------------------------------------------
sync)
  fetch || die "git fetch origin failed — sync compares origin/main with origin/$ub and needs the network"
  has_ref "origin/$ub" || stop "branch '$ub' does not exist on origin — promote-uat.sh init lists the one-time steps"
  has_ref origin/main || die "origin/main does not resolve"
  ref="origin/$ub"
  ahead="$(git_c rev-list --count "$ref..origin/main" 2>/dev/null || echo 0)"
  main_bj="$(batch_at origin/main)"; uat_bj="$(batch_at "$ref")"
  promo_head="$(printf '%s' "$main_bj" | jq -r 'if (.client_approved // false) == true then (.approved_head // "") else "" end')"
  landed=0
  if [ -n "$promo_head" ] && ! printf '%s' "$uat_bj" | jq -e --arg h "$promo_head" '(.promotions // []) | map(.head) | index($h)' >/dev/null 2>&1; then landed=1; fi
  if [ "$ahead" -eq 0 ] && [ "$landed" -eq 0 ]; then
    echo "$ub already carries main (nothing to bring in; no promotion to log)"
    echo "RESULT: UP-TO-DATE"; exit 0
  fi
  promo_by=""; promo_on=""; promo_pr=""; promo_url=""; promo_stubs="[]"
  if [ "$landed" -eq 1 ]; then
    promo_by="$(printf '%s' "$main_bj" | jq -r '.approved_by // ""')"; promo_on="$(printf '%s' "$main_bj" | jq -r '.approved_on // ""')"
    promo_stubs="$(printf '%s' "$main_bj" | jq -c '(.stubs // [])')"
    # The promote run archived on main names the PR: match its uat-head line to the approved head.
    while IFS= read -r name; do
      case "$name" in promote-uat-*) : ;; *) continue ;; esac
      h="$(read_at origin/main "$archive/$name/lane/output/notes.md" | awk '/^- uat-head:/ { print $3; exit }')"
      [ "$h" = "${promo_head:0:7}" ] || continue
      promo_pr="$(read_at origin/main "$archive/$name/run.md" | grep -m1 '^- pr:' | grep -oE '[0-9]+' | head -n1 || true)"
      break
    done < <(ls_dirs_at origin/main "$archive")
    gh_probe >/dev/null 2>&1 || true
    [ -n "$promo_pr" ] && [ -n "$gh_repo" ] && promo_url="https://github.com/$gh_repo/pull/$promo_pr"
  fi
  if [ "$dry" -eq 1 ]; then
    echo "would: merge origin/main into $ub ($ahead commit(s)) in a throwaway worktree and push $ub"
    [ "$landed" -eq 1 ] && echo "would: reset $bf for the next batch, logging the promotion of ${promo_on:-?} by ${promo_by:-?} (head ${promo_head:0:7}${promo_pr:+, PR #$promo_pr}) under promotions; stubs $promo_stubs leave the batch"
    echo "RESULT: DRY-RUN"; exit 0
  fi
  tmp="$(mktemp -d)"
  cleanup() { git_c worktree remove --force "$tmp" >/dev/null 2>&1 || rm -rf "$tmp"; }
  git_c worktree add --detach -q "$tmp" "$ref" || { rm -rf "$tmp"; die "could not create a worktree at $ref"; }
  if [ "$ahead" -gt 0 ] && ! git -C "$tmp" merge --no-commit --no-ff origin/main >/dev/null 2>&1; then
    if batch_only_conflict -C "$tmp"; then
      echo "note: $bf differed on main (a squash-merged promotion leaves its snapshot there) — kept the UAT branch's copy" >&2
    else
      git -C "$tmp" merge --abort >/dev/null 2>&1 || true; cleanup
      stop "origin/main does not merge cleanly into $ub — resolve it by hand on the UAT branch: git checkout $ub && git merge origin/main (keep $ub's newer stubs in $bf and main's promotions), then push"
    fi
  fi
  msg="chore: $ub takes main — $ahead commit(s)"
  if [ "$landed" -eq 1 ]; then
    tmpf="$(mktemp)"
    jq --arg on "$today" --arg by "$promo_by" --arg head "$promo_head" --arg pr "${promo_pr:-}" --arg aon "$promo_on" --argjson promoted "$promo_stubs" \
       '.promotions = ((.promotions // []) + [{promoted_on: $on, approved_on: $aon, approved_by: $by, head: $head, pr: $pr, stubs: $promoted}])
        | .stubs = ((.stubs // []) - $promoted) | .client_approved = false | .approved_by = "" | .approved_on = "" | .approved_head = "" | .approved_note = ""' \
       <<<"$( [ -f "$tmp/$bf" ] && cat "$tmp/$bf" || jq -n "$empty_batch")" > "$tmpf" || { rm -f "$tmpf"; cleanup; die "could not write $bf"; }
    mkdir -p "$tmp/$(dirname "$bf")"; mv "$tmpf" "$tmp/$bf"; git -C "$tmp" add "$bf" || { cleanup; die "could not stage $bf"; }
    msg="$msg; batch of ${promo_on:-?} promoted${promo_pr:+ (#$promo_pr)} — batch reset"
  fi
  if git -C "$tmp" diff --cached --quiet && [ "$ahead" -eq 0 ]; then cleanup; echo "nothing to commit"; echo "RESULT: UP-TO-DATE"; exit 0; fi
  git -C "$tmp" commit -q -m "$msg" || { cleanup; die "commit failed in the sync worktree"; }
  if ! git -C "$tmp" push -q origin "HEAD:refs/heads/$ub"; then
    cleanup; die "push to $ub refused — a ruleset on $ub blocks direct pushes: allow the operator's identity to bypass on $ub, or require no status checks there (the run PRs into it already carry them). The merge was not lost: repeat by hand with git checkout $ub && git merge origin/main && git push"
  fi
  new_head="$(git -C "$tmp" rev-parse --short HEAD)"; cleanup
  echo "$ub now at $new_head — $msg"
  if [ "$landed" -eq 1 ]; then
    merge_sha="$(git_c log -1 --format=%H origin/main -- "$bf" 2>/dev/null || true)"
    n="$(printf '%s' "$promo_stubs" | jq 'length')"
    titles=(); while IFS= read -r s; do [ -n "$s" ] && titles+=("$(title_at origin/main "$s")"); done < <(printf '%s' "$promo_stubs" | jq -r '.[]')
    summary="Production release — UAT batch approved by ${promo_by:-the client} on ${promo_on:-?}: $n change(s) — $(printf '%s; ' "${titles[@]+"${titles[@]}"}" | sed 's/; $//')"
    [ "${#summary}" -le 240 ] || summary="${summary:0:237}…"
    if [ "$(project_field .reporting.announce_from session)" = "ci" ]; then
      echo "announce: deferred to CI — the release workflow announced on the promotion merge (base branch main)"
    elif [ -x "$here/report.sh" ]; then
      "$here/report.sh" announce "$summary" --slug "promote-uat-${promo_on:-$today}" ${merge_sha:+--sha "$merge_sha"} ${promo_url:+--url "$promo_url"} || true
    else
      echo "announce: report.sh missing — nothing announced"
    fi
    echo "production: .icm/scripts/deploy-status.sh --sha ${merge_sha:0:7} — one read, when you want it; then .icm/scripts/health-check.sh --sha ${merge_sha:0:7} — the application's own word, once (Release skipped it on the UAT merge)"
    [ "$(database_provider)" = neon ] && [ -n "$(neon_uat_branch)" ] && echo "uat database: .icm/scripts/db-env.sh reset-uat --apply — when the client's test data should go and production's shape return (the operator's call; dry-run without --apply)"
  fi
  echo "RESULT: SYNCED $ahead commit(s)$( [ "$landed" -eq 1 ] && echo " · batch of ${promo_on:-?} promoted")"
  exit 0 ;;
esac
