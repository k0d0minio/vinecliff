#!/usr/bin/env bash
# check.sh — the checks of the CI jobs icm-check and icm-gate-read. Only --gate-report uses
# the network.
#
# Usage:
#   check.sh                    icm-check: verify _system/, the pointer files, and updates
#   check.sh --gate             print the state of the Ready to merge tick. Exit 1: not ticked
#   check.sh --gate-report      icm-gate-read: write the check run icm-gate on the head commit
#                               (GITHUB_REPOSITORY, HEAD_SHA, GH_TOKEN). Not ticked: the
#                               conclusion is action_required, "Waits for the operator". It
#                               is a wait, not a failure. Ticked, or no gate: success
#   check.sh --write-manifest   write MANIFEST.sha256. Only Copier runs this, at a render
#
# icm-check fails when:
#   1. a file below .icm/_system/ does not match MANIFEST.sha256, or is not in it. The
#      manifest also has the three guards of .claude/hooks/ that the blueprint owns
#      (1.0.0-rc18): a guard that was changed in the repo, or that is absent, is a fault
#   2. a pointer file does not point to .icm/_system/, or .claude/settings.json does not
#      register one of the three guards
#   3. a pull request changes .icm/_system/ or a guard and does not change
#      .icm/_system/VERSION
#   4. a client request of .icm/requests/ breaks the form of features/requests.md
#      (1.0.0-rc27): check-request.sh names each fault
# The gate is the box below <!-- gate:ready-to-merge -->. A body with no such anchor
# passes: the gate is not required there. merge.sh refuses while the box is not ticked.
set -euo pipefail
# Copier runs --write-manifest in the folder that it renders. The CI jobs run in the repo.
[ "${1:-}" = --write-manifest ] || cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
sys=".icm/_system"
manifest="$sys/MANIFEST.sha256"
. "$sys/scripts/lib/gh.sh"

# The guards are in .claude/hooks/, because .claude/settings.json registers them there.
guards=".claude/hooks/block-local-checks.sh .claude/hooks/confirm-git-writes.sh .claude/hooks/guard-plaintext-secrets.sh"

files() {
  {
    find "$sys" -type f ! -name MANIFEST.sha256
    for g in $guards; do [ ! -f "$g" ] || echo "$g"; done
  } | LC_ALL=C sort
}

if [ "${1:-}" = --write-manifest ]; then
  files | xargs -d '\n' sha256sum > "$manifest"
  echo "icm: wrote $manifest ($(wc -l < "$manifest") files)"
  exit 0
fi

if [ "${1:-}" = --gate ] || [ "${1:-}" = --gate-report ]; then
  if [ -n "${PR_BODY:-}" ]; then
    body="$PR_BODY"
  else
    body="$(jq -r '.pull_request.body // ""' "${GITHUB_EVENT_PATH:?no pull request event}")"
  fi
  state="$(printf '%s\n' "$body" | gate_state ready-to-merge)"
  if [ "$1" = --gate-report ]; then
    conclusion=success title="Ready to merge is ticked"
    [ "$state" != none ] || title="This pull request has no Ready to merge gate"
    if [ "$state" = no ]; then
      conclusion=action_required title="Waits for the operator: Ready to merge is not ticked"
    fi
    url="https://github.com/${GITHUB_REPOSITORY:?}/pull/${PR_NUMBER:-}"
    gh api -X POST "repos/${GITHUB_REPOSITORY}/check-runs" -f name=icm-gate -f head_sha="${HEAD_SHA:?}" \
      -f status=completed -f conclusion="$conclusion" -f details_url="$url" \
      -f "output[title]=$title" \
      -f "output[summary]=The operator ticks Ready to merge after the test. Until the tick this check waits. It is not a failure." \
      >/dev/null || { echo "icm-gate-read: the check run icm-gate was not written"; exit 1; }
    echo "icm-gate: $conclusion. $title."
    exit 0
  fi
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
    || fault "a file below $sys/ or a guard of .claude/hooks/ was changed in this repo. They belong to the blueprint: $(sha256sum -c "$manifest" 2>/dev/null | grep -v ': OK$' | head -n 5 | tr '\n' ' ')"
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
for g in $guards; do pointer .claude/settings.json "$g"; done

# 3. In a pull request, a change of _system/ comes only with a new version.
if [ -n "${GITHUB_BASE_REF:-}" ]; then
  # shellcheck disable=SC2086  # the list of the guards is three words
  changed="$(git diff --name-only "origin/${GITHUB_BASE_REF}...HEAD" -- "$sys" $guards 2>/dev/null || true)"
  if [ -n "$changed" ] && ! grep -qxF "$sys/VERSION" <<<"$changed"; then
    fault "this pull request changes $sys/ or a guard of .claude/hooks/, and not $sys/VERSION. Only a blueprint update changes them"
  fi
fi

# 4. Each client request has the form of features/requests.md (1.0.0-rc27).
if compgen -G ".icm/requests/REQ-*.md" >/dev/null; then
  out="$(bash "$sys/scripts/check-request.sh" .icm/requests/REQ-*.md 2>&1)" \
    || fault "a client request breaks the form of $sys/features/requests.md: $(grep '^fault:' <<<"$out" | tr '\n' ' ')"
fi

if [ "$faults" -gt 0 ]; then
  echo "icm-check: $faults fault(s)."
  exit 1
fi
echo "icm-check: OK. Blueprint $(cat "$sys/VERSION")."
