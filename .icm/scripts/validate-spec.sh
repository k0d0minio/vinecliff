#!/usr/bin/env bash
# validate-spec.sh — Define's structural self-check on a run's spec.md.
#
# Define calls this before opening (or revising) the draft PR, instead of eyeballing the structure
# conversationally. It checks only the DETERMINISTIC, non-AI properties of the spec — header fields,
# required sections, acceptance criteria written as checkboxes. Whether an open question actually
# *blocks* a criterion is a judgement the agent still owns; this script surfaces open questions as an
# advisory line, it does not fail on them. Requires no network. awk/grep, plus jq to read the
# repo's persona vocabulary from .icm/project.json.
#
# This is a Define-time call, not a CI check (see issue #548, open question 1) — it runs in the
# Define stage before the gate, never as a GitHub Action.
#
# Usage:
#   .icm/scripts/validate-spec.sh <slug>            # resolves .icm/runs/<slug>/02_define/output/spec.md
#   .icm/scripts/validate-spec.sh <path-to-spec.md> # or validate a spec file directly
#
# Verdict (stdout, last line):
#   RESULT: OK        exit 0  — structure is sound; the spec is ready for the human to review.
#   RESULT: INVALID   exit 2  — one or more structural problems (listed on stderr) — fix and re-run.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "error: $*" >&2; exit 1; }

command -v jq >/dev/null || die "jq not found — needed to read the persona vocabulary from .icm/project.json"
# shellcheck source=lib/project.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/project.sh"

# --- args → spec path ------------------------------------------------------------------------------

arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --*) die "unknown flag: $1" ;;
    *)   [ -z "$arg" ] && arg="$1" || die "unexpected argument: $1"; shift ;;
  esac
done
[ -n "$arg" ] || die "usage: validate-spec.sh <slug | path-to-spec.md>"

if [ -f "$arg" ]; then
  spec="$arg"
else
  spec="$repo_root/.icm/runs/$arg/02_define/output/spec.md"
fi
[ -f "$spec" ] || die "no spec found at .icm/runs/$arg/02_define/output/spec.md (write spec.md first, or pass an explicit path)"

# --- checks ----------------------------------------------------------------------------------------

problems=()
add() { problems+=("$1"); }

# 1. Header fields present (the projection inputs for labels + the PR body).
for field in slug personas touches complexity; do
  grep -Eq "^- ${field}:[[:space:]]*[^[:space:]]" "$spec" || add "missing or empty header field: '- ${field}:'"
done

# complexity must be one of the fixed vocabulary (labels depend on it).
complexity="$(grep -m1 '^- complexity:' "$spec" | sed -E 's/^- complexity:[[:space:]]*//; s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]' || true)"
case "$complexity" in
  trivial|standard|complex) : ;;
  "") : ;;  # already reported as missing above
  *) add "complexity must be trivial|standard|complex, found: '$complexity'" ;;
esac

# personas must name at least one word of the repo's own persona vocabulary — the `personas`
# array in .icm/project.json (lib/project.sh), the same list project-labels.sh projects from.
# project-labels.sh hard-fails without a match, and by then the PR is already open; catch it
# here, before any side effect. A repo that declares no vocabulary projects no persona labels
# and is not wrong, so the check is skipped for it.
personas_raw="$(grep -m1 '^- personas:' "$spec" | sed -E 's/^- personas:[[:space:]]*//; s/[[:space:]]*$//' || true)"
persona_vocab="$(project_list '.personas')"
if [ -n "$personas_raw" ] && [ -n "$persona_vocab" ]; then
  persona_hit=0
  for vocab in $persona_vocab; do
    printf '%s' "$personas_raw" | grep -iqwE "$vocab" && persona_hit=1
  done
  [ "$persona_hit" -eq 1 ] || add "personas must name at least one of the repo's vocabulary (personas in .icm/project.json): $(printf '%s' "$persona_vocab" | paste -sd', ' -) — found: '$personas_raw'"
fi

# 2. Required sections present.
for section in "Problem" "Proposed change" "Acceptance criteria" "Out of scope" "Open questions"; do
  grep -Eq "^##[[:space:]]+${section}[[:space:]]*$" "$spec" || add "missing required section: '## ${section}'"
done

# 3. Acceptance criteria are checkboxes — at least one, and every bullet in the section is a checkbox.
#    awk extracts the body of the '## Acceptance criteria' section (up to the next '## ' heading).
ac_section="$(awk '
  /^##[[:space:]]+Acceptance criteria[[:space:]]*$/ { grab=1; next }
  grab && /^##[[:space:]]/ { grab=0 }
  grab { print }
' "$spec")"

ac_checkboxes="$(printf '%s\n' "$ac_section" | grep -Ec '^[[:space:]]*-[[:space:]]+\[[ xX]\]' || true)"
ac_plain_bullets="$(printf '%s\n' "$ac_section" | grep -E '^[[:space:]]*-[[:space:]]' | grep -Evc '^[[:space:]]*-[[:space:]]+\[[ xX]\]' || true)"

if grep -Eq "^##[[:space:]]+Acceptance criteria[[:space:]]*$" "$spec"; then
  [ "$ac_checkboxes" -ge 1 ] || add "## Acceptance criteria has no checkbox items (use '- [ ] <outcome>')"
  [ "$ac_plain_bullets" -eq 0 ] || add "## Acceptance criteria has $ac_plain_bullets non-checkbox bullet(s) — every criterion must be a '- [ ]' checkbox"
fi

# --- advisory (not a failure): open questions ------------------------------------------------------
# The spec template says Open questions must be "none" or only non-blocking notes. Whether an entry
# blocks a criterion is the agent's call — we only flag that entries exist so it gets a second look.
oq_section="$(awk '
  /^##[[:space:]]+Open questions[[:space:]]*$/ { grab=1; next }
  grab && /^##[[:space:]]/ { grab=0 }
  grab { print }
' "$spec")"
oq_entries="$(printf '%s\n' "$oq_section" | grep -E '^[[:space:]]*-[[:space:]]' | grep -Eiv '^[[:space:]]*-[[:space:]]+none[[:space:].]*$' || true)"

# --- verdict ---------------------------------------------------------------------------------------

if [ -n "$oq_entries" ]; then
  echo "advisory: ## Open questions has entries — confirm none of them block an acceptance criterion (Define gate). Move anything you won't do this run to ## Out of scope." >&2
fi

if [ "${#problems[@]}" -eq 0 ]; then
  echo "spec ok: $spec"
  echo "RESULT: OK"
  exit 0
fi

echo "spec invalid: $spec" >&2
for p in "${problems[@]}"; do echo "  ✗ $p" >&2; done
echo "RESULT: INVALID"
exit 2
