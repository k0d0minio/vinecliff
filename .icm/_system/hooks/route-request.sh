#!/usr/bin/env bash
# route-request.sh — UserPromptSubmit hook. Finds a command and a ticket in the prompt and
# prints one line "[icm-router] Route: ...". It never blocks: each path ends with exit 0.
#
# A command is: a start word (rules/triggers.txt), or build, release, revise or a lane word
# as the first word, with a ticket. A lane word is the name of a folder of lanes/ that has
# a CONTEXT.md. "ticket <what>" and "write a ticket" ask for a new ticket and need no
# ticket. A prompt that ends with "?" is a question, not a command. The hook prints
# nothing when it finds no command.
# The text of a <system-reminder> block is not the operator's: the hook drops it. A pair
# "<command> <ticket>" at the start of the prompt or in backticks (`tweak SUS-12`) wins. With
# no such pair, a prompt that names more than one ticket gets no route, only a line that
# says so: the hook does not guess the ticket.
input="$(cat)"
root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
cd "$root" 2>/dev/null || exit 0
sys=".icm/_system"
[ -f "$sys/rules/triggers.txt" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
. "$sys/scripts/lib/project.sh" 2>/dev/null || exit 0
. "$sys/scripts/lib/ticket.sh" 2>/dev/null || exit 0

prompt="$(jq -r '.prompt // empty' <<<"$input" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr '\n' ' ')"
while [[ "$prompt" == *"<system-reminder>"*"</system-reminder>"* ]]; do
  prompt="${prompt%%<system-reminder>*} ${prompt#*</system-reminder>}"
done
prompt="$(sed -E 's/^ +//' <<<"${prompt:0:2000}")"
prompt="${prompt#/pipeline }"
[ -n "$prompt" ] || exit 0
case "$prompt" in *"?" | *"? ") exit 0 ;; esac

say() { echo "[icm-router] Route: $*"; }

# A request to write a ticket: "ticket <what>", or "write|add|create|file|open a ticket".
if grep -qE "^ticket[ :]|(^|[^a-z])(write|add|create|file|open|make|draft)( me)?( up)? (a |an |the |one )?(new )?(ticket|stub)([^a-z]|$)" <<<"$prompt"; then
  say "write a ticket. Read $sys/stages/ticket/CONTEXT.md and follow it. Do not start the work."
  exit 0
fi

# The tickets, in the order of the prompt. A Linear key gets one spelling: sus-123.
tickets=""
if [ "$(ticket_source)" = linear ]; then
  # With a team key: "sus-123", "sus 123" and "sus123". With no team key: only "abc-123".
  key="$(team_key | tr '[:upper:]' '[:lower:]')"
  sep='[- ]?'
  [ -n "$key" ] || { key='[a-z][a-z0-9]{1,9}'; sep='-'; }
  prompt="$(sed -E "s/(^|[^a-z0-9])(${key})${sep}([0-9]+)/\\1\\2-\\3/g" <<<"$prompt")"
  tickets="$(grep -oE "(^|[^a-z0-9])${key}-[0-9]+" <<<"$prompt" | sed -E 's/^[^a-z0-9]//' | awk '!seen[$0]++')"
else
  for ref in $(grep -oE '[a-z0-9][a-z0-9-]*/[a-z0-9][a-z0-9-]*' <<<"$prompt"); do
    [ ! -f ".icm/intake/${ref}.md" ] || tickets+="$ref"$'\n'
  done
  tickets="$(awk 'NF && !seen[$0]++' <<<"$tickets")"
fi
[ -n "$tickets" ] || exit 0

# The command words: build, release, revise, the lanes, and the start words.
lanes="$(for f in "$sys"/lanes/*/CONTEXT.md; do [ -f "$f" ] && basename "$(dirname "$f")"; done | grep -vx spine | paste -sd '|')"
starts="$(grep -vE '^[[:space:]]*(#|$)' "$sys/rules/triggers.txt" | sed -E 's/[^a-z0-9 '"'"']//g' | paste -sd '|')"
verbs="build|release|revise${lanes:+|$lanes}${starts:+|$starts}"
verb="" ticket="" bt='`'
while IFS= read -r t; do
  pair="$(grep -oE "^[${bt} ]*(${verbs})[${bt} :]+${t}([^a-z0-9/-]|$)|${bt}(${verbs}) ${t}${bt}" <<<"$prompt" | head -n1)"
  [ -n "$pair" ] || continue
  ticket="$t" verb="$(sed -E "s/^[${bt} ]*(${verbs})[${bt} :]+.*/\\1/" <<<"$pair")"
  break
done <<<"$tickets"
if [ -z "$ticket" ] && [ "$(wc -l <<<"$tickets")" -gt 1 ]; then
  echo "[icm-router] The prompt names more than one ticket ($(paste -sd ' ' <<<"$tickets" | tr '[:lower:]' '[:upper:]')) and no command with one of them. No route. Find the ticket of the task, then run $sys/scripts/resolve-run.sh <ticket>."
  exit 0
fi
if [ -z "$ticket" ]; then
  ticket="$tickets" first="${prompt%% *}"
  if [[ "$first" =~ ^[a-z][a-z0-9-]*$ ]] && grep -qxE "build|release|revise${lanes:+|$lanes}" <<<"$first"; then
    verb="$first"
  elif [ -n "$starts" ] && grep -qE "(^|[^a-z])(${starts})([^a-z]|$)" <<<"$prompt"; then
    verb=start
  fi
fi
[ -n "$verb" ] || exit 0
lane=""
case "$verb" in
  build | release | revise) ;;
  *) if [ -n "$lanes" ] && grep -qxE "$lanes" <<<"$verb"; then lane="$verb" verb=lane; else verb=start; fi ;;
esac
[ "$(ticket_source)" != linear ] || ticket="$(tr '[:lower:]' '[:upper:]' <<<"$ticket")"

id="$(run_id "$ticket")"
if [ -d ".icm/archive/$id" ]; then
  say "the run of $ticket is closed out (.icm/archive/$id). Run $sys/scripts/resolve-run.sh $ticket: an open pull request goes on with release; a merged one means a follow-up needs a new ticket."
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
