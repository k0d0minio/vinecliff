#!/usr/bin/env bash
# guard-plaintext-secrets.sh — PreToolUse(Write|Edit|MultiEdit|Bash) guard.
# Runs from ~/.claude/hooks/ as the machine-wide default, or from a repo's .claude/hooks/,
# registered in that repo's .claude/settings.json. When the current project ships its own
# copy, the global one defers to it.
#
# Doctrine: never store secrets, tokens, or API keys in plaintext in config or committed
# files — use environment variables — and flag any credential found. This hook enforces
# that at the moment of writing.
#
# It is deliberately narrow: an ignored .env / .env.local IS the correct home for a real
# secret, so writes there pass. Everywhere else, a credential-shaped literal is blocked with
# instructions to move it to the environment. Placeholders (your-key-here, xxx, ${VAR},
# process.env.X, <REDACTED>) are not secrets and never trip it.
#
# Contract: reads the PreToolUse payload on stdin, inspects the written text. For Bash the
# text is the whole command, heredoc body included: a `cat > file <<EOF` writes a file too,
# and auto mode prefers Bash for edits (2026-10-19). A redirect into an ignored .env passes.
#   exit 0, no output → allow (also the fail-open path on malformed input or missing jq).
#   exit 0 + permissionDecision "deny" → block, with the reason surfaced to the agent.
set -euo pipefail

# Defer to a repo-owned copy of this guard, matching block-local-checks.sh: the repo
# registers it itself, and running both would double-fire on every write.
# The same file may run as that repo copy: defer only when the repo copy is another file.
repo_copy="${CLAUDE_PROJECT_DIR:-}/.claude/hooks/guard-plaintext-secrets.sh"
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$repo_copy" ] \
  && [ "$(realpath "$repo_copy" 2>/dev/null)" != "$(realpath "$0" 2>/dev/null)" ]; then
  exit 0
fi

input="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || exit 0

path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"
# Write → .content; Edit → .new_string; MultiEdit → every edit's new_string; Bash → .command.
text="$(printf '%s' "$input" | jq -r '
  [ .tool_input.content? // empty,
    .tool_input.new_string? // empty,
    (.tool_input.edits? // [] | .[].new_string? // empty),
    .tool_input.command? // empty
  ] | join("\n")' 2>/dev/null || true)"
[ -n "$text" ] || exit 0

# A Bash command that redirects into a real .env names its file in the redirect, not in
# file_path. Take the first redirect target as the path so the same exemption applies.
if [ -z "$path" ]; then
  path="$(printf '%s' "$text" | grep -oE '>>?[[:space:]]*[^[:space:];&|<>]+' | head -1 | sed -E 's/^>>?[[:space:]]*//' || true)"
fi

# A real, git-ignored .env is where secrets belong. .env.example / .env.sample are templates
# that get committed, so they stay guarded.
base="$(basename -- "$path" 2>/dev/null || true)"
case "$base" in
  .env|.env.local|.env.*.local) exit 0 ;;
  .env.example|.env.sample|.env.template) ;;   # keep guarding
  .env.*) exit 0 ;;
esac

# Strip lines whose value is obviously a placeholder rather than a credential.
scan="$(printf '%s' "$text" | grep -vEi \
  'process\.env|import\.meta\.env|\$\{|<[A-Za-z_ -]+>|your[-_ ]|xxx+|\.\.\.|placeholder|example|redacted|changeme|dummy|fake|<redacted>' \
  || true)"
[ -n "$scan" ] || exit 0

hit=""
# Vendor-prefixed keys — the prefix plus a long body is unambiguous.
printf '%s' "$scan" | grep -Eq 'sk-ant-[A-Za-z0-9_-]{20,}'            && hit="Anthropic API key"
printf '%s' "$scan" | grep -Eq '\bsk-[A-Za-z0-9]{32,}'                && hit="OpenAI-style API key"
printf '%s' "$scan" | grep -Eq '\b(ghp|gho|ghs|ghr)_[A-Za-z0-9]{30,}' && hit="GitHub token"
printf '%s' "$scan" | grep -Eq '\bgithub_pat_[A-Za-z0-9_]{30,}'       && hit="GitHub fine-grained PAT"
printf '%s' "$scan" | grep -Eq '\bxox[baprs]-[A-Za-z0-9-]{10,}'       && hit="Slack token"
printf '%s' "$scan" | grep -Eq '\bre_[A-Za-z0-9_]{20,}'               && hit="Resend API key"
printf '%s' "$scan" | grep -Eq '\b(sbp|sb)_[a-z0-9]{30,}'             && hit="Supabase key"
printf '%s' "$scan" | grep -Eq '\bAKIA[0-9A-Z]{16}\b'                 && hit="AWS access key id"
printf '%s' "$scan" | grep -Eq '\b(vc|prj)_[A-Za-z0-9]{20,}'          && hit="Vercel token"
printf '%s' "$scan" | grep -Eq 'BEGIN [A-Z ]*PRIVATE KEY'             && hit="private key block"
# Generic assignment: SECRET/TOKEN/PASSWORD/API_KEY = a long opaque literal.
printf '%s' "$scan" | grep -Eqi '(api[_-]?key|secret|token|password|passwd|credential)["'"'"' ]*[:=][ ]*["'"'"'][A-Za-z0-9/+_-]{24,}["'"'"']' \
  && hit="hardcoded credential assignment"

[ -n "$hit" ] || exit 0

reason="Blocked — this write puts what looks like a $hit in plaintext at '${path:-the target file}'. \
Standing rule: secrets never go in config or committed files. Put the value in an ignored .env \
(or the deployment's environment) and reference it via an env var here. If this is not a real \
credential, tell the user what it is rather than working around the guard."

jq -nc --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
