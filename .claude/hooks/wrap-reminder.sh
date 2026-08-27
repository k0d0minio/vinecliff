#!/usr/bin/env bash
# wrap-reminder.sh — canonical estate hook (icm-board _system/template/claude/hooks/).
# Stop hook: if the session is ending with uncommitted ticket changes, block the stop
# once and say so — the board reads main, so an unpushed ticket does not exist. Honours
# stop_hook_active to never loop; silent (exit 0) in every other case.
set -uo pipefail

input="$(cat 2>/dev/null || true)"
# Already continued once because of us — let the session end.
if printf '%s' "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

repo="${CLAUDE_PROJECT_DIR:-.}"
command -v git >/dev/null 2>&1 || exit 0
git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

dirty="$(git -C "$repo" status --porcelain -- .icm 2>/dev/null || true)"
[[ -n "$dirty" ]] || exit 0

cat <<'JSON'
{"decision": "block", "reason": "Uncommitted changes under .icm/ — the tickets board reads main, so unpushed ticket work does not exist. Wrap per the estate discipline: cut what's left into .icm/intake/, then commit only .icm/ paths (message 'Plan: …' or 'Wrap: …') and push — or tell Jamie it is being left deliberately."}
JSON
exit 0
