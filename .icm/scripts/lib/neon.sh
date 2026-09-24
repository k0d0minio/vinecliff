#!/usr/bin/env bash
# lib/neon.sh — the one Neon transport for the pipeline scripts. Sourced, not run (except --check).
#
# What lib/vercel.sh is to Vercel, this is to Neon: curl + the API key NAMED by the repo's own
# database block (`.icm/project.json` → database.neon.api_key_env, default NEON_API_KEY —
# lib/project.sh). Every Neon call a template-owned script makes — db-branch.sh's `neon` isolation,
# db-env.sh, setup.sh's one read of the project — goes through here (decision D32).
#
# Unlike lib/vercel.sh this file DOES carry write verbs — create, delete and reset a branch —
# because a Neon branch is a run's or an environment's working copy, never production, and every
# write here is scoped to a name the pipeline gave: `run/<slug>` (db-branch.sh), `preview/<git
# branch>` (the Vercel integration's own naming) or the UAT branch (`_shared/promotion.md`). The
# project's default (production) branch is never written, deleted or reset by anything in this
# file, whatever a caller asks; the UAT branch is never deleted; a name outside those shapes is
# refused before any request is made.
#
# Nothing outside the repo is read: no registry, no icm-board, no `~/Apps`. The project id comes
# from the database block; the key's VALUE comes from the process environment and never reaches
# argv (curl reads its configuration from stdin) or stdout.
#
# Contract for callers (source after die() is defined and lib/project.sh is sourced):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/neon.sh"
#     → sets NEON_API (default https://console.neon.tech/api/v2), neon_project
#       (database.neon.project_id), neon_key_name (database.neon.api_key_env) and neon_key (its
#       value, or empty). Nothing is fetched at source time.
#   neon_declared                    returns 0 when database.provider is neon and a project_id is set.
#   neon_ready                       returns 0 when declared AND curl, jq and the key are present —
#                                    the "can call" test; a script answers SKIP otherwise.
#   neon_require "<why>"             die NOW when not ready — before any side effect.
#   neon_api <METHOD> <path> [<json>]  the call; prints "<body>\n<http_code>".
#   neon_ok <resp> · neon_body <resp> · neon_code <resp> · neon_err <resp>
#   neon_branches                    GET the project's branches → the `branches` array as JSON.
#   neon_load_branches               GET once into NEON_BRANCHES (the cache the readers below use);
#                                    1 when the read failed. CALL IT AT TOP LEVEL FIRST — a die
#                                    inside a `$(...)` exits only that subshell, so a caller that
#                                    reads through command substitution must load here, where a
#                                    failure can stop the script, and read the cache afterwards.
#   neon_branch <name>               one branch's JSON by exact name, or nothing (from the cache).
#   neon_branch_id <name>            its id, or nothing.
#   neon_default_branch_id           the id of the project's default (production) branch.
#   neon_branch_state <id>           the branch's current_state (init|ready|…) — a live GET.
#   neon_branch_children <id>        the ids of the branches whose parent_id is <id>, one per line.
#   neon_connection_uri <branch_id> [--unpooled]
#                                    the branch's connection string for its first database and that
#                                    database's owner role, pooled unless told otherwise — printed
#                                    ONCE, to stdout, for an eval; never logged, never written.
#   neon_create_branch <name> <parent_id> [<expires_at>]
#                                    POST a branch with a read_write compute → the new branch's id.
#                                    Refuses a name that is not run/*.
#   neon_delete_branch <id> <name>   DELETE; refuses a name that is not run/* or preview/*, and the
#                                    UAT branch under any name.
#   neon_reset_branch <id> <parent_id> [<name>]
#                                    POST …/restore with source_branch_id = the parent ("reset from
#                                    parent"); refuses the default branch.
#   neon_wait_ready <id> [<seconds>] poll until current_state is ready (default 90s); 1 on timeout.
#   neon_now_plus_days <n>           an RFC 3339 UTC timestamp <n> days from now (GNU or BSD date).
#   neon_pipeline_name <name>        returns 0 when the pipeline gave this name (run/*, preview/*,
#                                    the UAT branch) — the only names a write verb accepts.
#
# Standalone check:
#   .icm/scripts/lib/neon.sh --check   GET the project's branches through the same logic;
#                                      RESULT: OK (exit 0) · SKIP (not declared, or no key) · the die
#                                      message (exit 1).

declare -F die >/dev/null 2>&1 || die() { echo "error: $*" >&2; exit 1; }

_neon_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=project.sh
declare -F project_field >/dev/null 2>&1 || source "$_neon_here/project.sh"

NEON_API="${NEON_API_URL:-https://console.neon.tech/api/v2}"
neon_project="$(neon_project_id)"
neon_key_name="$(neon_api_key_env)"
neon_key="${!neon_key_name:-}"

neon_declared() { [ "$(database_provider)" = "neon" ] && [ -n "$neon_project" ]; }
neon_ready()    { neon_declared && [ -n "$neon_key" ] && command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; }

neon_require() { # <why>
  neon_declared || die "no Neon project in .icm/project.json (database.provider: neon + database.neon.project_id) before ${1:-this call} — /setup asks for it"
  command -v curl >/dev/null 2>&1 || die "curl not found"
  command -v jq   >/dev/null 2>&1 || die "jq not found"
  [ -n "$neon_key" ] || die "no Neon API key in this environment for ${1:-this call}: set ${neon_key_name} (the name database.neon.api_key_env names); never pass it as an argument"
}

# curl reads its configuration from stdin so the key never appears in argv (`ps`) — the same idiom
# as lib/vercel.sh and the hydrate hook. A JSON body is passed as a curl-config string: jq's
# escaping (\" \\ \n) is exactly the set curl's config parser understands.
neon_api() { # <METHOD> <path> [<json>]
  local method="$1" path="$2" json="${3:-}"
  {
    printf 'url = "%s%s"\nrequest = "%s"\nheader = "Authorization: Bearer %s"\nheader = "Accept: application/json"\nwrite-out = "\\n%%{http_code}"\nmax-time = 60\nsilent\nshow-error\n' \
      "$NEON_API" "$path" "$method" "$neon_key"
    if [ -n "$json" ]; then
      printf 'header = "Content-Type: application/json"\ndata = %s\n' "$(printf '%s' "$json" | jq -Rs .)"
    fi
  } | curl --config - 2>/dev/null
}
neon_body() { printf '%s' "$1" | sed '$d'; }
neon_code() { printf '%s' "$1" | tail -n1; }
neon_ok()   { case "$(neon_code "$1")" in 2??) return 0 ;; *) return 1 ;; esac; }
neon_err()  { neon_body "$1" | jq -r '.message // .error // empty' 2>/dev/null || true; }
_neon_uri() { jq -rn --arg s "$1" '$s | @uri'; }

neon_branches() {
  local resp
  resp="$(neon_api GET "/projects/${neon_project}/branches")" || die "could not reach ${NEON_API} for project ${neon_project}"
  neon_ok "$resp" || die "GET /projects/${neon_project}/branches answered HTTP $(neon_code "$resp") via ${neon_key_name}: $(neon_err "$resp")"
  neon_body "$resp" | jq -c '.branches // []'
}
NEON_BRANCHES=""
neon_load_branches()     { NEON_BRANCHES="$(neon_branches)" || return 1; [ -n "$NEON_BRANCHES" ]; }
_neon_cached()           { [ -n "$NEON_BRANCHES" ] || neon_load_branches || return 1; printf '%s' "$NEON_BRANCHES"; }
neon_branch()            { _neon_cached | jq -c --arg n "$1" '[.[] | select(.name == $n)] | first // empty'; }
neon_branch_id()         { neon_branch "$1" | jq -r '.id // empty'; }
neon_default_branch_id() { _neon_cached | jq -r '[.[] | select(.default == true)] | first | .id // empty'; }
neon_branch_children()   { _neon_cached | jq -r --arg p "$1" '.[] | select(.parent_id == $p) | .id'; }
neon_branch_state() {
  local resp
  resp="$(neon_api GET "/projects/${neon_project}/branches/$1")" || return 1
  neon_ok "$resp" || return 1
  neon_body "$resp" | jq -r '.branch.current_state // empty'
}

neon_pipeline_name() { # <name>
  case "$1" in run/*|preview/*) return 0 ;; esac
  local u; u="$(neon_uat_branch)"
  [ -n "$u" ] && [ "$1" = "$u" ] && return 0
  return 1
}

neon_connection_uri() { # <branch_id> [--unpooled]
  local bid="$1" pooled=true resp db role
  [ "${2:-}" = "--unpooled" ] && pooled=false
  resp="$(neon_api GET "/projects/${neon_project}/branches/${bid}/databases")" || die "could not list the databases of branch $bid"
  neon_ok "$resp" || die "GET …/branches/$bid/databases answered HTTP $(neon_code "$resp"): $(neon_err "$resp")"
  db="$(neon_body "$resp" | jq -r '(.databases // [])[0].name // empty')"
  role="$(neon_body "$resp" | jq -r '(.databases // [])[0].owner_name // empty')"
  { [ -n "$db" ] && [ -n "$role" ]; } || die "branch $bid has no database to connect to"
  resp="$(neon_api GET "/projects/${neon_project}/connection_uri?branch_id=$(_neon_uri "$bid")&database_name=$(_neon_uri "$db")&role_name=$(_neon_uri "$role")&pooled=${pooled}")" \
    || die "could not read the connection string of branch $bid"
  neon_ok "$resp" || die "GET …/connection_uri for $bid answered HTTP $(neon_code "$resp"): $(neon_err "$resp")"
  neon_body "$resp" | jq -r '.uri // empty'
}

neon_create_branch() { # <name> <parent_id> [<expires_at>]
  local name="$1" parent="$2" expires="${3:-}" body resp
  case "$name" in run/*) : ;; *) die "refusing to create Neon branch '$name' — the pipeline creates run/<slug> branches here and nothing else (the integration creates preview/*; production is never created here)" ;; esac
  [ -n "$parent" ] || die "neon_create_branch: no parent id"
  body="$(jq -cn --arg n "$name" --arg p "$parent" --arg e "$expires" \
    '{branch: ({name: $n, parent_id: $p} + (if $e == "" then {} else {expires_at: $e} end)), endpoints: [{type: "read_write"}]}')"
  resp="$(neon_api POST "/projects/${neon_project}/branches" "$body")" || die "could not create branch $name"
  neon_ok "$resp" || die "POST /projects/${neon_project}/branches ($name) answered HTTP $(neon_code "$resp"): $(neon_err "$resp")"
  neon_body "$resp" | jq -r '.branch.id // empty'
}

neon_delete_branch() { # <id> <name>
  local id="$1" name="$2" resp
  case "$name" in run/*|preview/*) : ;; *) die "refusing to delete Neon branch '$name' — only run/* and preview/* branches are the pipeline's to delete" ;; esac
  [ -n "$NEON_BRANCHES" ] || neon_load_branches || die "could not read the project's branches before deleting $name — nothing deleted"
  [ "$name" != "$(neon_uat_branch)" ] || die "refusing to delete the UAT branch '$name' (_shared/promotion.md → The UAT database)"
  [ "$id" != "$(neon_default_branch_id)" ] || die "refusing to delete the default (production) branch"
  resp="$(neon_api DELETE "/projects/${neon_project}/branches/${id}")" || die "could not delete branch $name"
  neon_ok "$resp" || die "DELETE …/branches/$id ($name) answered HTTP $(neon_code "$resp"): $(neon_err "$resp")"
}

neon_reset_branch() { # <id> <parent_id> [<name>]
  local id="$1" parent="$2" name="${3:-$1}" resp
  [ -n "$NEON_BRANCHES" ] || neon_load_branches || die "could not read the project's branches before resetting $name — nothing reset"
  [ "$id" != "$(neon_default_branch_id)" ] || die "refusing to reset the default (production) branch"
  [ -n "$parent" ] || die "neon_reset_branch: no parent id"
  resp="$(neon_api POST "/projects/${neon_project}/branches/${id}/restore" "$(jq -cn --arg p "$parent" '{source_branch_id: $p}')")" || die "could not reset branch $name"
  neon_ok "$resp" || die "POST …/branches/$id/restore ($name) answered HTTP $(neon_code "$resp"): $(neon_err "$resp")"
}

neon_wait_ready() { # <id> [<seconds>]
  local id="$1" max="${2:-90}" waited=0 st
  while :; do
    st="$(neon_branch_state "$id" || true)"
    [ "$st" = "ready" ] && return 0
    waited=$((waited + 3)); [ "$waited" -le "$max" ] || return 1
    sleep 3
  done
}

neon_now_plus_days() { # <n>
  date -u -d "+$1 days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+"$1"d +%Y-%m-%dT%H:%M:%SZ
}

# --- standalone: `lib/neon.sh --check` ----------------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    --check)
      if ! neon_declared; then echo "no Neon project declared in .icm/project.json (database.provider: neon, database.neon.project_id) — nothing to check"; echo "RESULT: SKIP"; exit 0; fi
      if [ -z "$neon_key" ]; then echo "${neon_key_name} unset in this environment — the project ${neon_project} is declared, the route is not (export it; never in git)"; echo "RESULT: SKIP"; exit 0; fi
      neon_require "--check"
      neon_load_branches || exit 1
      n="$(printf '%s' "$NEON_BRANCHES" | jq 'length')"
      echo "Neon project ${neon_project}: ${n} branch(es), read via ${neon_key_name}"
      echo "RESULT: OK"; exit 0 ;;
    *) echo "usage: lib/neon.sh --check   (otherwise: source it)" >&2; exit 2 ;;
  esac
fi
