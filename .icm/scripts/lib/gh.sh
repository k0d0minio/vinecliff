#!/usr/bin/env bash
# lib/gh.sh — the one GitHub transport for the pipeline scripts. Sourced, not run (except --check).
#
# Every GitHub call in .icm/scripts/ — the PR create, the PR reads, the label PUT, the body PATCH,
# the PR search — goes through gh_api. It tries the REST API with curl and the token in
# GITHUB_TOKEN / GH_TOKEN first, exactly as the scripts always did. When there is no token, the
# request fails on the network, or GitHub answers non-2xx, it retries the same request through the
# `gh` CLI — if that is installed and logged in (`gh auth status`, checked with the token variables
# UNSET so the CLI's own login is what is tested, not the token that just failed). When neither
# route produces an HTTP answer it dies with ONE message that names what THIS environment is
# missing and how to fix it: the token variable in a cloud session or an Actions step, the login
# on a machine. The scripts' RESULT lines are untouched by any of this — a die is stderr + exit 1.
#
# One caveat on the fallback: a non-2xx that is a real answer (a 404 probe, a 422 "already
# exists") is retried through `gh` once and then handed back unchanged — the caller judges the
# code as before. It costs one extra call on a machine that has both routes; it never changes
# a verdict.
#
# Environments this recognises, and the fix it names for each:
#   GitHub Actions             GITHUB_ACTIONS=true      → the step's env + job permissions
#   Claude Code cloud session  CLAUDE_CODE_REMOTE=true  → the environment's variables (no gh there)
#   OpenCode / Claude Code local / plain shell           → export the token, or `gh auth login`
#
# Contract for callers (source it after die() is defined — it defines one otherwise):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/gh.sh"
#     → sets GH_API (GITHUB_API_URL, default https://api.github.com), repo (GITHUB_REPO, default
#       derived from the `origin` remote — the template ships no repo literal) and gh_token
#       (GITHUB_TOKEN, else GH_TOKEN, else empty).
#   gh_require "<why>"               preflight: die NOW, before any side effect, when no route can
#                                    work at all (no token and no gh login). Cheap — no request.
#   gh_api <METHOD> <path> [<json>]  prints "<body>\n<http_code>" on stdout and returns 0 whenever
#                                    an HTTP answer was obtained (2xx or not); dies when no route
#                                    answers. <path> is relative to GH_API ("/repos/o/r/pulls").
#   gh_route                         after a gh_api call: "curl" or "gh" — which route answered
#                                    (set in the calling shell only when gh_api was not run inside
#                                    a command substitution; the fallback also says so on stderr).
#
# Standalone check (the ten-second credential test in _shared/github.md → Runs anywhere):
#   .icm/scripts/lib/gh.sh --check   GET /repos/<repo> through the same logic, print the route
#                                    that answered, RESULT: OK (exit 0) or the die message (exit 1).

# --- config from the process environment (no .env loading) -----------------------------------------

GH_API="${GITHUB_API_URL:-https://api.github.com}"
# owner/repo: the environment's override, else derived from `origin` (https or ssh form). A repo
# with neither cannot make a single call, so say so once, here, before any script does work.
repo="${GITHUB_REPO:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" remote get-url origin 2>/dev/null \
  | sed -E 's#^.*github\.com[:/]##; s#\.git$##; s#/$##' || true)}"
[ -n "$repo" ] || die "GITHUB_REPO is not set and no origin remote to derive it from"
gh_token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
_gh_token_name="GITHUB_TOKEN"
[ -n "${GITHUB_TOKEN:-}" ] || _gh_token_name="GH_TOKEN"

declare -F die >/dev/null 2>&1 || die() { echo "error: $*" >&2; exit 1; }

_gh_route=""
_gh_cli_state=""   # "" (not probed yet) | ok | missing | unauthenticated
_gh_cli_note=""

gh_route() { printf '%s' "$_gh_route"; }

# --- which environment is this? ---------------------------------------------------------------------

gh_env_name() {
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "GitHub Actions"
  elif [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || [ -n "${CLAUDE_CODE_REMOTE_SESSION_ID:-}" ]; then
    echo "Claude Code cloud session"
  elif env | grep -q '^OPENCODE'; then
    echo "OpenCode"
  elif [ -n "${CLAUDECODE:-}" ]; then
    echo "Claude Code, local"
  else
    echo "local shell"
  fi
}

gh_env_fix() {
  case "$(gh_env_name)" in
    "GitHub Actions")
      echo "put 'GH_TOKEN: \${{ github.token }}' (or GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }}) in the step's env and give the job 'permissions: contents: write, pull-requests: write, issues: write' — gh is preinstalled on hosted runners and reads GH_TOKEN, so that one variable serves both routes" ;;
    "Claude Code cloud session")
      echo "add GH_TOKEN (or GITHUB_TOKEN) to the cloud environment's variables (claude.ai/code → the environment → Environment variables): a token for ${repo} with contents, pull-requests and issues read/write — gh is not installed in cloud sessions, so the token is the only route" ;;
    "OpenCode")
      echo "export GITHUB_TOKEN or GH_TOKEN in the shell OpenCode was started from (contents, pull-requests, issues read/write on ${repo}), or run 'gh auth login' on this machine" ;;
    *)
      echo "export GITHUB_TOKEN or GH_TOKEN (contents, pull-requests, issues read/write on ${repo}), or run 'gh auth login' on this machine" ;;
  esac
}

# --- the gh CLI: installed and logged in on its own account? ----------------------------------------
# The host gh talks to is derived from GH_API so a GHES API base still lands on the right login.

_gh_host() {
  local h="${GH_API#*://}"; h="${h%%/*}"
  [ "$h" = "api.github.com" ] && h="github.com"
  printf '%s' "$h"
}

# Runs gh with the token variables unset — the fallback exists to test the CLI's OWN login, not
# to hand the same failed token to a second client.
_gh_cli() { env -u GITHUB_TOKEN -u GH_TOKEN GH_HOST="$(_gh_host)" gh "$@"; }

_gh_cli_probe() {
  [ -z "$_gh_cli_state" ] || return 0
  if ! command -v gh >/dev/null 2>&1; then
    _gh_cli_state="missing"; _gh_cli_note="the gh CLI is not installed"
  elif _gh_cli auth status >/dev/null 2>&1; then
    _gh_cli_state="ok"; _gh_cli_note="the gh CLI is logged in"
  else
    _gh_cli_state="unauthenticated"; _gh_cli_note="the gh CLI is installed but not logged in (gh auth status failed with the token variables unset)"
  fi
}

# --- the two transports ------------------------------------------------------------------------------
# Both print "<body>\n<http_code>" and return 0 only when an HTTP status was obtained.

_gh_curl() { # METHOD path [json]
  local args=(-sS -m 30 -w $'\n%{http_code}' -X "$1"
    -H "Authorization: Bearer $gh_token"
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28")
  [ -n "${3:-}" ] && args+=(-H "Content-Type: application/json" -d "$3")
  curl "${args[@]}" "${GH_API}$2"
}

_gh_via_cli() { # METHOD path [json]  → parses `gh api --include` output into the same shape
  local out rc=0 http body
  local args=(api --method "$1" --include
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28")
  if [ -n "${3:-}" ]; then
    out="$(printf '%s' "$3" | _gh_cli "${args[@]}" --input - "${GH_API}$2" 2>/dev/null)" || rc=$?
  else
    out="$(_gh_cli "${args[@]}" "${GH_API}$2" 2>/dev/null)" || rc=$?
  fi
  out="$(printf '%s' "$out" | tr -d '\r')"
  http="$(printf '%s\n' "$out" | head -n1 | sed -nE 's#^HTTP/[0-9.]+ ([0-9]{3}).*#\1#p')"
  if [ -z "$http" ]; then
    # No status line: gh never got an answer (not logged in after all, a transport error, or an
    # unknown exit). Report as "no answer" and let gh_api decide what to say.
    return 1
  fi
  # Body is everything after the first blank line (the end of the headers block).
  body="$(printf '%s\n' "$out" | awk 'hdr_done { print; next } /^$/ { hdr_done=1 }')"
  printf '%s\n%s' "$body" "$http"
  return 0
}

# --- the public calls --------------------------------------------------------------------------------

gh_require() { # <why>
  [ -n "$gh_token" ] && return 0
  _gh_cli_probe
  [ "$_gh_cli_state" = "ok" ] && return 0
  die "no GitHub route works in this environment ($(gh_env_name)) for ${1:-this call}: GITHUB_TOKEN and GH_TOKEN are unset; ${_gh_cli_note}. Fix: $(gh_env_fix)"
}

gh_api() { # <METHOD> <path> [<json>]
  local method="$1" path="$2" json="${3:-}"
  local resp http curl_note="" curl_answer="" errf
  _gh_route=""

  if [ -n "$gh_token" ]; then
    errf="$(mktemp)"
    if resp="$(_gh_curl "$method" "$path" "$json" 2>"$errf")"; then
      http="$(printf '%s' "$resp" | tail -n1)"
      case "$http" in
        2??) rm -f "$errf"; _gh_route="curl"; printf '%s\n' "$resp"; return 0 ;;
      esac
      local reason
      reason="$(printf '%s' "$resp" | sed '$d' | jq -r '.message // empty' 2>/dev/null || true)"
      curl_note="${_gh_token_name} is set but GitHub answered HTTP ${http}${reason:+ (${reason})}"
      curl_answer="$resp"
    else
      curl_note="${_gh_token_name} is set but curl could not reach ${GH_API} ($(head -c 200 "$errf" | tr -d '\n'))"
    fi
    rm -f "$errf"
  else
    curl_note="GITHUB_TOKEN and GH_TOKEN are unset"
  fi

  _gh_cli_probe
  if [ "$_gh_cli_state" = "ok" ]; then
    echo "gh.sh: ${curl_note} — retrying ${method} ${path%%\?*} through the gh CLI" >&2
    if resp="$(_gh_via_cli "$method" "$path" "$json")"; then
      _gh_route="gh"; printf '%s\n' "$resp"; return 0
    fi
    _gh_cli_note="the gh CLI is logged in but returned no HTTP answer for ${method} ${path%%\?*}"
  fi

  # curl did get a real HTTP answer and gh could not improve on it → hand it back; the caller
  # judges the code exactly as it always did (a 404 probe stays a 404).
  if [ -n "$curl_answer" ]; then
    _gh_route="curl"; printf '%s\n' "$curl_answer"; return 0
  fi

  die "no GitHub route works in this environment ($(gh_env_name)) for ${method} ${path%%\?*}: ${curl_note}; ${_gh_cli_note}. Fix: $(gh_env_fix)"
}

# --- standalone: `lib/gh.sh --check` ------------------------------------------------------------------

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  [ "${1:-}" = "--check" ] || die "usage: .icm/scripts/lib/gh.sh --check   (this file is otherwise sourced by the pipeline scripts)"
  command -v curl >/dev/null || die "curl not found"
  echo "environment: $(gh_env_name); token: $([ -n "$gh_token" ] && echo "$_gh_token_name set" || echo "none"); repo: $repo; api: $GH_API" >&2
  # Not a command substitution, so _gh_route survives into this shell.
  _check_out="$(mktemp)"; trap 'rm -f "$_check_out"' EXIT
  gh_api GET "/repos/${repo}" > "$_check_out" || exit 1
  resp="$(cat "$_check_out")"
  http="$(printf '%s' "$resp" | tail -n1)"
  [ "$http" = "200" ] || die "GET /repos/${repo} answered HTTP $http via ${_gh_route} — the route works but this credential cannot read ${repo}: $(printf '%s' "$resp" | sed '$d' | jq -r '.message // "no message"' 2>/dev/null)"
  echo "GET /repos/${repo} → 200 via ${_gh_route}$([ "$_gh_route" = "curl" ] && echo " ($_gh_token_name)" || echo " (gh CLI login)")"
  echo "RESULT: OK"
fi
