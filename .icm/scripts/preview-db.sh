#!/usr/bin/env bash
# preview-db.sh — a pull request's own database: the Neon branch preview/<git branch>, cut from
# the base with its data, and its three variables on Vercel Preview, scoped to the git branch.
#
# Usage: .icm/scripts/preview-db.sh <status|create|delete> <git branch>
#
#   status   the base, the Neon branch, and DATABASE_URL, DATABASE_URL_UNPOOLED and
#            MIGRATE_AT_BUILD on Preview for the git branch, present or absent. Reads only.
#   create   the Neon branch from the base when it is absent, then the three variables when they
#            are absent, then a redeploy of the git branch's newest preview, only when this run
#            changed something. A second run changes nothing. preview-db.yml runs it.
#   delete   the Neon branch and the three variables, when they exist. Says what it found.
#            Nothing found is not an error. neon-cleanup.yml runs it.
#
# Reads: NEON_API_KEY, NEON_PROJECT_ID (the project that holds the base), VERCEL_TOKEN, and
# VERCEL_TEAM, VERCEL_PROJECT when set. The base is never written. No connection string reaches
# a terminal or a command line. The contract is .icm/database/CONTEXT.md.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { echo "error: $*" >&2; exit 1; }
usage="usage: preview-db.sh <status|create|delete> <git branch>"

case "${1:-}" in
  -h|--help) sed -n '2,17p' "${BASH_SOURCE[0]}"; exit 0 ;;
  status|create|delete) verb="$1" ;;
  *) die "unknown verb '${1:-}' ($usage)" ;;
esac
[ $# -eq 2 ] || die "$usage"
branch="$2"
[ -n "$branch" ] || die "the git branch is empty ($usage)"
[ "$branch" != main ] || die "main reads the base: it gets no preview branch"

# shellcheck source=lib/neon.sh
source "$here/lib/neon.sh"
# shellcheck source=lib/vercel.sh
source "$here/lib/vercel.sh"

name="preview/${branch}"
keys=(DATABASE_URL DATABASE_URL_UNPOOLED MIGRATE_AT_BUILD)

show_status() {
  local base id k
  base="$(neon_default_branch | jq -r '"\(.name) (\(.id))"')"
  echo "base:   $base, never written here"
  id="$(neon_branch "$name" | jq -r '.id // empty')"
  if [ -n "$id" ]; then echo "neon:   $name ($id)"; else echo "neon:   $name absent"; fi
  for k in "${keys[@]}"; do
    if [ -n "$(vercel_branch_env_find "$k" "$branch")" ]; then
      echo "vercel: $k set on Preview for $branch"
    else
      echo "vercel: $k not set on Preview for $branch"
    fi
  done
  echo "RESULT: STATUS $name $( [ -n "$id" ] && echo present || echo absent )"
}

do_create() {
  local changed=0 id base_id new db="" role="" pooled k dep url
  id="$(neon_branch "$name" | jq -r '.id // empty')"
  if [ -n "$id" ]; then
    echo "$name exists ($id)"
  else
    base_id="$(neon_default_branch | jq -r '.id // empty')"
    [ -n "$base_id" ] || die "the project has no default branch: NEON_PROJECT_ID names the wrong project"
    echo "creating $name from the base, with its data"
    new="$(neon_create_branch "$name" "$base_id")"
    id="$(printf '%s' "$new" | jq -r '.branch.id')"
    changed=1
  fi
  neon_wait_ready "$id" 180 || die "branch $id is not ready after 180 s: read it in the Neon console, then run preview-db.sh status $branch"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  for k in "${keys[@]}"; do
    # A new branch has new connection strings, so its variables are set again.
    [ "$changed" -eq 1 ] || [ -z "$(vercel_branch_env_find "$k" "$branch")" ] || continue
    case "$k" in
      MIGRATE_AT_BUILD) printf '1' > "$tmp/$k" ;;
      *)
        if [ -z "$db" ]; then
          IFS=$'\t' read -r db role < <(neon_branch_database "$id")
          [ -n "$db" ] && [ -n "$role" ] || die "branch $id has no database to connect to"
        fi
        if [ "$k" = DATABASE_URL ]; then pooled=true; else pooled=false; fi
        neon_connection_uri "$id" "$db" "$role" "$pooled" > "$tmp/$k"
        [ -s "$tmp/$k" ] || die "Neon returned no connection string for $id"
        ;;
    esac
    vercel_branch_env_upsert "$k" "$tmp/$k" "$branch"
    changed=1
  done
  rm -rf "$tmp"
  if [ "$changed" -eq 0 ]; then
    echo "RESULT: UNCHANGED $name: the branch and its three variables are in place"
    return 0
  fi
  dep="$(vercel_branch_deployment "$branch")"
  if [ -z "$dep" ]; then
    echo "no preview deployment of $branch yet: its first build reads the variables"
  else
    url="$(vercel_redeploy "$(printf '%s' "$dep" | jq -r '.uid // .id')")"
    echo "redeploy of $branch requested: $url"
  fi
  echo "RESULT: CREATED $name"
}

do_delete() {
  local id k vid found=0
  id="$(neon_branch "$name" | jq -r '.id // empty')"
  if [ -n "$id" ]; then
    neon_delete_branch "$id" "$name"
    echo "deleted $name ($id)"
    found=1
  else
    echo "$name is not in the project"
  fi
  for k in "${keys[@]}"; do
    vid="$(vercel_branch_env_find "$k" "$branch")"
    if [ -n "$vid" ]; then
      vercel_env_delete "$vid"
      found=1
    fi
  done
  if [ "$found" -eq 1 ]; then
    echo "RESULT: DELETED $name"
  else
    echo "RESULT: ABSENT $name: this pull request made no branch"
  fi
}

neon_require "the preview branch of $branch"
vercel_require "the Preview variables of $branch"
case "$verb" in
  status) show_status ;;
  create) do_create ;;
  delete) do_delete ;;
esac
