#!/usr/bin/env bash
# lib/project.sh — read .icm/project.json, and small helpers. Sourced, not run.
#
#   icm_root            the top folder of the repo
#   pj <jq path> [def]  one value of .icm/project.json, or the default
#   ticket_source       linear | markdown
#   team_key            the Linear team key, or nothing
#   default_branch      the default branch (main when not set)
#   field <name> <file> the value of the line "- <name>: <value>" in a run file
#   render <template>   print the template with each @NAME@ replaced by the variable NAME
#   stop <reason>       print "RESULT: STOP <reason>" and exit 1
#   need <tool>...      stop when a tool is not installed
#   help_if_asked "$@"  on -h or --help: print the header of the script and exit 0

# In bash 5.2 an "&" in a replacement means "the match". Titles can contain "&".
shopt -u patsub_replacement 2>/dev/null || true

icm_root() { git rev-parse --show-toplevel; }

pj() {
  local v
  v="$(jq -r "$1 // empty" "$(icm_root)/.icm/project.json" 2>/dev/null || true)"
  printf '%s' "${v:-${2:-}}"
}

ticket_source() { pj .ticket_source markdown; }
team_key() { pj .linear.team_key; }
default_branch() { pj .default_branch main; }

field() { sed -n "s/^- $1: *//p" "$2" 2>/dev/null | head -n1; }

render() {
  local text name
  text="$(cat "$1")"
  for name in ID TICKET TITLE URL BRANCH LANE PR DATE PHASE SUMMARY CRITERIA QUESTIONS; do
    text="${text//@${name}@/${!name:-}}"
  done
  printf '%s\n' "$text"
}

stop() {
  echo "RESULT: STOP $*"
  exit 1
}

need() {
  local t
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || stop "$t is not installed"
  done
}

help_if_asked() {
  local a
  for a in "$@"; do
    case "$a" in -h | --help) sed -n '2,/^set -/{/^#/s/^# \{0,1\}//p}' "$0"; exit 0 ;; esac
  done
}
