#!/usr/bin/env bash
# validate-spec.sh — check the shape of the spec of one run. It does not judge the content.
#
# Usage: validate-spec.sh <ticket | run id>
#
# It checks .icm/runs/<id>/spec.md: the title line, the ticket field, the four sections,
# one or more acceptance criteria, who verifies each criterion, and no text left from the
# template. Since 1.0.0-rc27: the field requests, and each AC line of each request file
# that it cites, kept as it is (features/requests.md).
# Last line: "RESULT: OK" or "RESULT: STOP <count> fault(s)". Each fault is one line above.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
. "$here/lib/ticket.sh"

[ $# -eq 1 ] || stop "usage: validate-spec.sh <ticket>"
need git jq
cd "$(icm_root)"
id="$(run_id "$1")"
[ -n "$id" ] || stop "$1 is not a ticket of this repo"
spec=".icm/runs/$id/spec.md"
[ -f "$spec" ] || stop "no spec at $spec"

faults=0
fault() {
  echo "fault: $*"
  faults=$((faults + 1))
}

grep -qE '^# Spec: .+' "$spec" || fault "the first heading must be '# Spec: <title>'"
for heading in "Problem" "Proposed change" "Acceptance criteria" "Out of scope"; do
  grep -qxF "## $heading" "$spec" || fault "the section '## $heading' is missing"
done
criteria="$(awk '/^## Acceptance criteria/ { f = 1; next } f && /^## / { f = 0 } f && /^- \[ \] ./' "$spec" | wc -l)"
[ "$criteria" -gt 0 ] || fault "the spec has no acceptance criterion ('- [ ] ...')"
bare="$(awk '/^## Acceptance criteria/ { f = 1; next } f && /^## / { f = 0 } f && /^- \[ \] ./ && !/ \(verify: (CI|agent|operator)\)$/' "$spec" | wc -l)"
[ "$bare" -eq 0 ] || fault "$bare acceptance criterion(s) do not end with '(verify: CI)', '(verify: agent)' or '(verify: operator)'"

named="$(field ticket "$spec")"
if [ -z "$named" ]; then
  fault "the line '- ticket:' is missing or empty"
elif [ "$(run_id "$named")" != "$id" ]; then
  fault "the ticket field says '$named', and the run folder is '$id'"
fi
requests="$(field requests "$spec")"
if [ -z "$requests" ]; then
  fault "the line '- requests:' is missing or empty: the ids of the client requests, or none"
elif [ "$requests" != none ]; then
  for r in ${requests//,/ }; do
    if [[ "$r" =~ ^REQ-[a-z0-9-]+-[0-9]+$ ]]; then
      f=".icm/requests/$r.md"
      [ -f "$f" ] || { fault "the request $r is not in .icm/requests/"; continue; }
      while IFS= read -r ac; do
        grep -qF -- "- [ ] $r#$ac" "$spec" || fault "the spec does not keep ${ac%%:*} of $r as it is: '- [ ] $r#$ac'"
      done < <(awk '/^## Acceptance criteria/ { f = 1; next } f && /^## / { exit } f && /^AC-[0-9]+: /' "$f")
    elif [[ "$r" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; then
      grep -qE "^- \[ \] $r#AC-[0-9]+: WHEN " "$spec" || fault "the spec has no AC line of $r: '- [ ] $r#AC-<n>: WHEN ...'"
    else
      fault "'$r' in requests is not a REQ id or a Linear key"
    fi
  done
fi
if grep -nE '<[A-Z][^>]*\.>|<the ticket|<the paths|<the ids' "$spec" >/dev/null; then
  fault "text from the template is left in the spec (a line with '<...>')"
fi

[ "$faults" -eq 0 ] || stop "$faults fault(s) in $spec"
echo "RESULT: OK"
