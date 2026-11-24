#!/usr/bin/env bash
# icm-only.sh — the job icm-only of the workflow ci. Only CI runs it (rc25, JAM-570).
#
# The close-out commit of release.sh changes only the records of a run: .icm/runs/,
# .icm/archive/ and .icm/intake/. The code is the code that CI examined before the push.
# This script says if the jobs code and database can skip the push. They skip it when each
# is true:
#   1. The event is a push to a pull request (synchronize).
#   2. The head before the push is in the history of the new head, and each file that the
#      push changes is a record of a run.
#   3. The check code is green on the head before the push, or on an older commit of the
#      branch. Each commit after that green commit changes only records and has one parent.
# Each doubt gives the full CI: a different event, a different file, a merge commit, no green
# check code in the last ICM_ONLY_DEPTH commits (default 10), a fault of a call to GitHub.
#
# Input (env): EVENT, ACTION, BEFORE (the head before the push), AFTER (the new head),
# GH_REPO, GH_TOKEN. Output: the line skip=true or skip=false in $GITHUB_OUTPUT.
# Last line: "RESULT: SKIP <reason>" or "RESULT: FULL <reason>". Exit 0.
set -uo pipefail

answer() {
  [ -z "${GITHUB_OUTPUT:-}" ] || echo "skip=$1" >> "$GITHUB_OUTPUT"
  echo "RESULT: $2"
  exit 0
}
full() { answer false "FULL $1"; }
records='^\.icm/(runs|archive|intake)/'
# only_records: each file name of stdin is a record of a run. No file: no code changed.
only_records() { local other; other="$(grep -vE "$records")"; [ -z "$other" ]; }

[ "${EVENT:-}" = pull_request ] && [ "${ACTION:-}" = synchronize ] \
  || full "the event is not a push to a pull request"
[ -n "${GH_REPO:-}" ] && [ -n "${AFTER:-}" ] || full "GH_REPO or AFTER is empty"
case "${BEFORE:-}" in '' | *[!0-9a-f]* | 0000000000000000000000000000000000000000)
  full "no head before the push" ;; esac
command -v gh > /dev/null && command -v jq > /dev/null || full "no gh or no jq"

# 2. The push. The compare of GitHub lists 300 files at most: more is not a close-out.
push="$(gh api "repos/$GH_REPO/compare/$BEFORE...$AFTER")" || full "the push was not read"
jq -e '(.status == "ahead" or .status == "identical") and ((.files // []) | length) < 300' \
  <<<"$push" > /dev/null || full "the head before the push is not in the history of the new head"
jq -r '.files[]?.filename' <<<"$push" | only_records \
  || full "the push changes a file that is not a record of a run"

# 3. The newest commit with a green check code. The newest check run of a commit counts.
sha="$BEFORE"
for _ in $(seq 1 "${ICM_ONLY_DEPTH:-10}"); do
  code="$(gh api "repos/$GH_REPO/commits/$sha/check-runs?check_name=code&per_page=100")" \
    || full "the check runs of ${sha:0:7} were not read"
  state="$(jq -r '[.check_runs[] | select(.name == "code" and .status == "completed")]
    | sort_by(.completed_at) | last | .conclusion // ""' <<<"$code")"
  [ "$state" != success ] || answer true "SKIP the push changes only the records of a run, and the check code is green on ${sha:0:7}"
  commit="$(gh api "repos/$GH_REPO/commits/$sha")" || full "the commit ${sha:0:7} was not read"
  jq -e '(.parents | length) == 1 and ((.files // []) | length) < 300' <<<"$commit" > /dev/null \
    || full "no green check code before ${sha:0:7}, a commit with no single parent"
  jq -r '.files[]?.filename' <<<"$commit" | only_records \
    || full "the check code is not green on ${sha:0:7}, a commit that changes a file of code"
  sha="$(jq -r '.parents[0].sha' <<<"$commit")"
done
full "no green check code in the last ${ICM_ONLY_DEPTH:-10} commits"
