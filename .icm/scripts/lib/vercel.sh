#!/usr/bin/env bash
# lib/vercel.sh — the Vercel transport the UAT scripts and promote.yml share.
# Sourced, not run.
#
# Reads from the environment: VERCEL_TOKEN (required before any call), VERCEL_TEAM (the team's
# slug. Unset means the personal scope), UAT_ENVIRONMENT (the custom environment's slug, `uat`
# when unset). The token never reaches a command line: curl reads its configuration from a file
# only this process can read. No function here prints a variable value. The contract is
# .icm/uat/CONTEXT.md.
#
# No variable names a project. The build's projects are the projects in the team whose git link
# is this repository (GET /v10/projects?repoUrl=, and each project's link is read again). The
# UAT projects are the ones among them with the custom environment UAT_ENVIRONMENT. A caller
# lists them, then calls vercel_use on each one. The functions after vercel_use act on that
# project. The repository comes from gh_repo in lib/github.sh.
#
# Functions (the caller defines `die`, or the default below applies):
#   vercel_require "<why>"                  stop now when VERCEL_TOKEN is empty.
#   vercel_call <METHOD> <path> [<file>]    one request. Prints the body, then the HTTP code on its own line.
#   vercel_get <path>                       GET. Prints the body. Dies on a code outside 2xx.
#   vercel_repo_url                         https://github.com/<owner>/<repo> of this repository.
#   vercel_projects                         "<id>\t<name>" of each project linked to the repository, by name. Nothing when none.
#   vercel_uat_projects                     the same, only the projects with the custom environment. Nothing when none.
#   vercel_use <id> <name>                  the project that the functions below act on.
#   vercel_project_name                     that project's name.
#   vercel_project_id                       that project's id.
#   vercel_project                          that project's JSON (GET /v9/projects/<id>).
#   vercel_custom_env                       the custom environment whose slug is UAT_ENVIRONMENT, or nothing.
#   vercel_deployments <target>             the 20 newest deployments for <target>: production, or a custom environment's slug.
#   vercel_deployment <target> <sha>        the newest deployment of <sha> for <target>, or nothing.
#   vercel_production_current               the id of the deployment production serves now.
#   vercel_production_domains               the project's production domains, one per line.
#   vercel_promote <deployment id>          POST promote. Prints the HTTP code.

VERCEL_API="${VERCEL_API:-https://api.vercel.com}"
if ! declare -F die >/dev/null 2>&1; then
  die() { echo "error: $*" >&2; exit 1; }
fi
# shellcheck source=lib/github.sh
source "$(dirname "${BASH_SOURCE[0]}")/github.sh"

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

vercel_repo_url() {
  local repo
  repo="$(gh_repo)" || die "the repository is not known, so its Vercel projects cannot be found"
  printf 'https://github.com/%s' "$repo"
}

vercel_projects() {
  local url repo body
  url="$(vercel_repo_url)" || exit 1
  repo="${url#https://github.com/}"
  # The read goes to a variable first, so a failed read stops the caller and never reads as no project.
  body="$(vercel_get "/v10/projects?repoUrl=$(jq -rn --arg u "$url" '$u | @uri')&limit=100")" || exit 1
  printf '%s' "$body" | jq -r --arg r "$repo" '[.projects[]
      | select(((.link.org // "") + "/" + (.link.repo // "") | ascii_downcase) == ($r | ascii_downcase))]
      | sort_by(.name) | .[] | [.id, .name] | @tsv'
}

vercel_uat_projects() {
  local list id name envs
  list="$(vercel_projects)" || exit 1
  [ -n "$list" ] || return 0
  while IFS=$'\t' read -r id name; do
    envs="$(vercel_get "/v9/projects/${id}/custom-environments")" || exit 1
    if printf '%s' "$envs" | jq -e --arg s "${UAT_ENVIRONMENT:-uat}" 'any(.environments[]?; .slug == $s)' >/dev/null; then
      printf '%s\t%s\n' "$id" "$name"
    fi
  done <<<"$list"
}

vercel_use() { # <id> <name>
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || die "vercel_use needs a project id and a name"
  _vercel_project_id="$1"
  _vercel_project_name="$2"
}

vercel_project_name() {
  [ -n "${_vercel_project_name:-}" ] || die "no Vercel project is chosen: the caller calls vercel_use first"
  printf '%s' "$_vercel_project_name"
}

vercel_project_id() {
  [ -n "${_vercel_project_id:-}" ] || die "no Vercel project is chosen: the caller calls vercel_use first"
  printf '%s' "$_vercel_project_id"
}

vercel_project() { vercel_get "/v9/projects/$(vercel_project_id)"; }

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
