#!/usr/bin/env bash
# guard-system.sh — PreToolUse hook. It denies two things in a repo:
# 1. Each MCP tool call: a tool name that starts with mcp__, also in a subagent. Rule 9 of
#    the router: a session uses the tools of BAXTER (baxter_tool), git and gh (J, 2026-11-20).
#    The one exception is the typed server of BAXTER: mcp__baxter__<noun>_<verb> (1.0.0-rc21,
#    J, 2026-11-24). A name with a second "__" after mcp__baxter__ is of another server, and
#    the guard denies it. This part needs no jq: it uses the regex of bash.
# 2. A file write below .icm/_system/, or of one of the three guards of .claude/hooks/
#    (1.0.0-rc18). They belong to the blueprint. The CI job icm-check is the control. This
#    part is a convenience that stops the edit early. It reads Edit, Write, MultiEdit and
#    NotebookEdit, and it needs jq.
# For each other tool it does nothing.
input="$(cat)"
mcp_reason="Do not use an MCP tool but the server baxter (mcp__baxter__*). Use the tools of BAXTER: mcp__baxter__tool_list, or ~/baxter_live/system/bin/baxter_tool list, then baxter_tool schema <tool>. For git and GitHub, use git and gh. If no BAXTER tool does the work, stop and tell the operator. Rule 9 and the section On this computer of .icm/_system/ROUTER.md."
# The first "tool_name" is the name of the call: Claude Code writes it before tool_input. A
# key "tool_name" in the arguments of a call comes after it.
name_re='"tool_name"[[:space:]]*:[[:space:]]*"([^"]*)"'
tool=""
[[ $input =~ $name_re ]] && tool="${BASH_REMATCH[1]}"
baxter_re='^mcp__baxter__[a-z0-9]+(_[a-z0-9]+)*$'
if [[ $tool == mcp__* && ! $tool =~ $baxter_re ]]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$mcp_reason"
  exit 0
fi
command -v jq >/dev/null 2>&1 || exit 0
case "$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null)" in
  Edit | Write | MultiEdit | NotebookEdit) ;;
  *) exit 0 ;;
esac
path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null)"
case "$path" in
  */.icm/_system/* | .icm/_system/*) ;;
  */.claude/hooks/block-local-checks.sh | .claude/hooks/block-local-checks.sh) ;;
  */.claude/hooks/confirm-git-writes.sh | .claude/hooks/confirm-git-writes.sh) ;;
  */.claude/hooks/guard-plaintext-secrets.sh | .claude/hooks/guard-plaintext-secrets.sh) ;;
  *) exit 0 ;;
esac
jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
  permissionDecisionReason: "The folder .icm/_system/ and the three guards of .claude/hooks/ (block-local-checks.sh, confirm-git-writes.sh, guard-plaintext-secrets.sh) belong to the blueprint. Do not edit them in this repo. If a file is wrong, tell the operator: the correction is made in the blueprint and comes with the next update."}}'
exit 0
