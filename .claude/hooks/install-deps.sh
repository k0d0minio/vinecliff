#!/usr/bin/env bash
# install-deps.sh — canonical estate hook (icm-board _system/template/claude/hooks/). A second
# SessionStart hook that makes Husky's pre-commit formatting exist in every session.
#
# Promoted from sustentus (#1116, 2026-09-17) by decision D44. A repo that formats on commit does
# it through Husky (lint-staged → prettier), and Husky is a git hook that only exists after the
# install has run the root `prepare` script. A Claude Code cloud session starts from a fresh clone
# with no node_modules, so nothing formats on commit and the first thing CI says about a
# markdown-only PR is "unformatted". This hook closes the hole by installing dependencies when they
# are missing or stale, in the background, so the first prompt is never delayed.
#
# It is its own hook, not a step of session-start.sh, because it runs async: once a hook announces
# `{"async": true}` the harness runs the rest in the background and nothing it prints reaches the
# session as context — which is exactly what session-start.sh's board must do.
#
# What it does, in order:
#   0. Applies only where the repo's root package.json has a `prepare` script naming husky.
#      Anywhere else — no package.json, no Husky — it exits 0 silently: the hook is canonical in
#      every repo and inert where there is nothing to install for. /setup suggests Husky where a
#      repo formats with prettier but lacks it (.claude/skills/setup/SKILL.md).
#   1. Decides whether an install is owed, by the lockfile the repo carries: pnpm-lock.yaml
#      against node_modules/.modules.yaml (pnpm's install record), package-lock.json against
#      node_modules/.package-lock.json (npm's). A missing record or a newer lockfile owes one; a
#      fresh node_modules → exit 0 in milliseconds. No lockfile → exit 0.
#   2. If HUSKY=0 is exported, says so on one line and still installs — `husky` honours that
#      variable by skipping the hook install silently, and the operator must see that formatting
#      is off, not discover it from a red check.
#   3. Announces async mode to the harness, then runs `pnpm install --frozen-lockfile` or `npm ci`
#      — no --ignore-scripts, because the `prepare` script is the point. Everything it prints goes
#      to a log in the session's scratch directory; the last lines record whether
#      `core.hooksPath` ended up pointing at .husky/_.
#
# Contract:
#   exit 0 always — this hook NEVER fails the session, whatever the install does. Fail-open on
#   malformed or empty stdin (the log then lands under ${TMPDIR:-/tmp} instead of the session
#   scratch dir). stdout: nothing on the fast path; one line when HUSKY=0 is set or the package
#   manager is missing; the async announcement plus a one-line pointer to the log when an install
#   starts.
#   Not a repo check (block-local-checks.sh does not match it) — it may be run by hand:
#     echo '{"session_id":"x","cwd":"'"$PWD"'"}' | .claude/hooks/install-deps.sh
set -euo pipefail

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# 0. Husky repos only.
[ -f "$root/package.json" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
jq -e '(.scripts.prepare // "") | test("husky")' "$root/package.json" >/dev/null 2>&1 || exit 0

# 1. Which package manager, and is an install owed? `-nt` is "newer than" by mtime; a missing record
#    file makes the lockfile newer by definition, which covers the no-node_modules clone as well.
if [ -f "$root/pnpm-lock.yaml" ]; then
  pm=pnpm; lock="$root/pnpm-lock.yaml"; record="$root/node_modules/.modules.yaml"
  install=(pnpm install --frozen-lockfile)
elif [ -f "$root/package-lock.json" ]; then
  pm=npm; lock="$root/package-lock.json"; record="$root/node_modules/.package-lock.json"
  install=(npm ci)
else
  exit 0
fi
if [ -f "$record" ] && ! [ "$lock" -nt "$record" ]; then
  exit 0
fi

# Where the log goes: the session's scratch directory, derived the way the harness names it
# (/tmp/claude-<uid>/<cwd with / → ->/<session_id>/scratchpad). Falls back to ${TMPDIR:-/tmp}.
input="$(cat 2>/dev/null || true)"
session_id=""
cwd=""
if [ -n "$input" ]; then
  session_id="$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null || true)"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null || true)"
fi
cwd="${cwd:-$root}"
log_dir="${TMPDIR:-/tmp}"
if [ -n "$session_id" ]; then
  candidate="/tmp/claude-$(id -u)/$(printf '%s' "$cwd" | tr '/' '-')/$session_id/scratchpad"
  if mkdir -p "$candidate" 2>/dev/null; then log_dir="$candidate"; fi
fi
log="$log_dir/install-deps-$pm.log"

# 2. HUSKY=0 makes `husky` skip the hook install with exit 0 — never silently.
if [ "${HUSKY-}" = "0" ]; then
  echo "install-deps: HUSKY=0 is set — ${install[*]} will NOT install the git hooks, so pre-commit formatting is off in this session; unset HUSKY (or run \`npx husky\`) to restore it."
fi

if ! command -v "$pm" >/dev/null 2>&1; then
  echo "install-deps: $pm is not on PATH — dependencies were not installed and Husky's pre-commit will not run; install $pm (corepack enable) and run \`${install[*]}\`."
  exit 0
fi

# 3. Background install. The JSON line hands the rest of this script to the harness's async runner:
#    the session starts now, the install continues for up to asyncTimeout ms.
echo '{"async": true, "asyncTimeout": 600000}'
echo "install-deps: node_modules is missing or older than ${lock##*/} — running ${install[*]} in the background; log: $log"

{
  echo "== $(date -u +%FT%TZ) ${install[*]} (cwd: $root)"
  if (cd "$root" && "${install[@]}"); then
    echo "== install: ok"
  else
    echo "== install: FAILED (exit $?) — Husky's pre-commit may be absent; run ${install[*]} by hand"
  fi
  hooks_path="$(cd "$root" && git config core.hooksPath 2>/dev/null || true)"
  if [ "$hooks_path" = ".husky/_" ] && [ -f "$root/.husky/_/pre-commit" ]; then
    echo "== husky: core.hooksPath=.husky/_ — pre-commit formatting is installed"
  else
    echo "== husky: core.hooksPath='${hooks_path:-unset}' — pre-commit formatting is NOT installed${HUSKY:+ (HUSKY=$HUSKY)}"
  fi
} >"$log" 2>&1 || true

exit 0
