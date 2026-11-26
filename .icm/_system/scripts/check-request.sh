#!/usr/bin/env bash
# check-request.sh — check the form of client requests (.icm/_system/features/requests.md).
#
# Usage: check-request.sh <file>...   files .icm/requests/REQ-<slug>-<n>.md
#        check-request.sh -           a Linear request: its description on stdin
#
# Each fault is one line "fault: <file or linear>: <name>". The names: no-client-words,
# empty-client-words, no-acceptance-criteria, no-ac-line, bad-ac-line, template-text,
# duplicate-ac, bad-id, bad-source, bad-date, bad-status.
# Last line: "RESULT: OK" or "RESULT: STOP <count> fault(s)".
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
help_if_asked "$@"
[ $# -gt 0 ] || stop "usage: check-request.sh <file>... | -"

form='^AC-[0-9]+: WHEN [^ ].* (WHILE [^ ].* )?THE [^ ].* SHALL [^ ].*[^ ]$'
faults=0
fault() {
  echo "fault: $1: $2"
  faults=$((faults + 1))
}
# section <heading> <text>: the lines below "## <heading>", to the next "## ".
section() { awk -v h="## $1" '$0 == h { f = 1; next } f && /^## / { exit } f' <<<"$2"; }
# meta <name> <text>: "=<value>" of "<name>: <value>" in the front matter, or of
# "- <name>: <value>" above the first "## ". Nothing when the field is absent.
meta() {
  awk -v k="$1" 'NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    /^## / { exit }
    { l = $0; if (!fm) { if (l !~ /^- /) next; sub(/^- /, "", l) }
      if (l == k ":" || index(l, k ": ") == 1) { sub(/^[^:]*: ?/, "", l); print "=" l; exit } }' <<<"$2"
}

check() {  # check <name> <text> <id expected from the file name, or nothing>
  local where="$1" text="$2" id="$3" ac line v
  if ! grep -qxF '## Client words' <<<"$text"; then
    fault "$where" no-client-words
  elif ! section 'Client words' "$text" | grep -q '[[:alnum:]]'; then
    fault "$where" empty-client-words
  fi
  if ! grep -qxF '## Acceptance criteria' <<<"$text"; then
    fault "$where" no-acceptance-criteria
  else
    ac="$(section 'Acceptance criteria' "$text" | grep -v '^[[:space:]]*$' | grep -v '^<!--' || true)"
    [ -n "$ac" ] || fault "$where" no-ac-line
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      if ! grep -qE "$form" <<<"$line"; then
        fault "$where" "bad-ac-line: $line"
      elif grep -qE '<[a-z][^>]*>' <<<"$line"; then
        fault "$where" "template-text: $line"
      fi
    done <<<"$ac"
    v="$(grep -oE '^AC-[0-9]+:' <<<"$ac" | sort | uniq -d | tr '\n' ' ')"
    [ -z "$v" ] || fault "$where" "duplicate-ac: $v"
  fi
  if [ -n "$id" ]; then
    v="$(meta id "$text")"
    [ "$v" = "=$id" ] && [[ "$id" =~ ^REQ-[a-z0-9-]+-[0-9]+$ ]] || fault "$where" "bad-id: the field id must be $id"
    v="$(meta date "$text")"
    [[ "$v" =~ ^=[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fault "$where" "bad-date: ${v#=}"
  fi
  v="$(meta source "$text")"
  [[ "$v" =~ ^=(button|mail|meeting|call)$ ]] || fault "$where" "bad-source: ${v#=} (button, mail, meeting or call)"
  v="$(meta status "$text")"
  [[ "$v" =~ ^=(received|specified|built|verified|accepted)$ ]] \
    || fault "$where" "bad-status: ${v#=} (received, specified, built, verified or accepted)"
}

for arg in "$@"; do
  if [ "$arg" = - ]; then
    check linear "$(cat)" ""
  elif [ -f "$arg" ]; then
    check "$arg" "$(cat "$arg")" "$(basename "$arg" .md)"
  else
    fault "$arg" "no such file"
  fi
done
[ "$faults" -eq 0 ] || stop "$faults fault(s)"
echo "RESULT: OK"
