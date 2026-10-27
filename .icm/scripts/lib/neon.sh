#!/usr/bin/env bash
# lib/neon.sh — the Neon transport preview-db.sh uses. Sourced, not run.
#
# Reads from the environment: NEON_API_KEY and NEON_PROJECT_ID (both required before any call).
# The key never reaches a command line: curl reads its configuration from a file only this
# process can read. The project's default branch is the base: UAT's database with UAT,
# production's without. No function here writes it or deletes it, whatever a caller asks, and a
# delete refuses every name outside preview/*. A connection string is printed by one function
# only, neon_connection_uri, and a caller writes it to a file, never to a terminal. The contract
# is .icm/database/CONTEXT.md.
#
# Functions (the caller defines `die`, or the default below applies):
#   neon_require "<why>"                     stop now when the key or the project id is missing.
#   neon_call <METHOD> <path> [<file>]       one request. Prints the body, then the HTTP code on its own line.
#   neon_get <path>                          GET. Prints the body. Dies on a code outside 2xx.
#   neon_branches                            the project's branches as a JSON array.
#   neon_default_branch                      the default branch's JSON.
#   neon_branch <name>                       one branch's JSON by exact name, or nothing.
#   neon_branch_state <id>                   the branch's current_state, read live.
#   neon_wait_ready <id> [<seconds>]         poll until current_state is ready. 1 on timeout (default 180 s).
#   neon_branch_database <id>               "<database name>\t<owner role>" of the branch's first database.
#   neon_create_branch <name> <parent id>   create a branch with the parent's data and a read-write compute. Prints its JSON.
#   neon_delete_branch <id> <name>           DELETE. Refuses the default branch and a name outside preview/*.
#   neon_connection_uri <id> <database> <role> <pooled: true|false>   prints the connection string.

NEON_API="${NEON_API:-https://console.neon.tech/api/v2}"
if ! declare -F die >/dev/null 2>&1; then
  die() { echo "error: $*" >&2; exit 1; }
fi

neon_require() { # <why>
  [ -n "${NEON_API_KEY:-}" ] || die "NEON_API_KEY is not set: $1 needs it"
  [ -n "${NEON_PROJECT_ID:-}" ] || die "NEON_PROJECT_ID is not set: $1 needs it"
  command -v curl >/dev/null 2>&1 || die "curl is not installed"
  command -v jq >/dev/null 2>&1 || die "jq is not installed"
}

neon_call() { # <METHOD> <path> [<json file>]
  local method="$1" path="$2" body="${3:-}" cfg rc
  cfg="$(mktemp)"
  {
    printf 'url = "%s%s"\n' "$NEON_API" "$path"
    printf 'request = "%s"\n' "$method"
    printf 'header = "Authorization: Bearer %s"\n' "$NEON_API_KEY"
    printf 'header = "Accept: application/json"\n'
    printf 'header = "Content-Type: application/json"\n'
    [ -z "$body" ] || printf 'data = "@%s"\n' "$body"
    printf 'write-out = "\\n%%{http_code}"\nmax-time = 60\nsilent\nshow-error\n'
  } > "$cfg"
  curl --config "$cfg"
  rc=$?
  rm -f "$cfg"
  return "$rc"
}

neon_body() { printf '%s\n' "$1" | sed '$d'; }
neon_code() { printf '%s\n' "$1" | tail -n1; }
neon_message() { neon_body "$1" | jq -r '.message // .error // empty' 2>/dev/null; }

neon_get() { # <path>
  local resp
  resp="$(neon_call GET "$1")" || die "GET $1: curl failed"
  case "$(neon_code "$resp")" in
    2??) neon_body "$resp" ;;
    *) die "GET $1 answered HTTP $(neon_code "$resp"): $(neon_message "$resp")" ;;
  esac
}

neon_branches() { neon_get "/projects/${NEON_PROJECT_ID}/branches" | jq -c '.branches'; }
neon_default_branch() { neon_branches | jq -c '[.[] | select(.default == true)] | first // empty'; }
neon_branch() { neon_branches | jq -c --arg n "$1" '[.[] | select(.name == $n)] | first // empty'; }
neon_branch_state() { neon_get "/projects/${NEON_PROJECT_ID}/branches/$1" | jq -r '.branch.current_state // empty'; }

neon_wait_ready() { # <id> [<seconds>]
  local deadline=$((SECONDS + ${2:-180})) state
  while :; do
    state="$(neon_branch_state "$1")"
    [ "$state" != ready ] || return 0
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep 5
  done
}

neon_branch_database() { # <id>
  neon_get "/projects/${NEON_PROJECT_ID}/branches/$1/databases" \
    | jq -r '.databases | first | "\(.name)\t\(.owner_name)"'
}

neon_create_branch() { # <name> <parent id>
  local body resp code
  body="$(mktemp)"
  jq -n --arg n "$1" --arg p "$2" \
    '{branch: {name: $n, parent_id: $p}, endpoints: [{type: "read_write"}]}' > "$body"
  resp="$(neon_call POST "/projects/${NEON_PROJECT_ID}/branches" "$body")" || { rm -f "$body"; die "POST branches: curl failed"; }
  rm -f "$body"
  code="$(neon_code "$resp")"
  case "$code" in
    2??) neon_body "$resp" ;;
    *) die "POST branches answered HTTP $code: $(neon_message "$resp")" ;;
  esac
}

neon_delete_branch() { # <id> <name>
  local default_id resp code
  case "$2" in
    preview/*) ;;
    *) die "refusing to delete '$2': only preview/* is this repo's to delete" ;;
  esac
  default_id="$(neon_default_branch | jq -r '.id // empty')"
  [ "$1" != "$default_id" ] || die "refusing to delete the default branch: it is the base"
  resp="$(neon_call DELETE "/projects/${NEON_PROJECT_ID}/branches/$1")" || die "DELETE branch $2: curl failed"
  code="$(neon_code "$resp")"
  case "$code" in
    2??) return 0 ;;
    *) die "DELETE branch $2 answered HTTP $code: $(neon_message "$resp")" ;;
  esac
}

neon_connection_uri() { # <id> <database> <role> <pooled>
  neon_get "/projects/${NEON_PROJECT_ID}/connection_uri?branch_id=$1&database_name=$2&role_name=$3&pooled=$4" \
    | jq -r '.uri // empty'
}
