#!/usr/bin/env bash
# lib/vercel.sh — the Vercel transport the UAT scripts, preview-db.sh and the workflows share.
# Sourced, not run.
#
# Reads from the environment: VERCEL_TOKEN (required before any call), VERCEL_TEAM (the team's
# slug; unset means the personal scope), VERCEL_PROJECT (the project's name; the repository's
# name when unset), UAT_ENVIRONMENT (the custom environment's slug; `uat` when unset). The token
# never reaches a command line: curl reads its configuration from a file only this process can
# read. No function here prints a variable value. The contracts are .icm/uat/CONTEXT.md and
# .icm/database/CONTEXT.md.
#
# Functions (the caller defines `die`, or the default below applies):
#   vercel_require "<why>"                  stop now when VERCEL_TOKEN is empty.
#   vercel_call <METHOD> <path> [<file>]    one request. Prints the body, then the HTTP code on its own line.
#   vercel_get <path>                       GET. Prints the body. Dies on a code outside 2xx.
#   vercel_project_name                     VERCEL_PROJECT, or the repository's name.
#   vercel_project                          the project's JSON (GET /v9/projects/<name>).
#   vercel_project_id                       the project's id.
#   vercel_custom_env                       the custom environment whose slug is UAT_ENVIRONMENT, or nothing.
#   vercel_deployments <target>             the 20 newest deployments for <target>: production, or a custom environment's slug.
#   vercel_deployment <target> <sha>        the newest deployment of <sha> for <target>, or nothing.
#   vercel_production_current               the id of the deployment production serves now.
#   vercel_production_domains               the project's production domains, one per line.
#   vercel_promote <deployment id>          POST promote. Prints the HTTP code.
#   vercel_env_find <key> <custom env id>   the id of that variable on that environment, or nothing.
#   vercel_env_upsert <key> <file> <custom env id>   create or replace the variable with the file's content, encrypted.
#   vercel_env_delete <variable id>         delete one variable.
#   vercel_branch_env_find <key> <git branch>   the id of that Preview variable scoped to the git branch, or nothing.
#   vercel_branch_env_upsert <key> <file> <git branch>   create or replace that Preview variable, encrypted.
#   vercel_branch_deployment <git branch>   the newest preview deployment of the git branch, or nothing.
#   vercel_redeploy <deployment id>         build that deployment's git source again. Prints the new deployment's URL.

VERCEL_API="${VERCEL_API:-https://api.vercel.com}"
if ! declare -F die >/dev/null 2>&1; then
  die() { echo "error: $*" >&2; exit 1; }
fi

vercel_require() { # <why>
  [ -n "${VERCEL_TOKEN:-}" ] || die "VERCEL_TOKEN is not set: $1 needs it"
  command -v curl >/dev/null 2>&1 || die "curl is not installed"
  command -v jq >/dev/null 2>&1 || die "jq is not installed"
}

vercel_call() { # <METHOD> <path> [<json file>]
  local method="$1" path="$2" body="${3:-}" url sep cfg rc
  url="${VERCEL_API}${path}"
  case "$path" in *\?*) sep='&' ;; *) sep='?' ;; esac
  [ -z "${VERCEL_TEAM:-}" ] || url="${url}${sep}slug=${VERCEL_TEAM}"
  cfg="$(mktemp)"
  {
    printf 'url = "%s"\n' "$url"
    printf 'request = "%s"\n' "$method"
    printf 'header = "Authorization: Bearer %s"\n' "$VERCEL_TOKEN"
    printf 'header = "Content-Type: application/json"\n'
    [ -z "$body" ] || printf 'data = "@%s"\n' "$body"
    printf 'write-out = "\\n%%{http_code}"\nmax-time = 60\nsilent\nshow-error\n'
  } > "$cfg"
  curl --config "$cfg"
  rc=$?
  rm -f "$cfg"
  return "$rc"
}

vercel_body() { printf '%s\n' "$1" | sed '$d'; }
vercel_code() { printf '%s\n' "$1" | tail -n1; }

vercel_get() { # <path>
  local resp
  resp="$(vercel_call GET "$1")" || die "GET $1: curl failed"
  case "$(vercel_code "$resp")" in
    2??) vercel_body "$resp" ;;
    *) die "GET $1 answered HTTP $(vercel_code "$resp")" ;;
  esac
}

vercel_project_name() {
  if [ -n "${VERCEL_PROJECT:-}" ]; then
    printf '%s' "$VERCEL_PROJECT"
  else
    basename -s .git "$(git config --get remote.origin.url 2>/dev/null || pwd)"
  fi
}

vercel_project() { vercel_get "/v9/projects/$(vercel_project_name)"; }

vercel_project_id() {
  [ -n "${_vercel_project_id:-}" ] || _vercel_project_id="$(vercel_project | jq -r '.id')"
  printf '%s' "$_vercel_project_id"
}

vercel_custom_env() {
  vercel_get "/v9/projects/$(vercel_project_id)/custom-environments" \
    | jq -c --arg s "${UAT_ENVIRONMENT:-uat}" '[.environments[] | select(.slug == $s)] | first // empty'
}

vercel_deployments() { # <target>
  vercel_get "/v6/deployments?projectId=$(vercel_project_id)&target=$1&limit=20" | jq -c '.deployments'
}

vercel_deployment() { # <target> <sha>
  local q
  q="projectId=$(vercel_project_id)&target=$1&limit=20"
  # Vercel's sha filter matches the full 40-character SHA only. A shorter one is matched here.
  [ "${#2}" -ne 40 ] || q="${q}&sha=$2"
  vercel_get "/v6/deployments?${q}" \
    | jq -c --arg s "$2" '[.deployments[] | select((.meta.githubCommitSha // "") | startswith($s))] | sort_by(-.created) | first // empty'
}

vercel_production_current() { vercel_project | jq -r '.targets.production.id // empty'; }

vercel_production_domains() {
  vercel_get "/v9/projects/$(vercel_project_id)/domains?limit=100" \
    | jq -r '.domains[] | select(.gitBranch == null and .customEnvironmentId == null and .redirect == null) | .name'
}

vercel_promote() { # <deployment id>
  local resp
  resp="$(vercel_call POST "/v10/projects/$(vercel_project_id)/promote/$1")" || die "POST promote: curl failed"
  vercel_code "$resp"
}

vercel_env_find() { # <key> <custom env id>
  vercel_get "/v9/projects/$(vercel_project_id)/env" \
    | jq -r --arg k "$1" --arg e "$2" '[.envs[] | select(.key == $k and ((.customEnvironmentIds // []) | index($e) != null))] | first | .id // empty'
}

vercel_env_upsert() { # <key> <file holding the value> <custom env id>
  local body resp code
  body="$(mktemp)"
  jq -n --arg k "$1" --rawfile v "$2" --arg e "$3" \
    '{key: $k, value: ($v | rtrimstr("\n")), type: "encrypted", customEnvironmentIds: [$e]}' > "$body"
  resp="$(vercel_call POST "/v10/projects/$(vercel_project_id)/env?upsert=true" "$body")" || { rm -f "$body"; die "POST env $1: curl failed"; }
  rm -f "$body"
  code="$(vercel_code "$resp")"
  case "$code" in
    2??) echo "$1 set on the environment (HTTP $code)" ;;
    *) die "POST env $1 answered HTTP $code: $(vercel_body "$resp" | jq -r '.error.message // empty' 2>/dev/null)" ;;
  esac
}

vercel_env_delete() { # <variable id>
  local resp code
  resp="$(vercel_call DELETE "/v9/projects/$(vercel_project_id)/env/$1")" || die "DELETE env $1: curl failed"
  code="$(vercel_code "$resp")"
  case "$code" in
    2??) echo "variable $1 removed (HTTP $code)" ;;
    *) die "DELETE env $1 answered HTTP $code" ;;
  esac
}

vercel_branch_env_find() { # <key> <git branch>
  local b
  b="$(jq -rn --arg b "$2" '$b | @uri')"
  vercel_get "/v9/projects/$(vercel_project_id)/env?gitBranch=${b}" \
    | jq -r --arg k "$1" --arg b "$2" '[.envs[] | select(.key == $k and .gitBranch == $b and ((.target // []) | index("preview") != null))] | first | .id // empty'
}

vercel_branch_env_upsert() { # <key> <file holding the value> <git branch>
  local body resp code
  body="$(mktemp)"
  jq -n --arg k "$1" --rawfile v "$2" --arg b "$3" \
    '{key: $k, value: ($v | rtrimstr("\n")), type: "encrypted", target: ["preview"], gitBranch: $b}' > "$body"
  resp="$(vercel_call POST "/v10/projects/$(vercel_project_id)/env?upsert=true" "$body")" || { rm -f "$body"; die "POST env $1: curl failed"; }
  rm -f "$body"
  code="$(vercel_code "$resp")"
  case "$code" in
    2??) echo "$1 set on Preview for $3 (HTTP $code)" ;;
    *) die "POST env $1 answered HTTP $code: $(vercel_body "$resp" | jq -r '.error.message // empty' 2>/dev/null)" ;;
  esac
}

vercel_branch_deployment() { # <git branch>
  vercel_get "/v6/deployments?projectId=$(vercel_project_id)&limit=100" \
    | jq -c --arg b "$1" '[.deployments[] | select((.meta.githubCommitRef // "") == $b and (.target // "preview") == "preview")] | sort_by(-.created) | first // empty'
}

vercel_redeploy() { # <deployment id>
  local src body resp code
  src="$(vercel_get "/v13/deployments/$1" | jq -c '.gitSource // empty | {type, repoId, ref, sha}')"
  [ -n "$src" ] || die "deployment $1 has no git source to build again"
  body="$(mktemp)"
  jq -n --arg n "$(vercel_project_name)" --arg p "$(vercel_project_id)" --argjson g "$src" \
    '{name: $n, project: $p, gitSource: $g}' > "$body"
  resp="$(vercel_call POST "/v13/deployments?forceNew=1" "$body")" || { rm -f "$body"; die "POST deployments: curl failed"; }
  rm -f "$body"
  code="$(vercel_code "$resp")"
  case "$code" in
    2??) echo "https://$(vercel_body "$resp" | jq -r '.url // empty')" ;;
    *) die "POST deployments answered HTTP $code: $(vercel_body "$resp" | jq -r '.error.message // empty' 2>/dev/null)" ;;
  esac
}
