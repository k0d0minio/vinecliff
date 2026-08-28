#!/usr/bin/env bash
# session-start.sh — canonical estate hook (icm-board _system/template/claude/hooks/).
# Opens every session in this repo knowing its own board: open stubs per epic (with the
# next in sequence), the triage backlog, and any legacy flat tickets still unmigrated.
# Read-only; quiet on failure — a hook must never break session start.
set -uo pipefail

intake="${CLAUDE_PROJECT_DIR:-.}/.icm/intake"
[[ -d "$intake" ]] || exit 0

open=0; legacy=0; triage=0
lines=()

# Epics: every directory except triage/ and _done/.
for epic in "$intake"/*/; do
  [[ -d "$epic" ]] || continue
  name="$(basename "$epic")"
  [[ "$name" == "triage" || "$name" == "_done" ]] && continue
  n=0; next=""; next_seq=999999
  for f in "$epic"*.md; do
    [[ -e "$f" ]] || continue
    [[ "$(basename "$f")" == "breakdown.md" ]] && continue
    n=$((n + 1))
    seq="$(grep -m1 -E '^- *sequence:' "$f" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
    [[ -n "$seq" ]] || seq=999998
    if (( seq < next_seq )); then next_seq=$seq; next="$(basename "$f" .md)"; fi
  done
  (( n > 0 )) || continue
  open=$((open + n))
  lines+=("  $name: $n open — next: ${next:-?}")
done

# Triage backlog.
if [[ -d "$intake/triage" ]]; then
  for f in "$intake/triage"/*.md; do
    [[ -e "$f" ]] || continue
    triage=$((triage + 1))
  done
fi
open=$((open + triage))

# Legacy flat tickets (pre-2026-08-28 shape) — still open, awaiting a /project re-cut.
for f in "$intake"/[A-Z]*-[0-9]*.md; do
  [[ -e "$f" ]] || continue
  legacy=$((legacy + 1))
done
open=$((open + legacy))

(( open > 0 )) || exit 0
(( ${#lines[@]} > 0 )) && printf '%s\n' "${lines[@]}"
(( triage > 0 )) && echo "  triage: $triage parked"
(( legacy > 0 )) && echo "  legacy: $legacy unmigrated flat ticket(s)"
echo "$open open stub(s) in .icm/intake/ — planning lives there, never a loose TODO.md."
exit 0
