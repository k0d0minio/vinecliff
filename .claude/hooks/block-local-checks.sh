#!/usr/bin/env bash
# block-local-checks.sh — PreToolUse(Bash) guard.
# The blueprint owns this file (1.0.0-rc18, JAM-439). A render and an update write it to
# .claude/hooks/ of the repo, and .claude/settings.json of the repo registers it. Do not
# edit it in a repo: the CI job icm-check fails on a changed copy. A correction is made in
# the blueprint and comes with the next update. The cases rc15-guard.sh and rc18-guards.sh
# of blueprint/tests/ test it.
#
# Doctrine: the deploy is the verdict for the target app. This session does NOT run its
# deterministic checks or e2e/browser tests locally unless the user explicitly asks.
#   • build                                   → the Vercel preview deploy
#   • format / lint / typecheck               → CI's advisory quality job
#   • Playwright / e2e / unit test runners    → run in CI, not ad-hoc here
# A dev server is permitted (1.0.0-rc19; J, 2026-11-21: "permit it"; the global rule since
# JAM-328): a session starts it to test a change, in the background, and stops it. This
# guard refuses no dev, start or preview server.
# ALLOWED: the ICM pipeline's own scripts (.icm/_system/scripts/*.sh and
# .icm/_system/ci/check.sh) are the factory's tooling, not
# the target app's checks — running them in-session is the point. One of them is
# .icm/_system/scripts/dev-server.sh: the agent review-shots starts the dev server with it.
# Commit and push, then read the target app's results from the PR's check runs and the
# preview deploy.
#
# Contract: reads the PreToolUse payload on stdin, inspects tool_input.command.
#   exit 0 → allow (default; also the fail-open path on any malformed/empty input).
#   exit 2 → block; stderr is surfaced to the agent as the reason.
# It only matches runner invocations at a command-segment boundary (start, ; , && , || , | ),
# strips heredoc bodies, and strips each quoted string: text inside quotes is data, not a
# command (`git commit -m "fix lint"`, `grep -E 'error|tsc'`). The quoted body of
# `bash -c`, `sh -c`, `zsh -c` and `eval` stays a command.
set -euo pipefail

# No rule "defer to a repo copy" (1.0.0-rc18): this file is the repo copy, and no global copy
# of this guard is registered.
input="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || exit 0            # no jq → can't parse → fail open
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
[ -n "$cmd" ] || exit 0

# Heredoc bodies are data, not commands — drop everything from the first heredoc marker on.
cmd="${cmd%%<<*}"
[ -n "$cmd" ] || exit 0
# The body of `bash -c '...'` and `eval "..."` is a command: it becomes its own segment.
# Then each other quoted string is data and goes.
cmd="$(printf '%s' "$cmd" | tr '\n' ';' | sed -E \
  -e "s/(^|[^[:alnum:]_])((ba|z)?sh([[:space:]]+-[a-z]+)*[[:space:]]+-[a-z]*c|eval)[[:space:]]+'([^']*)'/\\1; \\5 ;/g" \
  -e 's/(^|[^[:alnum:]_])((ba|z)?sh([[:space:]]+-[a-z]+)*[[:space:]]+-[a-z]*c|eval)[[:space:]]+"([^"]*)"/\1; \5 ;/g' \
  -e "s/'[^']*'/ /g" -e 's/"([^"\\]|\\.)*"/ /g')"
[ -n "${cmd// /}" ] || exit 0

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

# 2) Browser / e2e / unit test runners — especially Playwright: no ad-hoc testing.
printf '%s' "$cmd" | grep -Eq "${b}(${runner})?(playwright|vitest|jest|cypress|mocha)([[:space:]]|$|[;&|])" && hit="playwright / e2e / unit test runner"
printf '%s' "$cmd" | grep -Eq "${b}${pm}[[:space:]]+(run[[:space:]]+)?([a-z@/_:.-]*:)?(e2e|playwright)${sfx}([[:space:]]|$|[;&|])" && hit="playwright / e2e"
# The e2e script behind flags (`pnpm --filter <package> e2e`), and through turbo (1.0.0-rc18).
printf '%s' "$cmd" | grep -Eq "${b}${pm}[[:space:]]+([^;&|]*[[:space:]])?e2e${sfx}([[:space:]]|$|[;&|])" && hit="playwright / e2e"
printf '%s' "$cmd" | grep -Eq "${b}turbo[[:space:]]+(run[[:space:]]+)?([^;&|]*[[:space:]])?e2e${sfx}([[:space:]]|$|[;&|])" && hit="playwright / e2e"

[ -n "$hit" ] || exit 0

cat >&2 <<EOF
Blocked ($hit): the deploy is the verdict for the target app — this session does not run its
local checks or e2e/browser tests unless you are explicitly asked to. A dev server is permitted.
  • build                                → the Vercel preview deploy
  • format / lint / typecheck            → CI's advisory quality job
  • Playwright / e2e / unit tests        → run in CI, not ad-hoc here
The ICM pipeline's own scripts (.icm/_system/scripts/*.sh) are unaffected by this guard — they are
the factory's tooling, not the target app's checks.
Commit and push, then read results from the PR's check runs and the preview deploy.
If you must run one locally, ask the user to run it (or to lift this guard for that command).
EOF
exit 2
