#!/usr/bin/env bash
# worktree-setup.sh — install the dependencies of a new ticket worktree.
#
# Usage: bash .icm/scripts/worktree-setup.sh
#
# goose-task, the lane script of legible-consulting/house (core/setup/goose-task.sh), runs this
# script in the new worktree before it starts the lane's agent, so the agent finds node_modules
# on its first command.
# The script finds the lockfile at the root of the repository and runs one install command:
#
#   pnpm-lock.yaml          pnpm install --frozen-lockfile
#   package-lock.json       npm ci
#   yarn.lock               yarn install --immutable
#   bun.lock or bun.lockb   bun install --frozen-lockfile
#
# It runs no build, lint, typecheck, test, format or dev command (why: CI is the source of
# truth). Each worktree installs its own node_modules, because a new worktree has none of the
# untracked files of the primary clone.
#
# Exit: 0 the install ended, or there is no lockfile · 1 two package managers have a lockfile,
# the package manager is not installed, or the install failed.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

found=()
[ ! -e pnpm-lock.yaml ] || found+=(pnpm)
[ ! -e package-lock.json ] || found+=(npm)
[ ! -e yarn.lock ] || found+=(yarn)
if [ -e bun.lock ] || [ -e bun.lockb ]; then
  found+=(bun)
fi

if [ "${#found[@]}" -eq 0 ]; then
  echo "worktree-setup: no lockfile at the root, nothing to install"
  exit 0
fi
if [ "${#found[@]}" -gt 1 ]; then
  echo "worktree-setup: lockfiles of more than one package manager at the root (${found[*]}); keep one" >&2
  exit 1
fi

pm="${found[0]}"
command -v "$pm" >/dev/null 2>&1 || {
  echo "worktree-setup: the lockfile needs $pm, and $pm is not installed" >&2
  exit 1
}

case "$pm" in
  pnpm) exec pnpm install --frozen-lockfile ;;
  npm) exec npm ci ;;
  yarn) exec yarn install --immutable ;;
  bun) exec bun install --frozen-lockfile ;;
esac
