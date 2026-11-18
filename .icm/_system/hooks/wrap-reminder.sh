#!/usr/bin/env bash
# wrap-reminder.sh — Stop hook. Blocks one stop when a run folder has changes that are not
# committed. A later session reads the run folder, not the chat. It blocks one time only.
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
[ "$(jq -r '.stop_hook_active // false' <<<"$input" 2>/dev/null)" != true ] || exit 0
root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
cd "$root" 2>/dev/null || exit 0
[ -d .icm/runs ] || exit 0
dirty="$(git status --porcelain -- .icm/runs 2>/dev/null | head -n 5)"
[ -n "$dirty" ] || exit 0
jq -n --arg files "$dirty" '{decision: "block",
  reason: ("A run folder has changes that are not committed:\n" + $files + "\nUpdate status.md and handoff.md, commit and push them. Then stop. If the run has no branch yet, say that in your stop report and stop.")}'
exit 0
