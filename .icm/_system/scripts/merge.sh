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
# It ticks nothing. The pull request body is its one source for the tick.
#
# Last line: "RESULT: OK <merge commit>" or "RESULT: STOP <reason>".
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
. "$here/lib/gh.sh"

[ $# -eq 1 ] || stop "usage: merge.sh <pull request number>"
case "$1" in '' | *[!0-9]*) stop "usage: merge.sh <pull request number>" ;; esac
number="$1"
need git gh jq
cd "$(icm_root)"
repo="$(gh_repo)" || stop "the GitHub repo was not found"

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
    [ "$verdict" = ok ] || refuse "the check $name is $verdict"
  done <<<"$checks"
fi
if [ "$(jq -r '.mergeable' <<<"$pr")" = false ] || [ "$(jq -r '.mergeable_state' <<<"$pr")" = dirty ]; then
  refuse "the branch $branch conflicts with $(default_branch)"
fi
[ "$refusals" -eq 0 ] || stop "#$number was not merged: $refusals reason(s) above"

# `sha` makes GitHub refuse the merge when a push moved the head after the read.
merged="$(gh api -X PUT "repos/${repo}/pulls/${number}/merge" \
  -f merge_method=squash -f sha="$sha" -f commit_title="${title} (#${number})")" \
  || stop "GitHub refused the merge of #$number"
echo "merged #${number}: ${title}"
if gh api -X DELETE "repos/${repo}/git/refs/heads/${branch}" >/dev/null 2>&1; then
  echo "branch deleted: $branch"
elif gh api "repos/${repo}/git/ref/heads/${branch}" >/dev/null 2>&1; then
  echo "the branch $branch was not deleted. Delete it on GitHub"
else
  echo "branch deleted: $branch (by GitHub)"
fi
echo "RESULT: OK $(jq -r '.sha // "merge commit not read"' <<<"$merged")"
