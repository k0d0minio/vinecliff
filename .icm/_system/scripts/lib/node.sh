#!/usr/bin/env bash
# lib/node.sh — the package manager of a Node repo. Sourced, not run. Needs jq.
#
#   node_pm              pnpm | yarn | npm, from the lockfile at the top of the repo
#   node_has <script>    0 when package.json names the script
#   node_run <script>    run the script with the package manager, when package.json names it
#   node_install         install the dependencies from the lockfile, with no change to it.
#                        With no package.json: nothing to install, exit 0 (rc26)

node_pm() {
  if [ -f pnpm-lock.yaml ]; then echo pnpm
  elif [ -f yarn.lock ]; then echo yarn
  else echo npm
  fi
}

node_has() { [ -f package.json ] && jq -e --arg s "$1" '.scripts[$s] // empty' package.json >/dev/null; }

node_run() {
  node_has "$1" || { echo "[node] package.json names no '$1': skipped"; return 0; }
  echo "[node] $(node_pm) run $*"
  "$(node_pm)" run "$@"
}

node_install() {
  [ -f package.json ] || { echo "[node] no package.json: nothing to install"; return 0; }
  case "$(node_pm)" in
    pnpm) corepack enable >/dev/null 2>&1 || true; pnpm install --frozen-lockfile ;;
    yarn) corepack enable >/dev/null 2>&1 || true; yarn install --frozen-lockfile ;;
    *) npm ci ;;
  esac
}
