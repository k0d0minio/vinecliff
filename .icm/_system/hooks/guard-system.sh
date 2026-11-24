#!/usr/bin/env bash
# guard-system.sh — PreToolUse hook. It denies two things in a repo:
# 1. Each MCP tool call that is not on the allowlist: a tool name that starts with mcp__,
#    also in a subagent. Rule 9 of the router: a session uses the tools of BAXTER
#    (baxter_tool), git and gh (J, 2026-11-20). The allowlist (1.0.0-rc23, JAM-563):
#    - the typed server of BAXTER: mcp__baxter__<noun>_<verb> (1.0.0-rc21, J, 2026-11-24);
#    - four servers of the Claude desktop app: ccd_turn (the task list, the wrap-up),
#      ccd_session (start a session), ccd_pr (bind a pull request), ccd_view (a pane). The
#      one tool mcp__ccd_pr__set_auto_merge stays refused: the gate Ready to merge is the
#      operator's.
#    The guard refuses each other server, also of the app: ccd_connectors (it can enable a
#    connector), ccd_settings, ccd_session_mgmt, ccd_directory (a different folder has no
#    guard of this repo), ccd_host (it can delete a worktree), Claude_Browser and
#    claude-in-chrome (a site with the operator's sign-ins), terminal (a command with no
#    Bash guard). It is an allowlist: a connector of claude.ai has a UUID as its server
#    name, and a deny list cannot name it before it is connected. The name must match all:
#    a second "__" after the server name is of another server. This part needs no jq: it
#    uses the regex of bash.
# 2. A file write below .icm/_system/, or of one of the three guards of .claude/hooks/
#    (1.0.0-rc18). They belong to the blueprint. The CI job icm-check is the control. This
#    part is a convenience that stops the edit early. It reads Edit, Write, MultiEdit and
#    NotebookEdit, and it needs jq.
# For each other tool it does nothing.
input="$(cat)"
mcp_reason="Do not use an MCP tool but the server baxter (mcp__baxter__*) and the app servers ccd_turn, ccd_session, ccd_pr and ccd_view. Use the tools of BAXTER: mcp__baxter__tool_list, or ~/baxter_live/system/bin/baxter_tool list, then baxter_tool schema <tool>. For git and GitHub, use git and gh. If no BAXTER tool does the work, stop and tell the operator. Rule 9 and the section On this computer of .icm/_system/ROUTER.md."
# The first "tool_name" is the name of the call: Claude Code writes it before tool_input. A
# key "tool_name" in the arguments of a call comes after it.
name_re='"tool_name"[[:space:]]*:[[:space:]]*"([^"]*)"'
tool=""
[[ $input =~ $name_re ]] && tool="${BASH_REMATCH[1]}"
allow_re='^mcp__(baxter|ccd_turn|ccd_session|ccd_pr|ccd_view)__[a-z0-9]+(_[a-z0-9]+)*$'
if [[ $tool == mcp__* && ( ! $tool =~ $allow_re || $tool == mcp__ccd_pr__set_auto_merge ) ]]; then
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
