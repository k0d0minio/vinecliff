#!/usr/bin/env bash
# check.sh — the checks of the CI jobs icm-check and icm-gate. It needs no network.
#
# Usage:
#   check.sh                    icm-check: verify _system/, the pointer files, and updates
#   check.sh --gate             icm-gate: verify the Ready to merge tick of the pull request
#   check.sh --write-manifest   write MANIFEST.sha256. Only Copier runs this, at a render
#
# icm-check fails when:
#   1. a file below .icm/_system/ does not match MANIFEST.sha256, or is not in it
#   2. a pointer file does not point to .icm/_system/
#   3. a pull request changes .icm/_system/ and does not change .icm/_system/VERSION
# icm-gate fails when the box below <!-- gate:ready-to-merge --> is not ticked. A body with
# no such anchor passes: the gate is not required there.
set -euo pipefail
# Copier runs --write-manifest in the folder that it renders. The CI jobs run in the repo.
[ "${1:-}" = --write-manifest ] || cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
sys=".icm/_system"
manifest="$sys/MANIFEST.sha256"
. "$sys/scripts/lib/gh.sh"

files() { find "$sys" -type f ! -name MANIFEST.sha256 | LC_ALL=C sort; }

if [ "${1:-}" = --write-manifest ]; then
  files | xargs -d '\n' sha256sum > "$manifest"
  echo "icm: wrote $manifest ($(wc -l < "$manifest") files)"
  exit 0
fi

if [ "${1:-}" = --gate ]; then
  if [ -n "${PR_BODY:-}" ]; then
    body="$PR_BODY"
  else
    body="$(jq -r '.pull_request.body // ""' "${GITHUB_EVENT_PATH:?no pull request event}")"
  fi
  state="$(printf '%s\n' "$body" | gate_state ready-to-merge)"
  case "$state" in
    yes) echo "icm-gate: Ready to merge is ticked." ;;
    none) echo "icm-gate: this pull request has no Ready to merge gate." ;;
    *) echo "icm-gate: Ready to merge is not ticked. The operator ticks it after the test."; exit 1 ;;
  esac
  exit 0
fi

faults=0
fault() {
  echo "icm-check: $*"
  faults=$((faults + 1))
}

# 1. The folder matches the manifest.
if [ ! -f "$manifest" ]; then
  fault "$manifest is missing. Render the blueprint again"
else
  sha256sum --quiet -c "$manifest" >/dev/null 2>&1 \
    || fault "a file below $sys/ was changed in this repo. The folder belongs to the blueprint: $(sha256sum -c "$manifest" 2>/dev/null | grep -v ': OK$' | head -n 5 | tr '\n' ' ')"
  extra="$(comm -13 <(sed -E 's/^[0-9a-f]+  //' "$manifest" | LC_ALL=C sort) <(files))"
  [ -z "$extra" ] || fault "files below $sys/ that the blueprint did not write: $(tr '\n' ' ' <<<"$extra")"
fi

# 2. The pointer files point to _system/.
pointer() {
  if [ ! -f "$1" ]; then
    fault "the pointer file $1 is missing"
  elif ! grep -qF -- "$2" "$1"; then
    fault "$1 must contain: $2"
  fi
}
pointer CLAUDE.md '@.icm/_system/ROUTER.md'
pointer .claude/settings.json '.icm/_system/hooks/dispatch.sh'
pointer .claude/skills/pipeline/SKILL.md '.icm/_system/ROUTER.md'
pointer .claude/agents/review-shots.md '.icm/_system/agents/review-shots/CONTEXT.md'
pointer .github/workflows/icm.yml '.icm/_system/ci/check.sh'

# 3. In a pull request, a change of _system/ comes only with a new version.
if [ -n "${GITHUB_BASE_REF:-}" ]; then
  changed="$(git diff --name-only "origin/${GITHUB_BASE_REF}...HEAD" -- "$sys" 2>/dev/null || true)"
  if [ -n "$changed" ] && ! grep -qxF "$sys/VERSION" <<<"$changed"; then
    fault "this pull request changes $sys/ and not $sys/VERSION. Only a blueprint update changes that folder"
  fi
fi

if [ "$faults" -gt 0 ]; then
  echo "icm-check: $faults fault(s)."
  exit 1
fi
echo "icm-check: OK. Blueprint $(cat "$sys/VERSION")."
