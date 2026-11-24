#!/usr/bin/env bash
# merge.sh — merge one pull request after the operator's Ready to merge tick.
#
# Usage: merge.sh <pull request number>
#
# The script refuses, with one line for each reason, when:
#   - the pull request is not open, or is a draft
#   - Ready to merge is not ticked (the box below <!-- gate:ready-to-merge -->)
#   - no check ran, or a check is pending or failed
#   - the branch conflicts with the default branch
# If nothing refuses, it squash-merges the head commit that it read, and deletes the branch.
# A branch that is behind the default branch with no conflict is brought up to date first
# (GitHub merges the default branch into it, update-branch). The script then waits for the
# new head and for its checks, icm-gate too (ci-status.sh --watch --all).
# When GitHub answers "Base branch was modified" (HTTP 405: another pull request merged
# first), it tries the merge again, 4 times at most, after 5, 10, 20 and 40 seconds.
# It ticks nothing. The pull request body is its one source for the tick.
#
# Last line: "RESULT: OK <merge commit>" or "RESULT: STOP <reason>".
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
. "$here/lib/gh.sh"
help_if_asked "$@"

[ $# -eq 1 ] || stop "usage: merge.sh <pull request number>"
case "$1" in '' | *[!0-9]*) stop "usage: merge.sh <pull request number>" ;; esac
number="$1"
need git gh jq
cd "$(icm_root)"
repo="$(gh_repo)" || stop "the GitHub repo was not found"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

pr="$(gh_pr "$number")" || stop "the pull request #$number was not read"
if [ "$(jq -r '.state' <<<"$pr")" = open ] && [ "$(jq -r '.mergeable' <<<"$pr")" = null ]; then
  # GitHub computes `mergeable` after the first read. One more read gets the value.
  sleep 3
  pr="$(gh_pr "$number")" || stop "the pull request #$number was not read"
fi
title="$(jq -r '.title' <<<"$pr")"
branch="$(jq -r '.head.ref' <<<"$pr")"
sha="$(jq -r '.head.sha' <<<"$pr")"
state="$(jq -r 'if .merged then "merged" else .state end' <<<"$pr")"

refusals=0
refuse() {
  echo "refused: $*"
  refusals=$((refusals + 1))
}
[ "$state" = open ] || refuse "the pull request is $state, not open"
[ "$(jq -r '.draft' <<<"$pr")" = false ] || refuse "the pull request is a draft"
ready="$(jq -r '.body // ""' <<<"$pr" | gate_state ready-to-merge)"
[ "$ready" = yes ] || refuse "Ready to merge is not ticked (gate: $ready). The operator ticks it"
checks="$(gh_checks "$sha")" || refuse "the checks were not read"
if [ -z "${checks:-}" ]; then
  refuse "no check ran"
else
  while IFS=$'\t' read -r name verdict; do
    case "$verdict" in
      ok) ;;
      waits) refuse "the check $name waits for the operator" ;;
      *) refuse "the check $name is $verdict" ;;
    esac
  done <<<"$checks"
fi
conflict="$(gh_conflict "$pr")"
[ -z "$conflict" ] || refuse "$conflict"
[ "$refusals" -eq 0 ] || stop "#$number was not merged: $refusals reason(s) above"

if [ "$(jq -r '.mergeable_state' <<<"$pr")" = behind ]; then
  echo "merge: #$number is behind $(default_branch). GitHub merges $(default_branch) into $branch"
  gh api -X PUT "repos/${repo}/pulls/${number}/update-branch" -f expected_head_sha="$sha" >/dev/null \
    || stop "GitHub did not bring $branch up to date. Merge $(default_branch) into it, push, then merge again"
  waited=0
  until new="$(gh_pr "$number" | jq -r '.head.sha')" && [ "$new" != "$sha" ]; do
    [ "$waited" -lt "${ICM_HEAD_WAIT_S:-60}" ] || stop "GitHub does not show the new head of #$number. Merge again"
    sleep 2; waited=$((waited + 2))
  done
  echo "merge: the new head is ${new:0:7}. The checks run again"
  out="$(bash "$here/ci-status.sh" "$number" --watch --all)" \
    || stop "the checks of the new head of #$number are not green: $(tail -n1 <<<"$out")"
  sha="$new"
fi

# `sha` makes GitHub refuse the merge when a push moved the head after the read.
wait_s="${ICM_MERGE_WAIT_S:-5}"
for try in 1 2 3 4 5; do
  if merged="$(gh api -X PUT "repos/${repo}/pulls/${number}/merge" \
    -f merge_method=squash -f sha="$sha" -f commit_title="${title} (#${number})" 2>"$tmp")"; then
    break
  fi
  grep -q "Base branch was modified" "$tmp" && [ "$try" -lt 5 ] \
    || stop "GitHub refused the merge of #$number: $(tail -n1 "$tmp")"
  echo "merge: the base branch moved (HTTP 405). Try $((try + 1)) of 5 in ${wait_s} s"
  sleep "$wait_s"
  wait_s=$((wait_s * 2))
done
echo "merged #${number}: ${title}"
if gh api -X DELETE "repos/${repo}/git/refs/heads/${branch}" >/dev/null 2>&1; then
  echo "branch deleted: $branch"
elif gh api "repos/${repo}/git/ref/heads/${branch}" >/dev/null 2>&1; then
  echo "the branch $branch was not deleted. Delete it on GitHub"
else
  echo "branch deleted: $branch (by GitHub)"
fi
echo "RESULT: OK $(jq -r '.sha // "merge commit not read"' <<<"$merged")"
