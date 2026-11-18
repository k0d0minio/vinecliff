#!/usr/bin/env bash
# questions.sh — read the questions of one run and their answers from the pull request body.
#
# Usage: questions.sh <ticket | run id>
#
# The pull request body is the home of the answers (rules/questions.md). This script
# copies the block between <!-- questions:start --> and <!-- questions:end --> to
# .icm/runs/<id>/questions.md and prints it. It writes nothing on GitHub.
#
# Last line: "RESULT: OK <n> answered" (exit 0), "RESULT: WAITING <k> of <n>" (exit 4)
# or "RESULT: STOP <reason>" (exit 1). A run with no question gives RESULT: OK 0 answered.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
. "$here/lib/ticket.sh"
. "$here/lib/gh.sh"

[ $# -eq 1 ] || stop "usage: questions.sh <ticket>"
need git gh jq
cd "$(icm_root)"
id="$(run_id "$1")"
[ -n "$id" ] || stop "$1 is not a ticket of this repo"
run=".icm/runs/$id"
[ -f "$run/run.md" ] || stop "no run for $1 on this branch"
number="$(field pr "$run/run.md" | tr -d '#')"
[[ "$number" =~ ^[0-9]+$ ]] || stop "run.md has no pull request number"

body="$(gh_pr "$number" | jq -r '.body // ""' | tr -d '\r')" || stop "the pull request #$number was not read"
block="$(printf '%s\n' "$body" | awk '
  index($0, "<!-- questions:end -->") { inside = 0 }
  inside { print }
  index($0, "<!-- questions:start -->") { inside = 1 }')"
total="$(printf '%s\n' "$block" | grep -cE '^### Q[0-9]+\.' || true)"
if [ "$total" -eq 0 ]; then
  echo "RESULT: OK 0 answered. The run has no question"
  exit 0
fi
printf '%s\n' "$block" > "$run/questions.md"
printf '%s\n' "$block"
waiting="$(printf '%s\n' "$block" | grep -cE '^- answer: *(_waiting_)? *$' || true)"
if [ "$waiting" -gt 0 ]; then
  echo "RESULT: WAITING $waiting of $total"
  exit 4
fi
echo "RESULT: OK $total answered"
