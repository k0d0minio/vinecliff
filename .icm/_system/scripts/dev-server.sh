#!/usr/bin/env bash
# dev-server.sh — the local dev server of the repo, for the pictures of the agent review-shots.
# This script is the one exception to router rule 5. It starts no build, test, lint or format.
#
# Usage:
#   dev-server.sh start [--wait <seconds>]   start the server in the background, in this
#                                            checkout, on a free port. Wait until it answers
#   dev-server.sh stop                       stop it. No process of it stays
#
# The command: the line "- dev server: <command>" of .icm/project-rules.md, where {port} is
# the port. Else the script "dev" of package.json, with the package manager of the lockfile,
# the variable PORT and the option --port. Before the start, a package.json with no
# node_modules gets the install of its lockfile (5 minutes at most).
# The server reads only the files that the repo has for local work. The script reads,
# copies and pulls no environment file and no secret.
# --wait: default 180 seconds (ICM_DEV_WAIT_S). The process group stops when the server
# exits or does not answer in that time. The state is in the git folder of this checkout.
#
# Last line: "RESULT: OK <url>" (start), "RESULT: OK stopped" (stop), or
# "RESULT: STOP <reason>". A STOP does not fail the run: review-shots writes the reason.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
help_if_asked "$@"

usage="usage: dev-server.sh start [--wait <seconds>] | stop"
act="${1:-}"
wait_s="${ICM_DEV_WAIT_S:-180}"
[ "${2:-}" != --wait ] || wait_s="${3:-}"
[[ "$wait_s" =~ ^[0-9]+$ ]] || stop "$usage"
need git jq
cd "$(icm_root)"
state="$(git rev-parse --absolute-git-dir)/icm-dev-server"
log="$(git rev-parse --absolute-git-dir)/icm-dev-server.log"

halt() {  # halt <pid>: the process group, TERM then KILL
  kill -TERM -- "-$1" 2>/dev/null || kill -TERM "$1" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$1" 2>/dev/null || return 0; sleep 1; done
  kill -KILL -- "-$1" 2>/dev/null || kill -KILL "$1" 2>/dev/null || true
}
answers() {  # answers <port>: an HTTP answer on the port. Bash only: no curl, no proxy
  ( exec 3<>"/dev/tcp/127.0.0.1/$1" && printf 'GET / HTTP/1.0\r\nHost: localhost\r\n\r\n' >&3 \
    && IFS= read -r -t 5 line <&3 && [[ "$line" == HTTP/* ]] ) 2>/dev/null
}

case "$act" in
  stop)
    if [ -f "$state" ]; then halt "$(cut -d' ' -f1 "$state")"; rm -f "$state"; fi
    echo "RESULT: OK stopped"
    exit 0
    ;;
  start) ;;
  *) stop "$usage" ;;
esac
if [ -f "$state" ] && kill -0 "$(cut -d' ' -f1 "$state")" 2>/dev/null; then
  echo "RESULT: OK http://127.0.0.1:$(cut -d' ' -f2 "$state")"
  exit 0
fi

port="${ICM_DEV_PORT:-4100}"
while (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; do
  port=$((port + 1))
  [ "$port" -lt 4200 ] || stop "no free port from 4100 to 4199"
done

cmd="$(sed -n 's/^- dev server: *//p' .icm/project-rules.md 2>/dev/null | head -n1)"
if [ -n "$cmd" ]; then
  cmd="${cmd//\{port\}/$port}"
elif [ -f package.json ] && jq -e '.scripts.dev' package.json >/dev/null 2>&1; then
  pm=npm
  [ ! -f pnpm-lock.yaml ] || pm=pnpm
  [ ! -f yarn.lock ] || pm=yarn
  { [ ! -f bun.lockb ] && [ ! -f bun.lock ]; } || pm=bun
  need "$pm"
  if [ ! -d node_modules ]; then
    install=(install)
    [ "$pm" != npm ] || install=(ci)
    timeout 300 "$pm" "${install[@]}" >"$log" 2>&1 \
      || stop "the install of the dependencies failed: $(tail -n1 "$log" | cut -c1-200)"
  fi
  if [ "$pm" = npm ]; then cmd="PORT=$port npm run dev -- --port $port"; else cmd="PORT=$port $pm run dev --port $port"; fi
else
  stop "no dev command: .icm/project-rules.md has no line '- dev server:', and package.json has no script dev"
fi

# Job control gives the server its own process group: stop ends the server and its children.
set -m
nohup bash -c "$cmd" >"$log" 2>&1 &
pid=$!
set +m
echo "$pid $port" > "$state"
echo "dev server: $cmd (process $pid)"
waited=0
until answers "$port"; do
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$state"
    stop "the dev server stopped: $(grep -v '^[[:space:]]*$' "$log" | tail -n1 | cut -c1-200)"
  fi
  if [ "$waited" -ge "$wait_s" ]; then
    halt "$pid"; rm -f "$state"
    stop "the dev server did not answer in ${wait_s} s: $(grep -v '^[[:space:]]*$' "$log" | tail -n1 | cut -c1-200)"
  fi
  sleep 2
  waited=$((waited + 2))
done
echo "RESULT: OK http://127.0.0.1:$port"
