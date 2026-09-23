#!/usr/bin/env bash
# validate-knowledge-map.sh — every page `_shared/knowledge-map.md` names must exist (PROJECT-OWNED).
#
# The knowledge map is the router every stage loads to find its slice of the docs tree. A page it
# names that is not there is a stage reading nothing and believing it read something. This is the
# generic validator the template seeds: it resolves every backticked path in the map against
# `docs_path` (from `.icm/project.json`) as `<path>`, `<path>.md`, `<path>.mdx`, `<path>/page.mdx`
# or `<path>/index.md`, and lists what does not resolve. Project-owned because a real docs tree
# usually wants stricter rules (which sections count, which extensions) — sharpen it here.
#
# A `"complexity": "micro"` project (`.icm/project.json`) keeps no knowledge map worth holding to
# a docs tree — a one-page site, a script repo — so the check returns 0 before it reads anything.
#
# Usage: .icm/scripts/validate-knowledge-map.sh
# Verdict (stdout, last line): RESULT: OK 0 · RESULT: SKIP 0 (micro project, no map, or no
#   docs_path) · RESULT: INVALID exit 2 (paths that do not resolve are listed above)
set -euo pipefail

command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
die() { echo "error: $*" >&2; exit 1; }

# shellcheck source=lib/project.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/project.sh"

# Micro projects leave immediately — before the map, the docs tree or anything else is looked at.
if [ "$(project_field '.complexity' 'standard')" = "micro" ]; then
  echo "complexity is \"micro\" in .icm/project.json — no knowledge map is held for this project"
  echo "RESULT: SKIP"; exit 0
fi

map=".icm/_shared/knowledge-map.md"
docs_path="$(project_field '.docs_path' '')"
docs_path="${docs_path%/}"

[ -f "$map" ] || { echo "no $map — nothing to validate"; echo "RESULT: SKIP"; exit 0; }
[ -n "$docs_path" ] || { echo "no docs_path in .icm/project.json — the map is not checked against a tree"; echo "RESULT: SKIP"; exit 0; }
# A docs_path that is not there yet is not an error by itself — the seeded default is `docs`, and
# a map that names no page under it is still true. A page the map DOES name cannot resolve in a
# tree that does not exist, so that case falls out below as INVALID, with the paths listed.
[ -d "$docs_path" ] || echo "note: docs_path '$docs_path' (from .icm/project.json) is not a directory yet"

resolves() {
  local p="$1"
  [ -e "$docs_path/$p" ] || [ -e "$docs_path/$p.md" ] || [ -e "$docs_path/$p.mdx" ] \
    || [ -e "$docs_path/$p/page.mdx" ] || [ -e "$docs_path/$p/index.md" ]
}

checked=0; missing=()
# Backticked tokens that look like a path under the docs tree: contain a `/`, no spaces, and are
# not a script, a run folder, or a repo-level file the map may also mention.
while IFS= read -r p; do
  [ -n "$p" ] || continue
  p="${p#"$docs_path"/}"
  case "$p" in
    .icm/*|_shared/*|stages/*|lanes/*|.claude/*|.github/*|*.sh|*/\*|*\**|*\<*|http*) continue ;;
  esac
  checked=$((checked + 1))
  resolves "$p" || missing+=("$p")
done < <(grep -oE '`[^` ]+/[^` ]+`' "$map" | tr -d '`' | sort -u)

if [ "${#missing[@]}" -gt 0 ]; then
  printf 'does not resolve under %s: %s\n' "$docs_path" "${missing[@]}"
  echo "RESULT: INVALID"; exit 2
fi
echo "$checked path(s) in $map resolve under $docs_path"
echo "RESULT: OK"; exit 0
