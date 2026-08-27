#!/usr/bin/env bash
# session-start.sh — canonical estate hook (icm-board _system/template/claude/hooks/).
# Opens every session in this repo knowing its own board: today's picks, then the open
# count. Read-only; quiet on failure — a hook must never break session start.
set -uo pipefail

intake="${CLAUDE_PROJECT_DIR:-.}/.icm/intake"
[[ -d "$intake" ]] || exit 0

open=0
today=()
for f in "$intake"/[A-Z]*-[0-9]*.md; do
  [[ -e "$f" ]] || continue
  open=$((open + 1))
  if grep -qiE '^\| *\**status\** *\| *\**today\**' "$f" 2>/dev/null; then
    title="$(head -n1 "$f" 2>/dev/null | sed 's/^# *//')"
    today+=("${title:-$(basename "$f")}")
  fi
done

(( open > 0 )) || exit 0
if (( ${#today[@]} > 0 )); then
  echo "Today:"
  for t in "${today[@]}"; do echo "  $t"; done
fi
echo "$open open ticket(s) in .icm/intake/ — planning lives there, never a loose TODO.md."
exit 0
