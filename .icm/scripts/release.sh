#!/usr/bin/env bash
# release.sh — merge the release pull request, on Jamie's word `release`.
#
# Usage: .icm/scripts/release.sh
#
# Run it only when Jamie says `release` in this session. Never on a file, a comment or silence.
# The script finds the open release pull request: the head branch
# release-please--branches--main, or a title that starts with "chore(main): release". It
# refuses, one line per refusal on stderr and exit 1, when:
#   - no release pull request is open, or more than one is open,
#   - a check on it is pending or failed,
#   - ci on main's head is not success.
# An empty check list on the release pull request is not a refusal. release-please opens it with
# the workflow token, and a pull request opened with that token starts no workflow.
#
# The merge is a squash. release-please's README says: "Both squash-merge and merge commits work
# with Release PRs" (googleapis/release-please, read on 2026-10-27).
#
# The merge does not make the tag. The release job of the ci run on the merge commit makes it.
# The script waits once for that run with gh run watch. Then it prints the newest release tag
# from GET releases, and refuses when that tag does not point at the merge commit.
#
# The reads and the merge use the REST API only, through lib/github.sh, which says why.
# It decides nothing. The contract is .icm/intake/CONTEXT.md § After the tick, and
# .icm/uat/CONTEXT.md § The promotion where that file exists.
set -euo pipefail

[ $# -eq 0 ] || { echo "usage: $0" >&2; exit 2; }
for t in gh git jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "$t is not installed" >&2; exit 1; }
done
root="$(git rev-parse --show-toplevel)"
cd "$root"
# shellcheck source=lib/github.sh
source .icm/scripts/lib/github.sh
repo="$(gh_repo)"

fail=0
refuse() {
  echo "$*" >&2
  fail=1
}

# --- the release pull request ---------------------------------------------------------------------
prs="$(gh_open_pulls \
  | jq -c '[.[] | select(.head.ref == "release-please--branches--main" or (.title | startswith("chore(main): release")))]')"
count="$(jq 'length' <<<"$prs")"
if [ "$count" -eq 0 ]; then
  echo "no release pull request is open. A merge to main makes release-please open one" >&2
  exit 1
fi
if [ "$count" -gt 1 ]; then
  echo "${count} release pull requests are open: $(jq -r '[.[] | "#\(.number)"] | join(", ")' <<<"$prs"). Close the extra ones first" >&2
  exit 1
fi
pr="$(jq -c '.[0]' <<<"$prs")"
n="$(jq -r '.number' <<<"$pr")"
title="$(jq -r '.title' <<<"$pr")"
url="$(jq -r '.html_url' <<<"$pr")"
pr_sha="$(jq -r '.head.sha' <<<"$pr")"
# One line per check: its name, then ok, pending, or the failed conclusion.
checks="$(gh_checks "$pr_sha")"
if [ -n "$checks" ]; then
  while IFS=$'\t' read -r name verdict _; do
    [ "$verdict" = ok ] || refuse "#${n}: the check ${name} is ${verdict}"
  done <<<"$checks"
fi

# --- ci on main's head ----------------------------------------------------------------------------
git fetch -q origin main
head="$(git rev-parse origin/main)"
ci="$(gh run list --workflow ci --branch main --commit "$head" --limit 1 --json status,conclusion \
  --jq 'first | if . == null then "" else "\(.status) \(.conclusion // "")" end')"
case "$ci" in
  "completed success") ;;
  "") refuse "no ci run found for main's head ${head:0:7}" ;;
  *) refuse "ci on main's head ${head:0:7} is ${ci% }, not success" ;;
esac
[ "$fail" -eq 0 ] || exit 1

# --- the merge ------------------------------------------------------------------------------------
# `sha` makes GitHub refuse the merge when a push moved the head after the read.
merged="$(gh api -X PUT "repos/${repo}/pulls/${n}/merge" \
  -f merge_method=squash -f sha="$pr_sha" -f commit_title="${title} (#${n})")" \
  || { echo "#${n}: GitHub refused the merge. The line above gives the reason" >&2; exit 1; }
sha="$(jq -r '.sha // empty' <<<"$merged")"
[ -n "$sha" ] || { echo "#${n}: the merge commit was not read back. Read it on ${url}" >&2; exit 1; }
echo "merged the release pull request #${n}: ${title}"
echo "merge commit: ${sha}"

# --- the tag: one blocking read of the ci run on the merge commit ---------------------------------
run=""
for _ in 1 2 3 4 5 6; do
  run="$(gh run list --workflow ci --branch main --commit "$sha" --limit 1 --json databaseId --jq 'first.databaseId // empty')"
  [ -z "$run" ] || break
  sleep 5
done
[ -n "$run" ] || { echo "no ci run started for ${sha:0:7}. The tag is not made. Read: gh run list --workflow ci --branch main" >&2; exit 1; }
echo "waiting once for the ci run ${run} on ${sha:0:7}: its release job makes the tag"
gh run watch "$run" --exit-status >/dev/null \
  || { echo "the ci run ${run} on ${sha:0:7} failed. The tag may not exist. Read: gh run view ${run}" >&2; exit 1; }
tag="$(gh api "repos/${repo}/releases?per_page=1" | jq -r 'first.tag_name // empty')"
[ -n "$tag" ] || { echo "no release exists after the ci run ${run}" >&2; exit 1; }
git fetch -q --tags origin
tag_sha="$(git rev-parse -q --verify "${tag}^{commit}" || true)"
[ "$tag_sha" = "$sha" ] \
  || { echo "the newest release ${tag} points at ${tag_sha:-nothing}, not at the merge commit ${sha:0:7}" >&2; exit 1; }
echo "tag: ${tag} at ${sha:0:7}"
if [ -f .icm/uat/CONTEXT.md ]; then
  echo "next: production moves on Jamie's word promote: .icm/scripts/promote.sh run --tag ${tag}"
else
  echo "next: nothing. Production already follows main. The release is the tag and the changelog."
fi
