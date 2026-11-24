#!/usr/bin/env bash
# ci-status.sh — one read of the checks of one pull request.
#
# Usage: ci-status.sh <pull request number | ticket> [--watch] [--all]
#
# A ticket (SUS-123, or a markdown stub) gives the pull request of its run on this branch,
# or the open pull request of the ticket.
# The script reads the head commit of the pull request. It prints one line for each check,
# then one verdict. It reads the check runs and the commit statuses. When this checkout is
# on the branch of the pull request and GitHub shows another head commit than HEAD, the
# verdict waits: GitHub has not read the push yet. A verdict is never for an older commit.
# A branch that conflicts with the default branch (another run merged first) is RED, with
# one line: merge the default branch into the branch (not a rebase), resolve, and push.
#
#   --watch  reads again each 60 seconds while a check is pending or no check is listed,
#            30 minutes at most. The wait is in the script and costs no model turn.
#            While a check runs, one read is two calls to GitHub: the pull request and
#            the check runs of its head commit. Give this command one time and wait for
#            it. Do not put a loop around it: GitHub permits 5000 calls in one hour for
#            all the sessions of the operator.
#
# When GitHub refuses a call because of the rate limit, the script stops one time with
# RESULT: STOP GitHub rate limit, resets at HH:MM. Do not read again before that time.
#
#   --all    counts icm-gate too. release.sh uses it before the merge.
#
# Without --all the check icm-gate is not counted: it waits for the operator's tick. That
# wait is not a failure. The script prints one line for it.
# A draft runs no job of ci.yml: its checks show as skipped. After the change to ready, the
# verdict waits until a run of ci.yml that started at that change or later is complete.
# Last line: RESULT: GREEN (exit 0) | RESULT: RED (exit 1) | RESULT: PENDING (exit 8).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
. "$here/lib/ticket.sh"
. "$here/lib/gh.sh"
help_if_asked "$@"

usage="usage: ci-status.sh <pull request number | ticket> [--watch] [--all]"
number="" watch=0 skip=$'^icm-gate\t' arg=""
for a in "$@"; do
  case "$a" in
    --watch) watch=1 ;;
    --all) skip=$'^\t' ;;
    -*) stop "unknown option $a. $usage" ;;
    *) [ -z "$arg" ] || stop "$usage"; arg="$a" ;;
  esac
done
[ -n "$arg" ] || stop "$usage"
need git gh jq
cd "$(icm_root)"
case "$arg" in
  '#'[0-9]* | [0-9]*) number="${arg#'#'}"; [[ "$number" =~ ^[0-9]+$ ]] || stop "$usage" ;;
  *) number="$(gh_pr_of "$arg")" || stop "no open pull request for $arg. $usage" ;;
esac

err="$(mktemp)"
trap 'rm -f "$err"' EXIT
# api_stop <text>: a call to GitHub failed. A rate limit has its own line, one time.
api_stop() {
  if gh_rate_limited "$err"; then
    stop "GitHub rate limit, resets at $(gh_rate_reset). Do not read again before that time"
  fi
  cat "$err" >&2
  stop "$1"
}
[ "$skip" = $'^\t' ] && gate="" || gate="icm-gate"
interval="${ICM_WATCH_S:-60}"
deadline=$((SECONDS + ${ICM_WATCH_MAX_S:-1800}))
while :; do
  pr="$(gh_pr "$number" 2>"$err")" || api_stop "the pull request #$number was not read"
  sha="$(jq -r '.head.sha' <<<"$pr")" draft="$(jq -r '.draft' <<<"$pr")" ci_wait="" conflict=""
  ref="$(jq -r '.head.ref' <<<"$pr")"
  # GitHub shows a commit that is older than the pushed HEAD: it has not read the push yet.
  if [ "$(git symbolic-ref -q --short HEAD || true)" = "$ref" ] && [ "$(git rev-parse HEAD)" != "$sha" ] \
    && git merge-base --is-ancestor "$sha" HEAD 2>/dev/null \
    && git merge-base --is-ancestor HEAD "origin/$ref" 2>/dev/null; then
    ci_wait="GitHub shows ${sha:0:7}, the branch is at $(git rev-parse --short=7 HEAD): GitHub has not read the push yet"
  fi
  conflict="$(gh_conflict "$pr")"
  # The short read of a wait: GitHub did not read the push yet, or a check runs. The
  # other reads (the timeline, the runs, the statuses) are not necessary before that ends.
  if [ "$watch" -eq 1 ] && [ -z "$conflict" ] && [ "$SECONDS" -lt "$deadline" ]; then
    if [ -z "$ci_wait" ]; then
      running="$(gh_running "$sha" "$gate" 2>"$err")" || api_stop "the check runs of #$number were not read"
    fi
    if [ -n "$ci_wait" ] || [ "${running:-0}" -gt 0 ]; then
      sleep "$interval"
      continue
    fi
  fi
  if [ -z "$ci_wait" ] && [ "$draft" != true ] && [ -f .github/workflows/ci.yml ]; then
    since="$(gh_ready_at "$number" 2>"$err")" || api_stop "the timeline of #$number was not read"
    if [ -n "$since" ]; then
      runs="$(gh_runs_since ci.yml "$sha" "$since" 2>"$err")" || api_stop "the runs of ci.yml were not read"
      if [ -z "$runs" ]; then ci_wait="ci.yml has not started since the change to ready"
      elif grep -qvx completed <<<"$runs"; then ci_wait="ci.yml runs"; fi
    fi
  fi
  all="$(gh_checks "$sha" 2>"$err")" || { ! gh_rate_limited "$err" || api_stop "the checks were not read"; all=""; }
  checks="$(grep -v "$skip" <<<"$all" || true)"
  waiting=0
  if [ -z "$conflict" ] && { [ -n "$ci_wait" ] || [ -z "$checks" ] \
    || printf '%s\n' "$checks" | cut -f2 | grep -qxE 'pending|waits'; }; then
    waiting=1
  fi
  if [ "$watch" -eq 0 ] || [ "$waiting" -eq 0 ] || [ "$SECONDS" -ge "$deadline" ]; then
    break
  fi
  sleep "$interval"
done

echo "#${number} at ${sha:0:7}"
[ "$draft" != true ] || echo "#${number} is a draft: ci.yml runs its checks when it is ready"
[ -z "$checks" ] || printf '%s\n' "$checks" | sort
if [ "$skip" != $'^\t' ] && grep -qE $'^icm-gate\t(waits|failure)' <<<"$all"; then
  echo "icm-gate waits for the operator's tick of Ready to merge. This is a wait, not a failure"
fi
if [ -n "$conflict" ]; then
  echo "RESULT: RED $conflict"
  exit 1
fi
if [ -n "$ci_wait" ]; then
  echo "RESULT: PENDING $ci_wait"
  exit 8
fi
if [ -z "$checks" ]; then
  echo "RESULT: PENDING no check is listed"
  exit 8
fi
if printf '%s\n' "$checks" | cut -f2 | grep -qvxE 'ok|pending|waits'; then
  echo "RESULT: RED"
  exit 1
fi
if printf '%s\n' "$checks" | cut -f2 | grep -qxE 'pending|waits'; then
  echo "RESULT: PENDING"
  exit 8
fi
echo "RESULT: GREEN"
