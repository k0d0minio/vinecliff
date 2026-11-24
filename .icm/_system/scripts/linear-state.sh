#!/usr/bin/env bash
# linear-state.sh — move the Linear ticket of a pull request to the state of an event.
#
# Usage: linear-state.sh <draft|ready|merged|live> --title "<pull request title>" [--branch <head>]
#
# Only the workflows icm-linear and promote run this script, in GitHub Actions. A session
# does not run it. It is the one script that calls a ticket service. promote.sh gives the
# event live for each ticket of a release, after the promotion.
#
# The state of an event is a state name in .icm/project.json: .linear.states.<event>.
# An event with no name moves nothing. The key is in the title ("SUS-12: ..."), or in the
# last part of the branch. The API key is LINEAR_API_KEY, a secret of the repo.
#
# It moves nothing, and exits 0, when: the event has no state name, no key of this team
# is found, LINEAR_API_KEY is not set (with a notice line for GitHub Actions), the ticket is completed or canceled, or the ticket
# has the state already. It exits 1 when Linear refuses, does not answer, or has no such
# ticket or state.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
. "$here/lib/ticket.sh"
need jq curl

event="${1:-}"
[ $# -eq 0 ] || shift
title="" branch=""
while [ $# -gt 0 ]; do
  case "$1" in
    --title) title="${2:-}"; shift 2 ;;
    --branch) branch="${2:-}"; shift 2 ;;
    *) stop "unknown argument: $1" ;;
  esac
done
case "$event" in
  draft | ready | merged | live) ;;
  *) stop "the event must be draft, ready, merged or live" ;;
esac
skip() {
  echo "linear-state: $*. Nothing moved."
  exit 0
}

[ "$(ticket_source)" = linear ] || skip "this repo has no Linear tickets"
want="$(pj ".linear.states.$event")"
[ -n "$want" ] || skip "no state for '$event' in .icm/project.json"
key="$(ticket_norm "${title%%:*}")"
if [ -z "$key" ]; then
  key="$(ticket_norm "$(grep -oiE '^[a-z][a-z0-9]{0,9}-[0-9]+' <<<"${branch##*/}" || true)")"
fi
[ -n "$key" ] && ticket_valid "$key" || skip "no ticket key of this team in the title or the branch"
if [ -z "${LINEAR_API_KEY:-}" ]; then
  # A notice in GitHub Actions: the job stays green, and the run page names the missing secret.
  echo "::notice title=icm-linear::LINEAR_API_KEY is not set. $key did not move. The operator sets the repo secret LINEAR_API_KEY."
  skip "LINEAR_API_KEY is not set"
fi

# api <query> <variables as JSON>: print the data of the answer, or stop. The caller
# reads the output, thus the stop line goes to the error output.
api() {
  local out
  out="$(curl -sS --max-time 30 -H "Authorization: $LINEAR_API_KEY" \
    -H 'Content-Type: application/json' \
    --data "$(jq -n --arg q "$1" --argjson v "$2" '{query: $q, variables: $v}')" \
    "${LINEAR_API_URL:-https://api.linear.app/graphql}")" || stop "Linear did not answer" >&2
  [ "$(jq -r '(.errors // []) | length' <<<"$out" 2>/dev/null)" = 0 ] \
    || stop "Linear refused: $(jq -r '.errors[0].message // "no message"' <<<"$out" 2>/dev/null)" >&2
  jq -c .data <<<"$out"
}

issue="$(api 'query($k: String!) { issue(id: $k) { id state { name type }
  team { states(first: 50) { nodes { id name } } } } }' "$(jq -n --arg k "$key" '{k: $k}')")"
id="$(jq -r '.issue.id // empty' <<<"$issue")"
[ -n "$id" ] || stop "Linear has no ticket $key"
now="$(jq -r '.issue.state.name' <<<"$issue")"
case "$(jq -r '.issue.state.type' <<<"$issue")" in
  completed | canceled) skip "$key has the state '$now'" ;;
esac
[ "$now" != "$want" ] || skip "$key has the state '$want' already"
state="$(jq -r --arg n "$want" '.issue.team.states.nodes[] | select(.name == $n) | .id' <<<"$issue")"
[ -n "$state" ] \
  || stop "the team of $key has no state '$want'. Correct .linear.states.$event in .icm/project.json"
api 'mutation($id: String!, $s: String!) { issueUpdate(id: $id, input: {stateId: $s}) { success } }' \
  "$(jq -n --arg id "$id" --arg s "$state" '{id: $id, s: $s}')" >/dev/null
echo "linear-state: $key moved from '$now' to '$want'."
