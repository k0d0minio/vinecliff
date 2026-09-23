#!/usr/bin/env bash
# lib/vercel.sh — the one Vercel transport for the pipeline scripts. Sourced, not run (except --check).
#
# What lib/gh.sh is to GitHub, this is to Vercel: curl + the token named by the repo's own deploy
# block (`.icm/project.json` → deploy.token_env — lib/project.sh), falling back to plain
# VERCEL_TOKEN exactly as the cloud hydrate hook does. Every Vercel READ a template-owned script
# makes — deploy-status.sh, env.sh audit, rollback.sh's lookup of the previous deployment,
# setup.sh's route check — goes through here. NO WRITE VERB LIVES IN THIS FILE: the two Vercel
# writes the pipeline knows about (`vercel env add`, the rollback endpoint) are made by the
# Vercel CLI from a human's stdin (env.sh add) or printed for a human to run (rollback.sh). A
# script that needs to change Vercel does not get a helper for it here.
#
# Nothing outside the repo is read: no registry, no icm-board, no `~/Apps`. The projects, the
# team and the token's NAME come from the deploy block; the token's VALUE comes from the
# process environment and never reaches argv (curl reads its config from stdin) or stdout.
#
# Contract for callers (source after die() is defined and lib/project.sh is sourced):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/vercel.sh"
#     → sets VERCEL_API (default https://api.vercel.com), vercel_team (deploy.team_slug),
#       vercel_token_name (deploy.token_env, else VERCEL_TOKEN) and vercel_token (its value, or
#       empty). Nothing is fetched at source time.
#   vercel_declared                  returns 0 when deploy.projects has at least one entry.
#   vercel_require "<why>"           die NOW when no token is set — before any side effect.
#   vercel_get <path> [<query>]      GET <path> (relative to VERCEL_API); the team is appended as
#                                    `teamId=<slug>` when declared. Prints "<body>\n<http_code>".
#   vercel_project <name>            GET /v9/projects/<name> → the project JSON (dies on non-200).
#   vercel_deployments <name> [--target production|preview] [--sha <sha>] [--limit n]
#                                    GET /v6/deployments filtered to the project (by its id),
#                                    newest first → the `deployments` array as JSON.
#   vercel_deployment <id>           GET /v13/deployments/<id> → one deployment's JSON.
#   vercel_env_list <name>           GET /v9/projects/<id>/env → one line per variable:
#                                    key<TAB>type<TAB>targets(csv). Names, targets, kinds —
#                                    never a decrypted value; `decrypt=false` is not even asked.
#   vercel_project_id <name>         the project's id (cached per call in this shell).
#
# Standalone check:
#   .icm/scripts/lib/vercel.sh --check   GET /v9/projects for the team through the same logic;
#                                        RESULT: OK (exit 0) · SKIP (no deploy block) · the die
#                                        message (exit 1).

declare -F die >/dev/null 2>&1 || die() { echo "error: $*" >&2; exit 1; }

_vercel_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=project.sh
declare -F project_field >/dev/null 2>&1 || source "$_vercel_here/project.sh"

VERCEL_API="${VERCEL_API_URL:-https://api.vercel.com}"
vercel_team="$(deploy_team)"
vercel_token_name="$(deploy_token_env)"
vercel_token="${!vercel_token_name:-}"
if [ -z "$vercel_token" ] && [ "$vercel_token_name" != "VERCEL_TOKEN" ]; then
  # The hydrate hook's rule: plain VERCEL_TOKEN is what a cloud panel sets.
  vercel_token="${VERCEL_TOKEN:-}"
  [ -z "$vercel_token" ] || vercel_token_name="VERCEL_TOKEN"
fi

vercel_declared() { project_has '.deploy.projects'; }

vercel_require() { # <why>
  vercel_declared || die "no deploy block in .icm/project.json — declare deploy.projects before ${1:-this call} (setup.sh asks for it)"
  [ -n "$vercel_token" ] || die "no Vercel token in this environment for ${1:-this call}: set ${vercel_token_name} (the name the deploy block names — or plain VERCEL_TOKEN); never pass it as an argument"
}

# curl reads its configuration from stdin so the token never appears in argv (`ps`) — the same
# idiom as the hydrate hook and icm-board's vercel-env.sh.
vercel_get() { # <path> [<query>]
  local path="$1" query="${2:-}" url
  url="${VERCEL_API}${path}"
  if [ -n "$vercel_team" ]; then
    query="${query:+$query&}teamId=${vercel_team}"
  fi
  [ -z "$query" ] || url="${url}?${query}"
  printf 'url = "%s"\nheader = "Authorization: Bearer %s"\nwrite-out = "\\n%%{http_code}"\nmax-time = 30\nsilent\nshow-error\n' \
    "$url" "$vercel_token" | curl --config - 2>/dev/null
}

_vercel_body() { printf '%s' "$1" | sed '$d'; }
_vercel_code() { printf '%s' "$1" | tail -n1; }

vercel_project() { # <name>
  local resp http
  resp="$(vercel_get "/v9/projects/$1")" || die "could not reach ${VERCEL_API} for project '$1'"
  http="$(_vercel_code "$resp")"
  [ "$http" = "200" ] || die "GET /v9/projects/$1 answered HTTP $http via ${vercel_token_name}${vercel_team:+ (team $vercel_team)}: $(_vercel_body "$resp" | jq -r '.error.message // empty' 2>/dev/null)"
  _vercel_body "$resp"
}

vercel_project_id() { # <name>
  vercel_project "$1" | jq -r '.id // empty'
}

vercel_deployments() { # <name> [--target t] [--sha s] [--limit n]
  local name="$1"; shift
  local target="" sha="" limit=20 id q resp http
  while [ $# -gt 0 ]; do
    case "$1" in
      --target) target="${2:-}"; shift 2 ;;
      --sha)    sha="${2:-}"; shift 2 ;;
      --limit)  limit="${2:-20}"; shift 2 ;;
      *) die "vercel_deployments: unknown flag $1" ;;
    esac
  done
  id="$(vercel_project_id "$name")"
  [ -n "$id" ] || die "project '$name' has no id in Vercel's answer"
  q="projectId=${id}&limit=${limit}"
  [ -z "$target" ] || q="${q}&target=${target}"
  [ -z "$sha" ]    || q="${q}&sha=${sha}"
  resp="$(vercel_get "/v6/deployments" "$q")" || die "could not list deployments for '$name'"
  http="$(_vercel_code "$resp")"
  [ "$http" = "200" ] || die "GET /v6/deployments for '$name' answered HTTP $http: $(_vercel_body "$resp" | jq -r '.error.message // empty' 2>/dev/null)"
  _vercel_body "$resp" | jq -c '.deployments // []'
}

vercel_deployment() { # <id>
  local resp http
  resp="$(vercel_get "/v13/deployments/$1")" || die "could not read deployment $1"
  http="$(_vercel_code "$resp")"
  [ "$http" = "200" ] || die "GET /v13/deployments/$1 answered HTTP $http"
  _vercel_body "$resp"
}

vercel_env_list() { # <name>  → key \t type \t targets
  local id resp http
  id="$(vercel_project_id "$1")"
  [ -n "$id" ] || die "project '$1' has no id in Vercel's answer"
  resp="$(vercel_get "/v9/projects/${id}/env")" || die "could not list env for '$1'"
  http="$(_vercel_code "$resp")"
  [ "$http" = "200" ] || die "GET /v9/projects/<id>/env for '$1' answered HTTP $http"
  # `.envs[]` carries key, type (plain|encrypted|sensitive|secret|system) and target[] — and a
  # `value` field this function never prints and never asks to decrypt.
  _vercel_body "$resp" | jq -r '(.envs // [])[] | [.key, (.type // ""), ((.target // []) | join(","))] | @tsv'
}

# --- standalone: `lib/vercel.sh --check` --------------------------------------------------------------

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  [ "${1:-}" = "--check" ] || die "usage: .icm/scripts/lib/vercel.sh --check   (this file is otherwise sourced by the pipeline scripts)"
  command -v curl >/dev/null || die "curl not found"
  command -v jq >/dev/null || die "jq not found"
  if ! vercel_declared; then
    echo "deploy not declared in .icm/project.json — nothing to check"
    echo "RESULT: SKIP"; exit 0
  fi
  vercel_require "the route check"
  echo "token: ${vercel_token_name} set; team: ${vercel_team:-<none>}; api: $VERCEL_API" >&2
  resp="$(vercel_get "/v9/projects" "limit=5")"
  http="$(_vercel_code "$resp")"
  [ "$http" = "200" ] || die "GET /v9/projects answered HTTP $http via ${vercel_token_name}: $(_vercel_body "$resp" | jq -r '.error.message // "no message"' 2>/dev/null)"
  n="$(_vercel_body "$resp" | jq '.projects | length')"
  echo "GET /v9/projects → 200 ($n project(s) visible to this token${vercel_team:+ on $vercel_team})"
  echo "RESULT: OK"
fi
