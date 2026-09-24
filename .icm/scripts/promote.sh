#!/usr/bin/env bash
# promote.sh — the client's UAT, the batch, and the client's word recorded as a draft Release (TEMPLATE-OWNED).
#
# Only where the repo declares a UAT environment (.icm/project.json → uat: {target, url} — /setup
# asks; decision D39; the contract is .icm/_shared/promotion.md). Without one every verb prints one
# line and `RESULT: SKIP`, exit 0: every merge to main is the production release, as it always was.
#
# The model (D39): `main` is the only long-lived branch. Every merge deploys to the UAT custom
# environment `uat.target` (the one fixed address `uat.url`) and builds a STAGED production
# deployment that serves nothing until it is promoted. The BATCH is `git log <last published
# release>..origin/main` — no file records it. The client tests the batch at the address and gives
# their word; the operator records it with `approve`, which DRAFTS a GitHub Release at the signed-off
# SHA; the operator PUBLISHES that Release on GitHub; the repo's release workflow then migrates
# production, promotes the staged deployment of that SHA and announces. This script never
# publishes and never promotes.
#
# Verbs:
#   init                    the operator's one-time checklist, with what can be read here marked
#                           [OK]: the custom environment `uat.target` on each product project and its
#                           domain, Auto-assign Custom Production Domains OFF, the UAT database and its
#                           variables on the environment, the environment deploying main (branch
#                           tracking, or the reference uat-deploy.yaml), the release workflow and a
#                           callable db-migrate workflow, the Actions secrets. Performs none of it.
#                                                                                   RESULT: INIT
#   status                  the last published Release (tag, SHA), the batch since it (runs archived
#                           on origin/main since, by title; the merged PRs), the production deployment
#                           of origin/main's head and whether it is Current or Staged, the UAT
#                           deployment of that head, and any draft promotion Release. Read-only.
#                           RESULT: BATCH <n> change(s) since <tag|no release> · <no draft|draft <tag>>
#   approve --by "<who>" [--note "<text>"] [--sha <sha>] [--announce client|internal|none] [--dry-run]
#                           THE OPERATOR'S ACT — the client said yes, and this records it. Drafts a
#                           GitHub Release tagged `<tag_prefix><date>-promote-<sha7>` at <sha> (default
#                           origin/main's head) whose body carries who, when, the note, `announce:`,
#                           the SHA and the batch. Refuses: no --by; a SHA not on origin/main; a SHA
#                           already released; a draft promotion already open; a tag that exists.
#                           NEVER publishes, never promotes.                RESULT: DRAFTED <tag>
#
# What never happens here: no Release is published, no deployment is promoted, no Vercel setting is
# read beyond names or written, no branch is pushed, no gate is ticked. `approve` is run by the
# operator — or by a session the operator told, in that session, that the client approved and who
# said so — never inferred from a message, a comment or a file. Publishing is the operator's click.
#
# Config: .icm/project.json through lib/project.sh (uat, deploy, reporting → the tag prefix, the
# archive path). GitHub through lib/gh.sh (approve; status's draft line). Vercel through lib/vercel.sh
# (status and init, reads only, when a token is in reach). Nothing outside the repo is read.
#
# Usage: .icm/scripts/promote.sh <init|status|approve> [--by "<who>"] [--note "<text>"] [--sha <sha>]
#                                [--announce client|internal|none] [--dry-run]
# Exit:  0 reported, drafted or skipped · 2 usage / a tool missing · 3 STOP (a refusal, named on stderr)
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root" || exit 2
die()  { echo "error: $*" >&2; exit 2; }
stop() { echo "$*" >&2; echo "RESULT: STOP"; exit 3; }
command -v jq  >/dev/null 2>&1 || die "jq not found"
command -v git >/dev/null 2>&1 || die "git not found"

usage="usage: promote.sh <init|status|approve> [--by \"<who>\"] [--note \"<text>\"] [--sha <sha>] [--announce client|internal|none] [--dry-run]"
verb="${1:-}"; shift || true
by=""; note=""; sha_in=""; announce="client"; dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --by)       by="${2:-}"; shift 2 ;;
    --note)     note="${2:-}"; shift 2 ;;
    --sha)      sha_in="${2:-}"; shift 2 ;;
    --announce) announce="${2:-}"; shift 2 ;;
    --dry-run)  dry=1; shift ;;
    -h|--help)  sed -n '2,49p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown argument: $1 ($usage)" ;;
  esac
done
case "$verb" in init|status|approve) : ;; -h|--help) sed -n '2,49p' "${BASH_SOURCE[0]}"; exit 0 ;; *) die "$usage" ;; esac
case "$announce" in client|internal|none) : ;; *) die "--announce must be client|internal|none" ;; esac

# shellcheck source=lib/project.sh
source "$here/lib/project.sh"

if ! uat_declared; then
  echo "no UAT environment is declared in .icm/project.json (uat: {target, url}) — every merge to main is the production release; /setup declares one (_shared/promotion.md)"
  echo "RESULT: SKIP"; exit 0
fi
ut="$(uat_target)"; uu="$(uat_url)"; archive="$runs_archive_rel"
prefix="$(reporting_channel_field github-release tag_prefix 'release/')"
today="$(date -u +%F)"
git_c()   { git -C "$repo_root" "$@"; }
fetch()   { GIT_TERMINAL_PROMPT=0 git_c fetch origin --tags --quiet >/dev/null 2>&1; }
has_ref() { git_c rev-parse --verify -q "$1" >/dev/null 2>&1; }

# --- small readers -----------------------------------------------------------------------------------------
read_at()    { git_c show "$1:$2" 2>/dev/null; return 0; }
ls_dirs_at() { git_c ls-tree --name-only -d "$1:${2%/}" 2>/dev/null; return 0; }
h1_title()   { awk '/^# / { sub(/^# +/, ""); sub(/^[A-Za-z]+: +/, ""); print; exit }'; }
humanise()   { printf '%s' "$1" | sed -E 's/[-_]+/ /g' | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }'; }
title_at() { # <ref> <slug> → the run's title from its spec, else the slug in words
  local sub t=""
  while IFS= read -r sub; do
    case "$sub" in *define) t="$(read_at "$1" "$archive/$2/$sub/output/spec.md" | h1_title)"; [ -n "$t" ] && break ;; esac
  done < <(ls_dirs_at "$1" "$archive/$2")
  [ -n "$t" ] && printf '%s' "$t" || humanise "$2"
}
# The last published Release: the newest commit on <ref> carrying a tag with the channel's prefix.
# A Release creates its tag only when published, so a draft never counts (D39 (6)).
last_release() { # <ref> → "<sha> <tag>", or nothing
  local line
  line="$(git_c log --format='%H %D' --decorate-refs="refs/tags/${prefix}*" "$1" 2>/dev/null | awk 'NF > 1 { print; exit }')"
  [ -n "$line" ] || return 0
  printf '%s %s\n' "${line%% *}" "$(printf '%s' "$line" | grep -oE "tag: ${prefix}[^, ]+" | head -n1 | sed 's/^tag: //')"
}
batch_slugs() { # <release-sha|''> <head> → runs archived at <head> and not at the release, one per line
  local s
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    if [ -n "$1" ] && git_c cat-file -e "$1:$archive/$s/run.md" 2>/dev/null; then continue; fi
    git_c cat-file -e "$2:$archive/$s/run.md" 2>/dev/null || continue
    printf '%s\n' "$s"
  done < <(ls_dirs_at "$2" "$archive")
}
batch_prs() { # <release-sha|''> <head> → "#<n> <subject>" per merged PR in the range
  git_c log --format='%s' ${1:+"$1.."}"$2" 2>/dev/null | sed -nE 's/^(.*) \(#([0-9]+)\)$/#\2 \1/p'
}
# GitHub is optional for status, required for approve.
gh_ok=0; gh_repo=""
gh_probe() {
  git_c remote get-url origin >/dev/null 2>&1 || return 1
  # shellcheck source=lib/gh.sh
  source "$here/lib/gh.sh" 2>/dev/null || return 1
  gh_repo="$repo"
  if [ -n "${gh_token:-}" ] || (command -v gh >/dev/null 2>&1 && env -u GITHUB_TOKEN -u GH_TOKEN gh auth status >/dev/null 2>&1); then gh_ok=1; fi
  [ "$gh_ok" -eq 1 ]
}
open_draft() { # → "<tag>\t<html_url>" of a draft promotion Release, or nothing (needs gh_ok)
  local resp
  resp="$(gh_api GET "/repos/${gh_repo}/releases?per_page=30" 2>/dev/null)" || return 0
  [ "$(printf '%s' "$resp" | tail -n1)" = "200" ] || return 0
  printf '%s' "$resp" | sed '$d' | jq -r '[.[] | select(.draft == true and ((.body // "") | test("(?m)^- promote-sha: [0-9a-f]{40}")))] | first // empty | "\(.tag_name)\t\(.html_url)"' 2>/dev/null
}
# Vercel reads, when a token is in reach — names and ids only.
vercel_ok=0
vercel_probe() {
  project_has '.deploy.projects' || return 1
  command -v curl >/dev/null 2>&1 || return 1
  # shellcheck source=lib/vercel.sh
  source "$here/lib/vercel.sh" 2>/dev/null || return 1
  [ -n "$vercel_token" ] && vercel_ok=1
  [ "$vercel_ok" -eq 1 ]
}
product_projects() { deploy_projects | jq -r 'select((.class // "product") == "product") | .name'; }

# ===========================================================================================================
case "$verb" in

# --- init ---------------------------------------------------------------------------------------------------
init)
  echo "UAT: custom environment '$ut' → $uu (D39; _shared/promotion.md)"
  echo
  echo "One-time setup the operator completes by hand, BEFORE the first merge that relies on it (this script does none of it):"
  vercel_probe >/dev/null 2>&1 || true
  pp="$(product_projects)"
  [ -n "$pp" ] || echo "  [TODO] declare the product project(s) in deploy.projects (/setup) — the environment and the promotion are per project"
  while IFS= read -r pn; do
    [ -n "$pn" ] || continue
    done_env=0; done_dom=0; done_track=0
    if [ "$vercel_ok" -eq 1 ]; then
      ce="$(vercel_get "/v9/projects/$pn/custom-environments" 2>/dev/null)" || ce=""
      if [ "$(printf '%s' "$ce" | tail -n1)" = "200" ]; then
        env="$(printf '%s' "$ce" | sed '$d' | jq -c --arg t "$ut" '[(.environments // [])[] | select(.slug == $t)] | first // empty')"
        if [ -n "$env" ]; then
          done_env=1
          printf '%s' "$env" | jq -e --arg h "$(printf '%s' "$uu" | sed -E 's#^[a-z]+://##; s#/.*$##')" 'any((.domains // [])[]; .name == $h)' >/dev/null 2>&1 && done_dom=1
          [ "$(printf '%s' "$env" | jq -r '.branchMatcher.pattern // ""')" = "main" ] && done_track=1
        fi
      fi
    fi
    [ "$done_env" -eq 1 ] && echo "  [OK]   $pn: custom environment '$ut' exists" \
      || echo "  [TODO] $pn: Vercel → Settings → Environments → Create Environment '$ut' (Pro; one per project) — never the Neon integration on it"
    [ "$done_dom" -eq 1 ] && echo "  [OK]   $pn: $uu is attached to '$ut'" \
      || echo "  [TODO] $pn: attach the host of $uu to the environment '$ut' (Settings → Domains → the domain → Environment '$ut'), moving it off any git branch it was bound to"
    if [ "$done_track" -eq 1 ]; then echo "  [OK]   $pn: '$ut' tracks the branch main"
    elif [ -f .github/workflows/uat-deploy.yaml ] || [ -f .github/workflows/uat-deploy.yml ]; then echo "  [OK]   $pn: .github/workflows/uat-deploy.yaml deploys main to '$ut' (branch tracking refused)"
    else echo "  [TODO] $pn: deploy main to '$ut' on every merge — the environment's Branch Tracking set to main where Vercel accepts the production branch; where it refuses, seed github-pipeline/workflows/uat-deploy.yaml (vercel deploy --target=$ut)"; fi
    echo "  [TODO] $pn: Settings → Environments → Production → Branch Tracking → turn OFF 'Auto-assign Custom Production Domains' — every merge then builds a STAGED production deployment; do this BEFORE any unsigned change merges, or it ships"
  done <<<"$pp"
  case "$(database_provider)" in
    neon)    echo "  [INFO] the UAT database: .icm/scripts/db-env.sh init lists the Neon branch '$(neon_uat_branch)' and its variables on '$ut'" ;;
    mongodb) echo "  [INFO] the UAT database: .icm/scripts/db-env.sh init lists '$(mongo_uat_database)' and its variables on '$ut'" ;;
    *)       echo "  [TODO] decide which data the client tests against and set it on '$ut''s own variables (vercel env add <NAME> $ut) — never production's credentials" ;;
  esac
  if [ -f .github/workflows/release.yaml ] || [ -f .github/workflows/release.yml ]; then echo "  [OK]   .github/workflows/release.yaml present — it promotes on release: published"
  else echo "  [TODO] seed github-pipeline/workflows/release.yaml — publishing a Release does nothing without it"; fi
  mig=""; for f in .github/workflows/db-migrate.yml .github/workflows/db-migrate.yaml; do [ -f "$f" ] && mig="$f"; done
  if [ -z "$mig" ]; then echo "  [INFO] no db-migrate workflow — remove the migrate job from release.yaml if production has no migrator"
  elif grep -q 'workflow_call' "$mig"; then echo "  [OK]   $mig is callable — production migrates at the promotion"
  else echo "  [TODO] $mig runs on push to main — give it the reference shape (workflow_call; push only without UAT) BEFORE any unsigned migration merges, or it runs against production on the push"; fi
  echo "  [TODO] Actions secrets for the release workflow: the Vercel token as \$$(deploy_token_env) (env.sh add $(deploy_token_env) --ci --github secret) and whatever the migrate job reads; the job's own token needs contents: write (it edits the Release)"
  echo "  [INFO] from then on: every merge is on UAT at $uu; promote.sh status shows the batch; when the client says yes, promote.sh approve --by \"<who>\" drafts the Release, and the operator publishes it on GitHub"
  echo "RESULT: INIT"; exit 0 ;;

# --- status -------------------------------------------------------------------------------------------------
status)
  fetch || echo "note: git fetch origin failed — reading the refs as last fetched" >&2
  has_ref origin/main || die "origin/main does not resolve — fetch first"
  head_full="$(git_c rev-parse origin/main)"
  rel="$(last_release origin/main)"; rel_sha="${rel%% *}"; rel_tag="${rel#* }"; [ -n "$rel" ] || { rel_sha=""; rel_tag=""; }
  echo "UAT: $uu (custom environment '$ut') — main at ${head_full:0:7}"
  if [ -n "$rel" ]; then echo "production: $rel_tag at ${rel_sha:0:7} (the last published Release)"
  else echo "production: no published Release with the prefix '$prefix' yet — the whole of main is the batch until the first promotion (a baseline release)"; fi
  mapfile -t slugs < <(batch_slugs "$rel_sha" origin/main)
  mapfile -t prs < <(batch_prs "$rel_sha" origin/main)
  n_commits="$(git_c rev-list --count ${rel_sha:+"$rel_sha.."}origin/main 2>/dev/null || echo '?')"
  echo "batch: ${#slugs[@]} run(s), ${#prs[@]} merged PR(s), $n_commits commit(s) since ${rel_tag:-the start}"
  for s in "${slugs[@]+"${slugs[@]}"}"; do echo "  - $(title_at origin/main "$s") ($s)"; done
  for p in "${prs[@]+"${prs[@]}"}"; do echo "  · $p"; done
  if vercel_probe; then
    while IFS= read -r pn; do
      [ -n "$pn" ] || continue
      dep="$(vercel_deployments "$pn" --target production --sha "$head_full" --limit 5 2>/dev/null | jq -c 'sort_by(-.created) | first // empty' 2>/dev/null)"
      cur="$(vercel_project "$pn" 2>/dev/null | jq -r '.targets.production.id // empty' 2>/dev/null)"
      if [ -z "$dep" ]; then echo "production build ($pn): none for ${head_full:0:7} yet"
      else
        did="$(printf '%s' "$dep" | jq -r '.uid // .id')"; st="$(printf '%s' "$dep" | jq -r '.state // .readyState // "?"')"
        if [ -n "$cur" ] && [ "$cur" = "$did" ]; then echo "production build ($pn): $did $st — Current (serving)"
        else echo "production build ($pn): $did $st — Staged (serving ${cur:-unknown}); published Release promotes it"; fi
      fi
    done < <(product_projects)
    u="$("$here/deploy-status.sh" --sha "$head_full" --uat --no-wait 2>/dev/null | grep -E '^- uat:' | head -n1)"
    [ -n "$u" ] && echo "uat deployment: ${u#- uat: }"
  else
    echo "deployments: not read (no Vercel token in this shell — \$$(deploy_token_env))"
  fi
  draft_note="no draft"
  if gh_probe; then
    d="$(open_draft)"
    if [ -n "$d" ]; then draft_note="draft ${d%%$'\t'*}"; echo "draft: ${d%%$'\t'*} — $(printf '%s' "$d" | cut -f2) — the client's word is recorded; publish it on GitHub to promote"
    else echo "draft: none — when the client signs the batch off: .icm/scripts/promote.sh approve --by \"<who>\""; fi
  else
    draft_note="draft unknown"; echo "draft: not read (no GitHub route)"
  fi
  echo "RESULT: BATCH ${#slugs[@]} change(s) since ${rel_tag:-no release} · $draft_note"
  exit 0 ;;

# --- approve ------------------------------------------------------------------------------------------------
approve)
  [ -n "$by" ] || die "--by \"<who signed off>\" is required — the approval is the client's word, recorded by the operator (never inferred)"
  fetch || die "git fetch origin failed — approve reads origin/main and its tags and needs the network"
  has_ref origin/main || die "origin/main does not resolve"
  sha="$(git_c rev-parse --verify -q "${sha_in:-origin/main}^{commit}" 2>/dev/null || true)"
  [ -n "$sha" ] || stop "--sha '${sha_in}' does not resolve to a commit here — fetch, or pass a SHA on origin/main"
  git_c merge-base --is-ancestor "$sha" origin/main 2>/dev/null || stop "${sha:0:7} is not on origin/main — only a commit on main can be promoted (D39 (1))"
  rel="$(last_release origin/main)"; rel_sha="${rel%% *}"; rel_tag="${rel#* }"; [ -n "$rel" ] || { rel_sha=""; rel_tag=""; }
  if [ -n "$rel_sha" ] && git_c merge-base --is-ancestor "$sha" "$rel_sha" 2>/dev/null; then
    stop "${sha:0:7} is already released — $rel_tag is at ${rel_sha:0:7}; nothing new to promote (promote.sh status)"
  fi
  mapfile -t slugs < <(batch_slugs "$rel_sha" "$sha")
  mapfile -t prs < <(batch_prs "$rel_sha" "$sha")
  tag="${prefix}${today}-promote-${sha:0:7}"
  name="Production release $today — ${#slugs[@]} change(s), approved by $by"
  body="$(
    echo "The client's sign-off of the UAT batch, recorded by the operator. **Publishing this Release promotes it to production** (the release workflow migrates, promotes the staged deployment of this SHA, and announces)."
    echo
    echo "- promote-sha: $sha"
    echo "- approved-by: $by"
    echo "- approved-on: $today"
    echo "- note: ${note:-none}"
    echo "- announce: $announce"
    echo "- uat: $uu"
    echo "- previous-release: ${rel_tag:-none}"
    echo
    echo "## Batch"
    echo
    if [ "${#slugs[@]}" -eq 0 ]; then echo "_No run archived since ${rel_tag:-the start} — lanes and direct commits only (see the pull requests)._"; fi
    for s in "${slugs[@]+"${slugs[@]}"}"; do echo "- $(title_at "$sha" "$s") (\`$s\`)"; done
    echo
    echo "## Pull requests"
    echo
    if [ "${#prs[@]}" -eq 0 ]; then echo "_None in the range._"; fi
    for p in "${prs[@]+"${prs[@]}"}"; do echo "- $p"; done
  )"
  payload="$(jq -n --arg tag "$tag" --arg sha "$sha" --arg name "$name" --arg body "$body" \
    '{tag_name: $tag, target_commitish: $sha, name: $name, body: $body, draft: true, prerelease: false}')"
  if [ "$dry" -eq 1 ]; then
    echo "would: POST /repos/<origin>/releases — a DRAFT, never published by this script:"
    printf '%s\n' "$payload"
    echo "RESULT: DRY-RUN"; exit 0
  fi
  gh_probe || die "no GitHub route (GH_TOKEN with contents: write, or gh login) — the draft Release is written through lib/gh.sh"
  d="$(open_draft)"
  [ -z "$d" ] && [ "$(gh_api GET "/repos/${gh_repo}/releases?per_page=1" 2>/dev/null | tail -n1)" != "200" ] && die "could not list the Releases of $gh_repo — the draft check must answer before a draft is written"
  [ -z "$d" ] || stop "a draft promotion Release is already open: ${d%%$'\t'*} ($(printf '%s' "$d" | cut -f2)) — publish it, or delete it on GitHub if the word it records no longer stands, then approve again"
  resp="$(gh_api GET "/repos/${gh_repo}/releases/tags/${tag}")" || die "GitHub unreachable"
  [ "$(printf '%s' "$resp" | tail -n1)" != "200" ] || stop "tag $tag already has a Release — a second approval of the same SHA today; nothing drafted"
  resp="$(gh_api POST "/repos/${gh_repo}/releases" "$payload")" || die "GitHub unreachable"
  http="$(printf '%s' "$resp" | tail -n1)"
  [ "$http" = "201" ] || die "POST /releases answered HTTP $http — $(printf '%s' "$resp" | sed '$d' | jq -r '.errors[0].message // .message // "no message"' 2>/dev/null) (the token needs Contents: read and write)"
  url="$(printf '%s' "$resp" | sed '$d' | jq -r '.html_url // empty')"
  echo "drafted: $tag at ${sha:0:7} — ${#slugs[@]} run(s), ${#prs[@]} PR(s) since ${rel_tag:-the start}; approved by $by"
  echo "next: the operator opens ${url:-the draft on GitHub} and PUBLISHES it — the release workflow then migrates production, promotes the staged deployment of ${sha:0:7} and announces (announce: $announce)"
  echo "RESULT: DRAFTED $tag"
  exit 0 ;;
esac
