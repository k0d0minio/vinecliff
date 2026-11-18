#!/usr/bin/env bash
# guard-system.sh — PreToolUse hook. Denies a file write below .icm/_system/ in a repo.
# The folder belongs to the blueprint. The CI job icm-check is the control. This hook is
# a convenience that stops the edit early. It reads Edit, Write, MultiEdit and
# NotebookEdit. For each other tool it does nothing.
input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
case "$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null)" in
  Edit | Write | MultiEdit | NotebookEdit) ;;
  *) exit 0 ;;
esac
path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null)"
case "$path" in
  */.icm/_system/* | .icm/_system/*) ;;
  *) exit 0 ;;
esac
jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
  permissionDecisionReason: "The folder .icm/_system/ belongs to the blueprint. Do not edit it in this repo. If a file in it is wrong, tell the operator: the correction is made in the blueprint and comes with the next update."}}'
exit 0
