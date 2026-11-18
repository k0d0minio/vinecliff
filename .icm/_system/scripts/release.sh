#!/usr/bin/env bash
# release.sh — the Release stage as one command: close the run and merge its pull request.
#
# Usage: release.sh <pull request number>
#
# A session runs it (stages/release/CONTEXT.md). The BAXTER HUD runs it when the operator
# presses "Merge now". It needs a checkout at the head commit of the pull request.
#
# Steps. Each step can stop the release:
#   1. The pull request is open, is not a draft, and Ready to merge is ticked.
#   2. The checkout is at the head commit of the pull request.
#   3. The checks are green. The script waits while a check is pending.
#   4. If the pull request has a run (.icm/runs/<id>/ with this number): close-out.sh,
#      then push, then wait until GitHub shows the new head on the pull request. A pull
#      request with no run has no close-out.
#   5. All checks are green on the new head, icm-gate too.
#   6. merge.sh. It checks the tick, the checks and the conflicts again.
#
# It ticks nothing. It does not merge the default branch in: on a conflict it stops.
# Last line: "RESULT: OK <merge commit>" or "RESULT: STOP <reason>".
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
. "$here/lib/gh.sh"

[ $# -eq 1 ] || stop "usage: release.sh <pull request number>"
case "$1" in '' | *[!0-9]*) stop "usage: release.sh <pull request number>" ;; esac
number="$1"
need git gh jq
cd "$(icm_root)"

pr="$(gh_pr "$number")" || stop "the pull request #$number was not read"
state="$(jq -r 'if .merged then "merged" else .state end' <<<"$pr")"
branch="$(jq -r '.head.ref' <<<"$pr")"
[ "$state" = open ] || stop "the pull request #$number is $state"
[ "$(jq -r '.draft' <<<"$pr")" = false ] || stop "the pull request #$number is a draft"
ready="$(jq -r '.body // ""' <<<"$pr" | gate_state ready-to-merge)"
[ "$ready" = yes ] || stop "Ready to merge is not ticked on #$number (gate: $ready). The operator ticks it"
[ "$(git rev-parse HEAD)" = "$(jq -r '.head.sha' <<<"$pr")" ] \
  || stop "this checkout is not at the head of #$number. Check out the branch $branch and pull"
[ -z "$(git status --porcelain)" ] || stop "the working tree is not clean. Commit first"

# wait_green [--all]: read CI and wait while a check is pending.
wait_green() {
  local out
  out="$(bash "$here/ci-status.sh" "$number" --watch "$@")" || {
    printf '%s\n' "$out"
    stop "the checks of #$number are not green: $(printf '%s\n' "$out" | tail -n1)"
  }
}
wait_green

run=""
for file in .icm/runs/*/run.md; do
  [ -f "$file" ] || continue
  if [ "$(field pr "$file" | tr -d '#')" = "$number" ]; then run="$(basename "$(dirname "$file")")"; fi
done
if [ -n "$run" ]; then
  bash "$here/close-out.sh" "$run" | tail -n1
  [ -d ".icm/archive/$run" ] || stop "close-out did not move the run $run"
  git push -q origin "HEAD:refs/heads/$branch" || stop "git push failed. The close-out commit is local"
  echo "close-out: the run $run is in .icm/archive/, and the branch $branch is pushed"
  # GitHub needs a moment to read the push. Until then the pull request has the head of
  # before, whose checks are green: a read of the checks at that moment is not a verdict.
  head="$(git rev-parse HEAD)"
  waited=0
  until [ "$(gh_pr "$number" | jq -r '.head.sha')" = "$head" ]; do
    [ "$waited" -lt "${ICM_HEAD_WAIT_S:-60}" ] \
      || stop "GitHub does not show the close-out commit on #$number. The run is closed. Run the release again"
    sleep 2
    waited=$((waited + 2))
  done
else
  echo "close-out: #$number has no run folder. Nothing to close"
fi

wait_green --all
exec bash "$here/merge.sh" "$number"
