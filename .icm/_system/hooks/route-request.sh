#!/usr/bin/env bash
# route-request.sh — UserPromptSubmit hook. Finds a command and a ticket in the prompt and
# prints one line "[icm-router] Route: ...". It never blocks: each path ends with exit 0.
#
# A command is: a start word (rules/triggers.txt), or build, release, revise or a lane word
# as the first word, with a ticket. A lane word is the name of a folder of lanes/ that has
# a CONTEXT.md. "ticket <what>" and "write a ticket" ask for a new ticket and need no
# ticket. A prompt that ends with "?" is a question, not a command. The hook prints
# nothing when it finds no command.
input="$(cat)"
root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
cd "$root" 2>/dev/null || exit 0
sys=".icm/_system"
[ -f "$sys/rules/triggers.txt" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
. "$sys/scripts/lib/project.sh" 2>/dev/null || exit 0
. "$sys/scripts/lib/ticket.sh" 2>/dev/null || exit 0

prompt="$(jq -r '.prompt // empty' <<<"$input" 2>/dev/null | head -c 2000 | tr '[:upper:]' '[:lower:]' | tr '\n' ' ')"
prompt="${prompt#/pipeline }"
[ -n "$prompt" ] || exit 0
case "$prompt" in *"?" | *"? ") exit 0 ;; esac

say() { echo "[icm-router] Route: $*"; }

# A request to write a ticket: "ticket <what>", or "write|add|create|file|open a ticket".
if grep -qE "^ticket[ :]|(^|[^a-z])(write|add|create|file|open|make|draft)( me)?( up)? (a |an |the |one )?(new )?(ticket|stub)([^a-z]|$)" <<<"$prompt"; then
  say "write a ticket. Read $sys/stages/ticket/CONTEXT.md and follow it. Do not start the work."
  exit 0
fi

# The ticket.
ticket=""
if [ "$(ticket_source)" = linear ]; then
  # With a team key: "sus-123", "sus 123" and "sus123". With no team key: only "abc-123".
  key="$(team_key | tr '[:upper:]' '[:lower:]')"
  sep='[- ]?'
  [ -n "$key" ] || { key='[a-z][a-z0-9]{1,9}'; sep='-'; }
  found="$(grep -oE "(^|[^a-z0-9])${key}${sep}[0-9]+" <<<"$prompt" | head -n1 | sed -E 's/^[^a-z0-9]//')"
  [ -z "$found" ] || ticket="$(printf '%s' "$found" | sed -E "s/^(${key})${sep}([0-9]+)\$/\\1-\\2/" | tr '[:lower:]' '[:upper:]')"
else
  for ref in $(grep -oE '[a-z0-9][a-z0-9-]*/[a-z0-9][a-z0-9-]*' <<<"$prompt"); do
    if [ -f ".icm/intake/${ref}.md" ]; then ticket="$ref"; break; fi
  done
fi
[ -n "$ticket" ] || exit 0

# The command.
verb="" lane="" first="${prompt%% *}"
case "$first" in
  build | release | revise) verb="$first" ;;
  *) if [[ "$first" =~ ^[a-z][a-z0-9-]*$ ]] && [ "$first" != spine ] && [ -f "$sys/lanes/$first/CONTEXT.md" ]; then
       verb=lane lane="$first"
     fi ;;
esac
if [ -z "$verb" ]; then
  words="$(grep -vE '^[[:space:]]*(#|$)' "$sys/rules/triggers.txt" | sed -E 's/[^a-z0-9 '"'"']//g' | paste -sd '|')"
  if [ -n "$words" ] && grep -qE "(^|[^a-z])(${words})([^a-z]|$)" <<<"$prompt"; then verb=start; fi
fi
[ -n "$verb" ] || exit 0

id="$(run_id "$ticket")"
if [ -d ".icm/archive/$id" ]; then
  say "the run of $ticket is finished (.icm/archive/$id). A follow-up needs a new ticket. Tell the operator."
elif [ -f ".icm/runs/$id/run.md" ]; then
  phase="$(field phase ".icm/runs/$id/status.md")"
  case "$verb" in
    build | release) say "$verb $ticket. Read $sys/stages/$verb/CONTEXT.md and follow it." ;;
    revise) say "revise $ticket. Read $sys/stages/define/CONTEXT.md, section Revise." ;;
    *) say "$ticket has a run in phase ${phase:-unknown}. Do not start it again. Run $sys/scripts/resolve-run.sh $ticket, then continue with the contract of that phase." ;;
  esac
else
  case "$verb" in
    start) say "start $ticket, if the operator means to start work on it now. Then read $sys/stages/define/CONTEXT.md and follow it. If the prompt only talks about the ticket, ignore this line." ;;
    lane) say "$lane lane for $ticket. Read $sys/lanes/$lane/CONTEXT.md and follow it." ;;
    *) say "$verb $ticket, but no run is on this branch. Run $sys/scripts/resolve-run.sh $ticket and obey its RESULT line." ;;
  esac
fi
exit 0
