#!/usr/bin/env bash
# resolve-run.sh — find the run of one ticket and print its state. It never makes a run.
#
# Usage: resolve-run.sh <ticket | run id> [--write-stub]
#
# Each stage and lane calls this script first. The last line is the instruction:
#   RESULT: OK              the run is on this branch. Its facts are printed above
#   RESULT: NONE <text>     no run exists. Only a start command can continue
#   RESULT: STOP <reason>   do not continue. The reason says what to do
#
# A closed run (.icm/archive/<id>) is finished only when its pull request is merged or
# closed. While its pull request is open the script prints its facts with "phase:
# closed-out" and RESULT: OK: the next step is release.sh <number>.
# For RESULT: OK the script prints: id, ticket, branch, lane, pr, phase, pr_state, draft,
# spec_approved, ready_to_merge and conflict. A gate value is yes, no or none (rules/gates.md).
# conflict: yes means that the default branch moved and the branch conflicts with it. The
# line after it says what to do first: merge the default branch in, resolve, push.
#
# --write-stub  Linear only. Writes .icm/intake/tickets/<KEY>.md when the spec is
#               approved, or when the run is a lane run. Markdown: does nothing.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
. "$here/lib/ticket.sh"
. "$here/lib/gh.sh"
help_if_asked "$@"

ticket="" stub=0
for a in "$@"; do
  case "$a" in
    --write-stub) stub=1 ;;
    -*) stop "unknown option $a" ;;
    *) ticket="$a" ;;
  esac
done
[ -n "$ticket" ] || stop "usage: resolve-run.sh <ticket> [--write-stub]"
need git gh jq
cd "$(icm_root)"

id="$(run_id "$ticket")"
[ -n "$id" ] || stop "$ticket is not a ticket of this repo"
run=".icm/runs/$id"

closed=0
if [ -d ".icm/archive/$id" ]; then
  number="$(field pr ".icm/archive/$id/run.md" | tr -d '#')"
  if [[ "$number" =~ ^[0-9]+$ ]] && [ "$(gh_pr "$number" | jq -r 'if .merged then "merged" else .state end')" = open ]; then
    closed=1 run=".icm/archive/$id"
  else
    stop "the run $id is finished (.icm/archive/$id). A follow-up needs a new ticket"
  fi
fi

if [ ! -f "$run/run.md" ]; then
  # The run folder is on the run's branch. Look for an open pull request of the ticket.
  key="$(ticket_norm "$ticket")"
  pulls="$(gh_open_pulls 2>/dev/null)" || stop "GitHub was not read. Cannot tell if $ticket has a run"
  other="$(jq -r --arg id "$id" --arg key "${key:-$id}" '
    .[] | select((.title | startswith($key + ":")) or .head.ref == $id
                 or (.head.ref | ascii_downcase | test("(^|[/_-])" + $id + "($|[/_-])")))
    | .head.ref' <<<"$pulls" | head -n1)"
  if [ -n "$other" ]; then
    stop "the run of $ticket is on the branch $other. Run: git fetch origin && git switch $other"
  fi
  echo "RESULT: NONE no run for $ticket. A start command makes one"
  exit 3
fi

branch="$(field branch "$run/run.md")"
current="$(git symbolic-ref -q --short HEAD || true)"
lane="$(field lane "$run/run.md")"
number="$(field pr "$run/run.md" | tr -d '#')"
echo "id: $id"
echo "ticket: $(field ticket "$run/run.md")"
echo "branch: $branch"
echo "lane: $lane"
echo "pr: ${number:-none}"
if [ "$closed" -eq 1 ]; then echo "phase: closed-out"; else echo "phase: $(field phase "$run/status.md")"; fi
[ "$current" = "$branch" ] || stop "this checkout is on ${current:-a detached HEAD}. Run: git switch $branch"
[[ "$number" =~ ^[0-9]+$ ]] || stop "run.md has no pull request number. new-run.sh did not finish"

pr="$(gh_pr "$number")" || stop "the pull request #$number was not read"
state="$(jq -r 'if .merged then "merged" else .state end' <<<"$pr")"
spec="$(jq -r '.body // ""' <<<"$pr" | gate_state spec-approved)"
ready="$(jq -r '.body // ""' <<<"$pr" | gate_state ready-to-merge)"
echo "pr_state: $state"
echo "draft: $(jq -r '.draft' <<<"$pr")"
echo "url: $(jq -r '.html_url' <<<"$pr")"
echo "spec_approved: $spec"
echo "ready_to_merge: $ready"
[ "$state" = open ] || stop "the pull request #$number is $state"
conflict="$(gh_conflict "$pr")"
echo "conflict: $([ -n "$conflict" ] && echo yes || echo no)"
[ -z "$conflict" ] || echo "Do this first: $conflict"
if [ "$closed" -eq 1 ]; then
  echo "The run is closed out on its branch. Its pull request is open: the next step is release.sh $number"
  echo "RESULT: OK"
  exit 0
fi

if [ "$stub" -eq 1 ] && [ "$(ticket_source)" = linear ]; then
  if [ "$lane" = spine ] && [ "$spec" != yes ]; then
    stop "Spec approved is not ticked. No stub was written"
  fi
  write_stub "$id"
fi
echo "RESULT: OK"
