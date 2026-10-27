#!/usr/bin/env bash
# merge.sh — merge one pull request after Jamie's Ready to merge tick.
#
# Usage: .icm/scripts/merge.sh <number>
#
# The script reads the pull request once, with gh pr view. It refuses, one line per refusal on
# stderr and exit 1, when:
#   - the state is not open,
#   - the pull request is a draft,
#   - the body has no line that starts with "- [x] **Ready to merge**" (x or X),
#   - no check ran,
#   - a check is pending or failed,
#   - the branch conflicts with main.
# Then it squash-merges with the subject "<title> (#<number>)", deletes the branch, and prints
# the merge commit and the deleted branch. It ticks nothing. The pull request body is its one
# source for the tick. The contract is .icm/intake/CONTEXT.md § The loop, step 7.
set -euo pipefail

usage() {
  echo "usage: $0 <pull request number>" >&2
  exit 2
}
[ $# -eq 1 ] || usage
case "$1" in '' | *[!0-9]*) usage ;; esac
n="$1"
for t in gh jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "$t is not installed" >&2; exit 1; }
done

pr="$(gh pr view "$n" --json number,title,state,isDraft,mergeable,headRefName,body,statusCheckRollup)"
title="$(jq -r '.title' <<<"$pr")"
branch="$(jq -r '.headRefName' <<<"$pr")"
state="$(jq -r '.state' <<<"$pr")"

fail=0
refuse() {
  echo "#${n}: $*" >&2
  fail=1
}
[ "$state" = OPEN ] || refuse "the state is ${state}, not open"
[ "$(jq -r '.isDraft' <<<"$pr")" = false ] || refuse "the pull request is a draft"
jq -r '.body' <<<"$pr" | tr -d '\r' | grep -qE '^- \[[xX]\] \*\*Ready to merge\*\*' \
  || refuse "Ready to merge has no tick. Jamie ticks it"
# One line per check: its name, then ok, pending, or the failed conclusion.
checks="$(jq -r '.statusCheckRollup[]? |
  if .__typename == "StatusContext" then
    "\(.context)\t\(if .state == "SUCCESS" then "ok" elif (.state | IN("PENDING", "EXPECTED")) then "pending" else (.state | ascii_downcase) end)"
  else
    "\(.name)\t\(if .status != "COMPLETED" then "pending" elif (.conclusion | IN("SUCCESS", "NEUTRAL", "SKIPPED")) then "ok" else (.conclusion | ascii_downcase) end)"
  end' <<<"$pr")"
if [ -z "$checks" ]; then
  refuse "no check ran"
else
  while IFS=$'\t' read -r name verdict; do
    [ "$verdict" = ok ] || refuse "the check ${name} is ${verdict}"
  done <<<"$checks"
fi
[ "$(jq -r '.mergeable' <<<"$pr")" != CONFLICTING ] || refuse "the branch ${branch} conflicts with main"
[ "$fail" -eq 0 ] || exit 1

gh pr merge "$n" --squash --delete-branch --subject "${title} (#${n})"
sha="$(gh pr view "$n" --json mergeCommit --jq '.mergeCommit.oid // empty')"
echo "merged #${n}: ${title} (#${n})"
echo "merge commit: ${sha:-not read}"
echo "branch deleted: ${branch}"
echo "next: read ci on main once: gh run list --workflow ci --branch main --limit 1"
