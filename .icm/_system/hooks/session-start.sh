#!/usr/bin/env bash
# session-start.sh — SessionStart hook. Prints the live runs of this checkout and the open
# intake count. It prints 14 lines at most. It reads files only and never fails a session.
root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
cd "$root" 2>/dev/null || exit 0
[ -d .icm/_system ] || exit 0
here=".icm/_system/scripts/lib"
. "$here/project.sh" 2>/dev/null || exit 0

echo "[icm] blueprint $(cat .icm/_system/VERSION 2>/dev/null). Router: .icm/_system/ROUTER.md"
count=0
for run in .icm/runs/*/run.md; do
  [ -f "$run" ] || continue
  count=$((count + 1))
  [ "$count" -le 10 ] || continue
  dir="$(dirname "$run")"
  blocked="$(field blocked "$dir/status.md")"
  line="[icm] run $(basename "$dir"): phase $(field phase "$dir/status.md"), pr $(field pr "$run"), branch $(field branch "$run")"
  case "$blocked" in "" | no) ;; *) line="$line, BLOCKED: $blocked" ;; esac
  echo "$line"
done
[ "$count" -le 10 ] || echo "[icm] and $((count - 10)) more runs in .icm/runs/"
[ "$count" -gt 0 ] || echo "[icm] no live run on this branch. A run on another branch is not listed."

if [ "$(ticket_source)" = linear ]; then
  open="$(find .icm/intake/tickets -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
  echo "[icm] intake: $open ticket(s) in work. The queue is in Linear."
else
  open="$(find .icm/intake -name '*.md' ! -name breakdown.md ! -name README.md ! -path '*/_done/*' 2>/dev/null | wc -l)"
  triage="$(find .icm/intake/triage -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
  echo "[icm] intake: $open open stub(s), $triage in triage."
fi
exit 0
