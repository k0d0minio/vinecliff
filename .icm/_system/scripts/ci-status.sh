#!/usr/bin/env bash
# ci-status.sh — one read of the checks of one pull request.
#
# Usage: ci-status.sh <pull request number> [--watch]
#
# The script reads the head commit of the pull request. It prints one line for each check,
# then one verdict. It reads the check runs and the commit statuses.
#
#   --watch  reads again each 15 seconds while a check is pending or no check is listed,
#            30 minutes at most. The wait is in the script and costs no model turn.
#
#   --all    counts icm-gate too. release.sh uses it before the merge.
#
# Without --all the check icm-gate is not counted: it waits for the operator's tick.
# A draft runs no job of ci.yml: its checks show as skipped. After the change to ready, the
# verdict waits until a run of ci.yml that started at that change or later is complete.
# Last line: RESULT: GREEN (exit 0) | RESULT: RED (exit 1) | RESULT: PENDING (exit 8).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
. "$here/lib/gh.sh"

number="" watch=0 skip=$'^icm-gate\t'
for a in "$@"; do
  case "$a" in
    --watch) watch=1 ;;
    --all) skip=$'^\t' ;;
    '' | *[!0-9]*) stop "usage: ci-status.sh <pull request number> [--watch]" ;;
    *) number="$a" ;;
  esac
done
[ -n "$number" ] || stop "usage: ci-status.sh <pull request number> [--watch]"
need git gh jq
cd "$(icm_root)"

deadline=$((SECONDS + 1800))
while :; do
  pr="$(gh_pr "$number")" || stop "the pull request #$number was not read"
  sha="$(jq -r '.head.sha' <<<"$pr")" draft="$(jq -r '.draft' <<<"$pr")" ci_wait=""
  if [ "$draft" != true ] && [ -f .github/workflows/ci.yml ]; then
    since="$(gh_ready_at "$number")" || stop "the timeline of #$number was not read"
    if [ -n "$since" ]; then
      runs="$(gh_runs_since ci.yml "$sha" "$since")" || stop "the runs of ci.yml were not read"
      if [ -z "$runs" ]; then ci_wait="ci.yml has not started since the change to ready"
      elif grep -qvx completed <<<"$runs"; then ci_wait="ci.yml runs"; fi
    fi
  fi
  checks="$(gh_checks "$sha" | grep -v "$skip" || true)"
  waiting=0
  if [ -n "$ci_wait" ] || [ -z "$checks" ] || printf '%s\n' "$checks" | cut -f2 | grep -qx pending; then
    waiting=1
  fi
  if [ "$watch" -eq 0 ] || [ "$waiting" -eq 0 ] || [ "$SECONDS" -ge "$deadline" ]; then
    break
  fi
  sleep 15
done

echo "#${number} at ${sha:0:7}"
[ "$draft" != true ] || echo "#${number} is a draft: ci.yml runs its checks when it is ready"
[ -z "$checks" ] || printf '%s\n' "$checks" | sort
if [ -n "$ci_wait" ]; then
  echo "RESULT: PENDING $ci_wait"
  exit 8
fi
if [ -z "$checks" ]; then
  echo "RESULT: PENDING no check is listed"
  exit 8
fi
if printf '%s\n' "$checks" | cut -f2 | grep -qvxE 'ok|pending'; then
  echo "RESULT: RED"
  exit 1
fi
if printf '%s\n' "$checks" | cut -f2 | grep -qx pending; then
  echo "RESULT: PENDING"
  exit 8
fi
echo "RESULT: GREEN"
