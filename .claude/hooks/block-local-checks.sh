#!/usr/bin/env bash
# block-local-checks.sh — PreToolUse(Bash) guard.
# Runs from ~/.claude/hooks/ as the machine-wide default, or from a repo's .claude/hooks/,
# registered in that repo's .claude/settings.json (so cloud/web sessions without ~/.claude
# are guarded too). When the current project ships its own copy, the global one defers to
# it — the repo's version is authoritative and nothing fires twice.
#
# Doctrine: the deploy is the verdict for the target app. This session does NOT run its
# deterministic checks, dev/preview servers, or e2e/browser tests locally unless the user
# explicitly asks.
#   • build                                   → the Vercel preview deploy
#   • format / lint / typecheck               → CI's advisory quality job
#   • dev / start / preview servers           → hang the session; not the agent's job
#   • Playwright / e2e / unit test runners    → run in CI, not ad-hoc here
# ALLOWED: the ICM pipeline's own scripts (.icm/scripts/*.sh — format.sh, lint.sh,
# validate-*.sh, project-labels.sh, setup.sh, and the rest) are the factory's tooling, not
# the target app's checks — running them in-session is the point.
# Commit and push, then read the target app's results from the PR's check runs and the
# preview deploy.
#
# Contract: reads the PreToolUse payload on stdin, inspects tool_input.command.
#   exit 0 → allow (default; also the fail-open path on any malformed/empty input).
#   exit 2 → block; stderr is surfaced to the agent as the reason.
# It only matches runner invocations at a command-segment boundary (start, ; , && , || , | ),
# and strips heredoc bodies, so a blocked word inside a quoted string — e.g.
# `git commit -m "fix lint"` or `git commit -m "add dev server"` — is never caught.
set -euo pipefail

# Defer to a repo-owned copy of this guard: the repo defines its own semantics and
# registers the hook itself — running both would double-fire on every Bash call.
# The same file may run as that repo copy: defer only when the repo copy is another file.
repo_copy="${CLAUDE_PROJECT_DIR:-}/.claude/hooks/block-local-checks.sh"
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$repo_copy" ] \
  && [ "$(realpath "$repo_copy" 2>/dev/null)" != "$(realpath "$0" 2>/dev/null)" ]; then
  exit 0
fi

input="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || exit 0            # no jq → can't parse → fail open
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
[ -n "$cmd" ] || exit 0

# Heredoc bodies are data, not commands — drop everything from the first heredoc marker on.
cmd="${cmd%%<<*}"
[ -n "$cmd" ] || exit 0

b='(^|[;&|])[[:space:]]*'                                   # command-segment boundary
runner='(npx|bunx|pnpm[[:space:]]+(exec|dlx)|yarn([[:space:]]+exec)?)[[:space:]]+'
pm='(pnpm|npm|yarn|bun)'

hit=""

# 1) Deterministic checks: build / lint / typecheck / test — script + turbo forms.
# `sfx` absorbs colon-qualified script names (lint:fix, test:watch, build:prod). Without it
# the verb had to end at a whitespace/boundary, so every `pnpm run <verb>:<sub>` — the most
# common script convention there is — walked straight past this guard.
sfx='(:[a-z0-9][a-z0-9_-]*)*'
verb="(build|lint|typecheck|test)${sfx}([[:space:]]|\$|[;&|])"
printf '%s' "$cmd" | grep -Eq "${b}${pm}[[:space:]]+(run[[:space:]]+)?([^;&|]*[[:space:]])?[a-z@/_:.-]*${verb}" && hit="build/lint/typecheck/test"
printf '%s' "$cmd" | grep -Eq "${b}turbo[[:space:]]+(run[[:space:]]+)?${verb}" && hit="turbo build/lint/typecheck/test"
# format (format, format:check, format:staged, …)
printf '%s' "$cmd" | grep -Eq "${b}${pm}[[:space:]]+(run[[:space:]]+)?([^;&|]*[[:space:]])?format" && hit="format"
# direct binaries the scripts wrap
printf '%s' "$cmd" | grep -Eq "${b}(${runner})?(tsc|next[[:space:]]+build|prettier|eslint)([[:space:]]|$|[;&|])" && hit="tsc / next build / prettier / eslint"

# 2) Dev / preview / production servers — they block the session and are the factory's job.
printf '%s' "$cmd" | grep -Eq "${b}${pm}[[:space:]]+(run[[:space:]]+)?([a-z@/_:.-]*:)?(dev|start|preview|serve)${sfx}([[:space:]]|$|[;&|])" && hit="dev/start server"
printf '%s' "$cmd" | grep -Eq "${b}turbo[[:space:]]+(run[[:space:]]+)?(dev|start|preview)${sfx}" && hit="dev/start server"
printf '%s' "$cmd" | grep -Eq "${b}(${runner})?(next[[:space:]]+(dev|start)|vite([[:space:]]+(dev|preview))?|nodemon|serve)([[:space:]]|$|[;&|])" && hit="dev/start server"

# 3) Browser / e2e / unit test runners — especially Playwright: no ad-hoc testing.
printf '%s' "$cmd" | grep -Eq "${b}(${runner})?(playwright|vitest|jest|cypress|mocha)([[:space:]]|$|[;&|])" && hit="playwright / e2e / unit test runner"
printf '%s' "$cmd" | grep -Eq "${b}${pm}[[:space:]]+(run[[:space:]]+)?([a-z@/_:.-]*:)?(e2e|playwright)${sfx}([[:space:]]|$|[;&|])" && hit="playwright / e2e"

[ -n "$hit" ] || exit 0

cat >&2 <<EOF
Blocked ($hit): the deploy is the verdict for the target app — this session does not run its
local checks, dev/preview servers, or e2e/browser tests unless you are explicitly asked to.
  • build                                → the Vercel preview deploy
  • format / lint / typecheck            → CI's advisory quality job
  • dev / start / preview servers        → they hang the session; not the agent's job
  • Playwright / e2e / unit tests        → run in CI, not ad-hoc here
The ICM pipeline's own scripts (.icm/scripts/*.sh) are unaffected by this guard — they are
the factory's tooling, not the target app's checks.
Commit and push, then read results from the PR's check runs and the preview deploy.
If you must run one locally, ask the user to run it (or to lift this guard for that command).
EOF
exit 2
