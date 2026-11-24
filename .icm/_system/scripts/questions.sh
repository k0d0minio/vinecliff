#!/usr/bin/env bash
# questions.sh — the questions of one run and their answers in the pull request body.
#
# Usage:
#   questions.sh <ticket | run id>
#   questions.sh <ticket | run id> --answer <Q1> "<answer>" [--note "<text>"]
#
# The pull request body is the home of the answers (rules/questions.md). The script
# copies the block between <!-- questions:start --> and <!-- questions:end --> to
# .icm/runs/<id>/questions.md and prints it.
#
#   --answer  writes the answer that the operator gave in the chat to the body first, on
#             the line "- answer:" of that question. For single and multi the answer is one
#             option or some options of the list, with " | " between them, as the operator
#             said them. The line "- note:" gets the note, or "answered in the chat".
#             Give the operator's words. Do not choose for the operator.
#
# Last line: "RESULT: OK <n> answered" (exit 0), "RESULT: WAITING <k> of <n>" (exit 4)
# or "RESULT: STOP <reason>" (exit 1). A run with no question gives RESULT: OK 0 answered.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
. "$here/lib/ticket.sh"
. "$here/lib/gh.sh"
help_if_asked "$@"

usage="usage: questions.sh <ticket> [--answer <Q1> \"<answer>\" [--note \"<text>\"]]"
ticket="" qid="" answer="" note=""
while [ $# -gt 0 ]; do
  case "$1" in
    --answer) qid="${2:-}" answer="${3:-}"; [ $# -ge 3 ] || stop "$usage"; shift 3 ;;
    --note) note="${2:-}"; [ $# -ge 2 ] || stop "$usage"; shift 2 ;;
    -*) stop "unknown option $1. $usage" ;;
    *) [ -z "$ticket" ] || stop "$usage"; ticket="$1"; shift ;;
  esac
done
[ -n "$ticket" ] || stop "$usage"
need git gh jq
cd "$(icm_root)"
id="$(run_id "$ticket")"
[ -n "$id" ] || stop "$ticket is not a ticket of this repo"
run=".icm/runs/$id"
[ -f "$run/run.md" ] || stop "no run for $ticket on this branch"
number="$(field pr "$run/run.md" | tr -d '#')"
[[ "$number" =~ ^[0-9]+$ ]] || stop "run.md has no pull request number"

body="$(gh_pr "$number" | jq -r '.body // ""' | tr -d '\r')" || stop "the pull request #$number was not read"
block() { printf '%s\n' "$1" | awk '
  index($0, "<!-- questions:end -->") { inside = 0 }
  inside { print }
  index($0, "<!-- questions:start -->") { inside = 1 }'; }

if [ -n "$qid" ]; then
  [[ "$qid" =~ ^Q[0-9]{1,2}$ ]] || stop "the question must be Q1, Q2 ... $usage"
  answer="$(tr -s '\n\t' '  ' <<<"$answer" | sed -E 's/^ +| +$//g')"
  note="$(tr -s '\n\t' '  ' <<<"${note:-answered in the chat}" | sed -E 's/^ +| +$//g')"
  [ -n "$answer" ] || stop "the answer is empty"
  entry="$(block "$body" | awk -v q="### $qid." 'index($0, q) == 1 { f = 1; print; next } f && /^### / { exit } f')"
  [ -n "$entry" ] || stop "#$number has no question $qid"
  type="$(sed -n 's/^- type: *//p' <<<"$entry")"
  if [ "$type" = single ] || [ "$type" = multi ]; then
    options="$(sed -n 's/^- options: *//p' <<<"$entry" | tr '|' '\n' | sed -E 's/^ +| +$//g')"
    picked="$(tr '|' '\n' <<<"$answer" | sed -E 's/^ +| +$//g' | grep -v '^$')"
    while IFS= read -r o; do
      grep -qxF -- "$o" <<<"$options" || stop "\"$o\" is not an option of $qid: $(paste -sd '|' <<<"$options" | sed 's/|/ | /g'). Put the operator's words in --note and give the option that they named"
    done <<<"$picked"
    [ "$type" = multi ] || [ "$(wc -l <<<"$picked")" -eq 1 ] || stop "$qid takes one option"
    answer="$(paste -sd '|' <<<"$picked" | sed 's/|/ | /g')"
  fi
  body="$(printf '%s\n' "$body" | awk -v q="### $qid." -v a="- answer: $answer" -v n="- note: $note" '
    index($0, "<!-- questions:start -->") { inside = 1 }
    index($0, "<!-- questions:end -->") { inside = 0 }
    inside && index($0, q) == 1 { f = 1; print; next }
    f && (/^### / || !inside) { f = 0 }
    f && /^- note:/ { next }
    f && /^- answer:/ { print a; print n; next }
    { print }')"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  printf '%s\n' "$body" > "$tmp"
  gh api -X PATCH "repos/$(gh_repo)/pulls/${number}" -F body=@"$tmp" >/dev/null \
    || stop "GitHub refused the new body of #$number"
  echo "#$number: the answer of $qid is written: $answer"
fi

questions="$(block "$body")"
total="$(printf '%s\n' "$questions" | grep -cE '^### Q[0-9]+\.' || true)"
if [ "$total" -eq 0 ]; then
  echo "RESULT: OK 0 answered. The run has no question"
  exit 0
fi
printf '%s\n' "$questions" > "$run/questions.md"
printf '%s\n' "$questions"
waiting="$(printf '%s\n' "$questions" | grep -cE '^- answer: *(_waiting_)? *$' || true)"
if [ "$waiting" -gt 0 ]; then
  echo "RESULT: WAITING $waiting of $total"
  exit 4
fi
echo "RESULT: OK $total answered"
