#!/usr/bin/env bash
# lib/ticket.sh — the ticket, in its forms. Sourced, not run. Needs lib/project.sh.
#
# A Linear ticket is a key (SUS-123). A markdown ticket is a stub path (<epic>/<slug>).
# The scripts never call a ticket service. The session reads the ticket and gives the
# values as flags. The one exception is linear-state.sh, which only CI runs.
#
#   ticket_norm <key>          SUS-123. Nothing for a value that is not a key
#   ticket_slug <key>          sus-123. Nothing for a value that is not a key
#   stub_ref <arg>             <epic>/<slug>, from a path with or without .icm/intake/ and .md
#   run_id <ticket|id>         the run folder name: sus-123, or the stub slug
#   ticket_valid <ticket>      0 when the key is on this repo's team, or the stub exists
#   pr_title_for <t> <title>   "SUS-123: <title>" for Linear. The title alone for markdown
#   write_stub <id>            Linear only: write .icm/intake/tickets/<KEY>.md from run.md

_key_re='^[A-Za-z][A-Za-z0-9]{0,9}-[0-9]+$'

ticket_norm() {
  [[ "${1:-}" =~ $_key_re ]] || return 0
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

ticket_slug() {
  [[ "${1:-}" =~ $_key_re ]] || return 0
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

stub_ref() {
  local r="${1:-}"
  r="${r%.md}"
  r="${r#./}"
  printf '%s' "${r#.icm/intake/}"
}

run_id() {
  local r
  if [ "$(ticket_source)" = linear ]; then
    ticket_slug "${1:-}"
  else
    r="$(stub_ref "${1:-}")"
    printf '%s' "${r##*/}"
  fi
}

ticket_valid() {
  local id key
  if [ "$(ticket_source)" = linear ]; then
    id="$(ticket_norm "${1:-}")"
    [ -n "$id" ] || return 1
    key="$(team_key | tr '[:lower:]' '[:upper:]')"
    [ -z "$key" ] || [ "${id%-*}" = "$key" ]
  else
    case "$(stub_ref "${1:-}")" in
      */*/* | _done/* | */_done) return 1 ;;
      */*) [ -f "$(icm_root)/.icm/intake/$(stub_ref "$1").md" ] ;;
      *) return 1 ;;
    esac
  fi
}

pr_title_for() {
  local id title="${2:-}"
  if [ "$(ticket_source)" = linear ]; then
    id="$(ticket_norm "${1:-}")"
    printf '%s: %s' "$id" "${title#"$id: "}"
  else
    printf '%s' "$title"
  fi
}

# Prints the stub path and "written" or "exists". Reads the values from run.md.
write_stub() {
  local run=".icm/runs/$1/run.md" out
  ID="$1"
  TICKET="$(field ticket "$run")"
  TITLE="$(field title "$run")"
  URL="$(field link "$run")"
  BRANCH="$(field branch "$run")"
  LANE="$(field lane "$run")"
  DATE="$(date +%F)"
  out=".icm/intake/tickets/${TICKET}.md"
  if [ -e "$out" ] || [ -e ".icm/intake/_done/${TICKET}.md" ]; then
    echo "stub: $out (exists)"
    return 0
  fi
  mkdir -p .icm/intake/tickets
  render .icm/_system/templates/stub.md > "$out"
  echo "stub: $out (written)"
}
