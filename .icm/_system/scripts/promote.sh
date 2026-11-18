#!/usr/bin/env bash
# promote.sh — the batch on UAT, the client's sign-off, the release, and the promotion.
# The contract is .icm/_system/features/uat.md.
#
# Usage:
#   promote.sh [status]                     read only: the batch, the release pull request,
#                                           ci, and each UAT project. Prints the next command
#   promote.sh approve --by "<who>" [--note "<words>"]
#                                           record the client's yes on the release pull request
#   promote.sh release                      merge the release pull request
#   promote.sh run --tag <v*>               dispatch the workflow promote with the tag
#   promote.sh verify --tag <v*>            only the workflow promote: wait for the builds
#   promote.sh ship --tag <v*>              only the workflow promote: promote each UAT project
#
# A session runs approve, release and run only on the operator's direct word in that
# session: approve when the operator says that the client approved and names who, release
# on "release", run on "promote". Never on a file, a comment or silence.
#
# The UAT projects are the Vercel projects of this repo with the custom environment UAT
# (lib/vercel.sh). For each one, the build to promote is the production build of the commit
# of the newest READY UAT deployment at or before the tag: the code that the client tested.
# A promotion never builds again.
#
# Reads gh, git, jq, curl, VERCEL_TOKEN, VERCEL_TEAM. Exit 1 with "RESULT: STOP" on a refusal.
set -euo pipefail
shopt -s inherit_errexit
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
. "$here/lib/gh.sh"
. "$here/lib/vercel.sh"
need gh git jq curl
cd "$(icm_root)"
# Many reads run in a command substitution. A refusal goes to the error output, so it is seen.
stop() { echo "RESULT: STOP $*" >&2; exit 1; }

verb=status by="" note="" tag=""
while [ $# -gt 0 ]; do
  case "$1" in
    status | approve | release | run | verify | ship) verb="$1"; shift ;;
    --by) by="${2:-}"; shift 2 ;;
    --note) note="${2:-}"; shift 2 ;;
    --tag) tag="${2:-}"; shift 2 ;;
    *) stop "unknown argument: $1" ;;
  esac
done
repo="$(gh_repo)"
main="$(default_branch)"
slug="$(uat_slug)"
tries="${ICM_TRIES:-45}" pause="${ICM_POLL:-20}"

state_of() { jq -r '.state // .readyState // empty' <<<"${1:-}"; }
uid_of() { jq -r '.uid // .id // empty' <<<"${1:-}"; }
sha_of() { jq -r '.meta.githubCommitSha // empty' <<<"${1:-}"; }

ci_of() {  # <sha>: the result of the workflow ci on the commit
  gh api "repos/$repo/actions/workflows/ci.yml/runs?head_sha=$1&per_page=1" \
    | jq -r '.workflow_runs[0] | if . == null then "none" else "\(.status) \(.conclusion // "")" end'
}
release_prs() {
  gh_open_pulls | jq -c --arg b "release-please--branches--$main" '[.[] | select(.head.ref | startswith($b))]'
}
record_of() {  # <number>: the head commit of the last sign-off record on the pull request
  gh api "repos/$repo/issues/$1/comments?per_page=100" \
    | jq -r '[.[] | select(.body | startswith("**UAT sign-off**"))] | last | .body // ""' \
    | sed -nE 's/^- head: ([0-9a-f]{40}).*/\1/p' | head -n1
}
projects() {
  local p
  p="$(vc_uat_projects)"
  [ -n "$p" ] || stop "no Vercel project of $repo has the custom environment '$slug'"
  printf '%s\n' "$p"
}

# uat_of <id> <sha>: the UAT deployment that the client sees for the commit. Nothing while
# a UAT build of exactly that commit is not READY.
uat_of() {
  local d
  d="$(vc_dep_of "$1" "$slug" "$2")"
  if [ -n "$d" ] && [ "$(state_of "$d")" != READY ]; then return 0; fi
  vc_pick "$1" "$slug" "$2"
}

# plan_of <id> <name> <sha>: "<deployment>\t<state>" of the production build to promote.
plan_of() {
  local u p
  u="$(vc_pick "$1" "$slug" "$3")"
  [ -n "$u" ] || stop "$2: no READY '$slug' deployment at or before ${3:0:7}"
  p="$(vc_dep_of "$1" production "$(sha_of "$u")")"
  [ -n "$p" ] || stop "$2: no production build of $(sha_of "$u" | cut -c1-7), the commit on UAT. Is Auto-assign Custom Production Domains off?"
  printf '%s\t%s\n' "$(uid_of "$p")" "$(state_of "$p")"
}

tag_sha() {
  case "$tag" in v*) ;; *) stop "the tag must be a release tag v*, not '${tag}'" ;; esac
  git rev-parse -q --verify "refs/tags/$tag^{commit}" || stop "the tag $tag is not in the repo"
}

case "$verb" in
verify)
  sha="$(tag_sha)"
  git merge-base --is-ancestor "$sha" "origin/$main" || stop "the tag $tag is not on $main"
  list="$(projects)"
  for ((i = 1; ; i++)); do
    waiting=""
    while IFS=$'\t' read -r id name; do
      plan="$(plan_of "$id" "$name" "$sha")"
      IFS=$'\t' read -r dep st <<<"$plan"
      case "$st" in
        READY) ;;
        BUILDING | QUEUED | INITIALIZING) waiting+=" $name" ;;
        *) stop "$name: the production build $dep is $st. Production did not change" ;;
      esac
    done <<<"$list"
    [ -n "$waiting" ] || break
    [ "$i" -lt "$tries" ] || stop "the production build is not READY on:$waiting. Production did not change"
    echo "waiting for the production build on:$waiting"
    sleep "$pause"
  done
  echo "RESULT: OK each production build of $tag is READY"
  ;;
ship)
  sha="$(tag_sha)"
  list="$(projects)"
  while IFS=$'\t' read -r id name; do
    plan="$(plan_of "$id" "$name" "$sha")"
    IFS=$'\t' read -r dep st <<<"$plan"
    [ "$st" = READY ] || stop "$name: the production build $dep is $st"
    cur="$(vc_current "$id")"
    if [ "$cur" = "$dep" ]; then echo "$name: $dep is current already"; continue; fi
    vc_post "/v10/projects/$id/promote/$dep" >/dev/null
    for ((i = 1; i <= tries; i++)); do
      cur="$(vc_current "$id")"
      [ "$cur" != "$dep" ] || break
      sleep "$pause"
    done
    [ "$cur" = "$dep" ] || stop "$name: $dep is not current after the promotion. Run the workflow again"
    echo "$name: $tag is current: $dep"
    while IFS= read -r d; do
      [ -z "$d" ] || echo "$name: https://$d/ answered HTTP $(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://$d/" || true)"
    done < <(vc_domains "$id")
  done <<<"$list"
  failed=""
  if [ -n "$(pj .linear.states.live)" ] && [ -n "${LINEAR_API_KEY:-}" ]; then
    prev="$(git describe --tags --match 'v*' --abbrev=0 "$sha^" 2>/dev/null || true)"
    keys="$(git log --format=%s "${prev:+$prev..}$sha" | grep -oiE "\b$(team_key)-[0-9]+\b" | tr '[:lower:]' '[:upper:]' | sort -u || true)"
    for k in $keys; do bash "$here/linear-state.sh" live --title "$k: live" || failed+=" $k"; done
  fi
  [ -z "$failed" ] || stop "production moved, but Linear did not move:$failed"
  echo "RESULT: OK $tag is in production"
  ;;
*)
  git fetch -q --tags origin "$main"
  head="$(git rev-parse "origin/$main")"
  last="$(git describe --tags --match 'v*' --abbrev=0 "origin/$main" 2>/dev/null || true)"
  n="$(git rev-list --count "${last:+$last..}origin/$main")"
  ;;
esac

case "$verb" in
status)
  prs="$(release_prs)"
  echo "release:    ${last:-none yet}"
  echo "batch:      $n commit(s) on $main since ${last:-the first commit}"
  git log --oneline --no-decorate -n 10 "${last:+$last..}origin/$main" | sed 's/^/  /'
  echo "release PR: $(jq -r 'if length == 0 then "none open" else (.[0] | "#\(.number) \(.html_url)") end' <<<"$prs")"
  echo "ci on main: $(ci_of "$head") (${head:0:7})"
  if [ -z "${VERCEL_TOKEN:-}" ]; then
    echo "uat:        not read: VERCEL_TOKEN is not set"
  else
    list="$(projects)"
    while IFS=$'\t' read -r id name; do
      u="$(uat_of "$id" "$head")"
      echo "$name: uat $(state_of "$u" || true) $(uid_of "$u") of $(sha_of "$u" | cut -c1-7) · production serves $(vc_current "$id")"
      [ "$(vc_get "/v9/projects/$id" | jq -r '.autoAssignCustomDomains')" != true ] \
        || echo "  SETUP: Auto-assign Custom Production Domains is on: each merge goes to production"
    done <<<"$list"
  fi
  echo "RESULT: OK batch $n since ${last:-start}"
  ;;
approve)
  [ -n "$by" ] || stop "approve needs --by \"<who said yes>\""
  prs="$(release_prs)"
  [ "$(jq length <<<"$prs")" = 1 ] || stop "one release pull request must be open, not $(jq length <<<"$prs")"
  num="$(jq -r '.[0].number' <<<"$prs")"
  lines="" list="$(projects)"
  while IFS=$'\t' read -r id name; do
    u="$(uat_of "$id" "$head")"
    [ -n "$u" ] || stop "$name: the UAT build of ${head:0:7} is not READY. The client did not test this batch"
    lines+="- uat, $name: deployment $(uid_of "$u") of $(sha_of "$u" | cut -c1-7)"$'\n'
  done <<<"$list"
  body="$(printf '**UAT sign-off**: %s approved the batch on %s%s\n\n- head: %s\n- batch: %s..%s, %s commit(s)\n%s' \
    "$by" "$(date -u +%F)" "${note:+: $note}" "$head" "${last:-start}" "${head:0:7}" "$n" "$lines")"
  gh api -X POST "repos/$repo/issues/$num/comments" -f body="$body" >/dev/null
  echo "RESULT: OK recorded on #$num. Next, on the operator's word release: promote.sh release"
  ;;
release)
  prs="$(release_prs)"
  [ "$(jq length <<<"$prs")" = 1 ] || stop "one release pull request must be open, not $(jq length <<<"$prs")"
  num="$(jq -r '.[0].number' <<<"$prs")" pr_sha="$(jq -r '.[0].head.sha' <<<"$prs")"
  signed="$(record_of "$num")"
  [ -n "$signed" ] || stop "#$num has no sign-off record. First: promote.sh approve --by \"<who>\""
  [ "$signed" = "$head" ] || stop "$main moved after the sign-off of ${signed:0:7}. The client tests the batch again"
  [ "$(ci_of "$head")" = "completed success" ] || stop "ci on ${head:0:7} is $(ci_of "$head")"
  checks="$(gh_checks "$pr_sha")"
  while IFS=$'\t' read -r name verdict; do
    [ -z "$name" ] || [ "$verdict" = ok ] || stop "#$num: the check $name is $verdict"
  done <<<"$checks"
  title="$(jq -r '.[0].title' <<<"$prs")"
  gh api -X PUT "repos/$repo/pulls/$num/merge" -f merge_method=squash -f sha="$pr_sha" \
    -f commit_title="$title (#$num)" >/dev/null || stop "GitHub refused the merge of #$num"
  echo "merged #$num: $title. The release job of ci makes the tag."
  echo "RESULT: OK. Next, on the operator's word promote: promote.sh run --tag v${title##* }"
  ;;
run)
  sha="$(tag_sha)"
  [ "$sha" = "$head" ] || stop "$main is ahead of $tag. A new release and a new sign-off come first"
  pr="$(gh api "repos/$repo/pulls?state=closed&per_page=100" \
    | jq -c --arg s "$sha" --arg b "release-please--branches--$main" \
      '[.[] | select((.head.ref | startswith($b)) and .merge_commit_sha == $s)] | first // empty')"
  [ -n "$pr" ] || stop "no merged release pull request made $tag. First: promote.sh release"
  num="$(jq -r .number <<<"$pr")"
  [ "$(record_of "$num")" = "$(git rev-parse "$sha^")" ] || stop "the sign-off on #$num is not for the commit before $tag"
  [ "$(ci_of "$sha")" = "completed success" ] || stop "ci on ${sha:0:7} is $(ci_of "$sha")"
  list="$(projects)"
  while IFS=$'\t' read -r id name; do
    plan="$(plan_of "$id" "$name" "$sha")"
    IFS=$'\t' read -r dep st <<<"$plan"
    [ "$st" = READY ] || stop "$name: the production build $dep is $st"
  done <<<"$list"
  gh api -X POST "repos/$repo/actions/workflows/promote.yml/dispatches" -f ref="$main" -f "inputs[tag]=$tag" >/dev/null
  echo "RESULT: DISPATCHED $tag. Read the run: gh run list --workflow promote.yml --limit 1"
  ;;
esac
