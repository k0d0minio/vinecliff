#!/usr/bin/env bash
# rollback.sh — print the commands that put the previous release back in production.
# It runs nothing: the operator runs the commands. The contract is .icm/_system/features/uat.md.
#
# Usage: rollback.sh [--tag <v*>]
#
# The release to put back is --tag, or the release tag before the newest one. For each UAT
# project, the build is the one that promote.sh chose for that tag: the production build of
# the commit that UAT served at the tag. When UAT has no such deployment any more, it is the
# newest READY production build at or before the tag. A build of a commit after the tag is
# never a choice. A rollback changes the code, not the database.
set -euo pipefail
shopt -s inherit_errexit
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
. "$here/lib/gh.sh"
. "$here/lib/vercel.sh"
need gh git jq curl
cd "$(icm_root)"
stop() { echo "RESULT: STOP $*" >&2; exit 1; }

tag=""
[ "${1:-}" != --tag ] || tag="${2:-}"
git fetch -q --tags origin "$(default_branch)"
[ -n "$tag" ] || tag="$(git tag --list 'v*' --sort=-v:refname | sed -n 2p)"
[ -n "$tag" ] || stop "no release before the newest one: nothing to put back"
sha="$(git rev-parse -q --verify "refs/tags/$tag^{commit}")" || stop "the tag $tag is not in the repo"

list="$(vc_uat_projects)"
[ -n "$list" ] || stop "no Vercel project of $(gh_repo) has the custom environment '$(uat_slug)'"
cmds=""
while IFS=$'\t' read -r id name; do
  u="$(vc_pick "$id" "$(uat_slug)" "$sha")" d=""
  [ -z "$u" ] || d="$(vc_dep_of "$id" production "$(jq -r .meta.githubCommitSha <<<"$u")")"
  if [ -z "$d" ] || [ "$(jq -r '.state // .readyState' <<<"$d")" != READY ]; then
    d="$(vc_pick "$id" production "$sha")"
  fi
  [ -n "$d" ] || stop "$name: no READY production build at or before $tag among the 20 newest"
  cur="$(vc_current "$id")"
  dep="$(jq -r '.uid // .id' <<<"$d")"
  echo "$name: production serves ${cur:-nothing}. $tag is $dep ($(jq -r '.meta.githubCommitSha[0:7]' <<<"$d"))"
  [ "$cur" = "$dep" ] || cmds+="  vercel rollback $(jq -r .url <<<"$d")${VERCEL_TEAM:+ --scope $VERCEL_TEAM}"$'\n'
done <<<"$list"
[ -n "$cmds" ] || { echo "RESULT: NONE production serves $tag already"; exit 0; }
echo "The commands, for the operator, one for each project:"
printf '%s' "$cmds"
echo "The database does not go back. The code of $tag must work with the schema of now."
echo "RESULT: PREPARED $tag"
