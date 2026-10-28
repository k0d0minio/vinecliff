#!/usr/bin/env bash
# merge.sh — merge one pull request after Jamie's Ready to merge tick.
#
# Usage: .icm/scripts/merge.sh <number>
#
# The script uses the REST API only, through lib/github.sh. It reads the pull request with
# GET pulls/<number>, and once more when GitHub has not computed `mergeable` yet. It refuses, one
# line per refusal on stderr and exit 1, when:
#   - the state is not open,
#   - the pull request is a draft,
#   - the body has no line that starts with "- [x] **Ready to merge**" (x or X),
#   - no check ran on the head commit,
#   - a check is pending or failed (the check runs and the commit statuses),
#   - the branch conflicts with main.
# Then it squash-merges the head commit that it read, with the subject "<title> (#<number>)".
# It deletes the branch, and prints the merge commit and the deleted branch. It ticks nothing.
# The pull request body is its one source for the tick. The contract is
# .icm/intake/CONTEXT.md § The loop, step 7.
set -euo pipefail

usage() {
  echo "usage: $0 <pull request number>" >&2
  exit 2
}
[ $# -eq 1 ] || usage
case "$1" in '' | *[!0-9]*) usage ;; esac
n="$1"
for t in gh git jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "$t is not installed" >&2; exit 1; }
done
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/github.sh
source "$here/lib/github.sh"
repo="$(gh_repo)"

pr="$(gh api "repos/${repo}/pulls/${n}")"
if [ "$(jq -r '.state' <<<"$pr")" = open ] && [ "$(jq -r '.mergeable' <<<"$pr")" = null ]; then
  # GitHub computes mergeable after the read that asks for it. One more read gets the value.
  sleep 3
  pr="$(gh api "repos/${repo}/pulls/${n}")"
fi
title="$(jq -r '.title' <<<"$pr")"
branch="$(jq -r '.head.ref' <<<"$pr")"
sha="$(jq -r '.head.sha' <<<"$pr")"
state="$(jq -r 'if .merged then "MERGED" else (.state | ascii_upcase) end' <<<"$pr")"

fail=0
refuse() {
  echo "#${n}: $*" >&2
  fail=1
}
[ "$state" = OPEN ] || refuse "the state is ${state}, not open"
[ "$(jq -r '.draft' <<<"$pr")" = false ] || refuse "the pull request is a draft"
jq -r '.body // ""' <<<"$pr" | tr -d '\r' | grep -qE '^- \[[xX]\] \*\*Ready to merge\*\*' \
  || refuse "Ready to merge has no tick. Jamie ticks it"
# One line per check: its name, then ok, pending, or the failed conclusion.
checks="$(gh_checks "$sha")"
if [ -z "$checks" ]; then
  refuse "no check ran"
else
  while IFS=$'\t' read -r name verdict _; do
    [ "$verdict" = ok ] || refuse "the check ${name} is ${verdict}"
  done <<<"$checks"
fi
if [ "$(jq -r '.mergeable' <<<"$pr")" = false ] || [ "$(jq -r '.mergeable_state' <<<"$pr")" = dirty ]; then
  refuse "the branch ${branch} conflicts with main"
fi
[ "$fail" -eq 0 ] || exit 1

# `sha` makes GitHub refuse the merge when a push moved the head after the read.
merged="$(gh api -X PUT "repos/${repo}/pulls/${n}/merge" \
  -f merge_method=squash -f sha="$sha" -f commit_title="${title} (#${n})")" \
  || { echo "#${n}: GitHub refused the merge. The line above gives the reason" >&2; exit 1; }
merge_sha="$(jq -r '.sha // empty' <<<"$merged")"
echo "merged #${n}: ${title} (#${n})"
echo "merge commit: ${merge_sha:-not read}"

# The branch delete. GitHub deletes the branch itself when the repository setting says so.
lower() { tr '[:upper:]' '[:lower:]'; }
if [ "$(jq -r '.head.repo.full_name // empty' <<<"$pr" | lower)" != "$(lower <<<"$repo")" ]; then
  echo "branch kept: ${branch} is in another repository"
elif gh api -X DELETE "repos/${repo}/git/refs/heads/${branch}" >/dev/null 2>&1; then
  echo "branch deleted: ${branch}"
elif ! gh api "repos/${repo}/git/ref/heads/${branch}" >/dev/null 2>&1; then
  echo "branch deleted: ${branch} (by GitHub on the merge)"
else
  echo "#${n}: merged, but the branch ${branch} was not deleted. Delete it on GitHub" >&2
  exit 1
fi
echo "next: read ci on main once: gh run list --workflow ci --branch main --limit 1"
