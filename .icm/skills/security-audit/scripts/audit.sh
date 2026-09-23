#!/usr/bin/env bash
# audit.sh — the security-audit skill's Level-3 runnable: the Release-pass scan, summarised.
# Wraps .icm/scripts/security-check.sh (the gate) — no logic of its own. Invoke as:
#   bash .icm/skills/security-audit/scripts/audit.sh <slug> [--all]
set -uo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$repo_root"
slug="${1:-}"; scope="--branch"
[ "${2:-}" = "--all" ] && scope="--all"
out="$(.icm/scripts/security-check.sh ${slug:+"$slug"} "$scope" --audit 2>&1)"; rc=$?
printf '%s\n' "$out"
echo "-------------------------------------------------"
found="$(printf '%s\n' "$out" | grep -c '^\s*\[FOUND\]' || true)"
warns="$(printf '%s\n' "$out" | grep -c '^\s*\[WARN\]' || true)"
echo "security-audit: $found finding(s), $warns check(s) that could not run — verdict: $(printf '%s\n' "$out" | tail -1)"
[ "$rc" -eq 0 ] && echo "stop class 2 input: nothing introduced by this branch was found by the gate — the review still reads the diff" \
                 || echo "stop class 2 input: the gate BLOCKED — follow .icm/skills/security-audit/SKILL.md → On BLOCKED before any merge"
exit "$rc"
