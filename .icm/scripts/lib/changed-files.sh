#!/usr/bin/env bash
# lib/changed-files.sh — the one definition of "the files this branch changed". Sourced, not run.
#
# format.sh and lint.sh both work on CHANGED FILES ONLY — that is what makes them cheap enough to
# run in a session where the full checks are the factory's (block-local-checks.sh). Both need the
# same answer to the same question, so it lives here once:
#
#   every file that differs between the branch's fork point off <base> and the WORKING TREE
#   (committed, staged and unstaged edits alike), plus untracked files git does not ignore,
#   minus anything that no longer exists (deleted or renamed away — nothing to format or lint).
#
# The fork point (merge-base), not <base>'s tip: after <base> moves on, a tip diff would list every
# file main changed since the branch was cut, as if this branch had touched them. Requires that
# <base> resolves — in a fresh cloud session that is `origin/main`, which `git fetch` keeps current.
#
# Contract for callers (source after die() is defined):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/changed-files.sh"
#   fork="$(fork_point <base-ref>)" || exit 1
#                                prints the merge-base of <base-ref> and HEAD; dies when the ref
#                                does not resolve. Called in the caller's own shell on purpose: a
#                                die inside a process substitution would only end that subshell,
#                                and an unresolvable base would read as "no changed files".
#   changed_files <fork>         prints one repo-relative path per line, sorted, unique.
#   filter_ext <ext> [<ext>...]  stdin → stdout: keeps the lines whose extension is one of <ext>.

fork_point() {
  local base="$1"
  git rev-parse --verify --quiet "${base}^{commit}" >/dev/null \
    || die "base ref '$base' does not resolve — run 'git fetch origin' first, or pass --base <ref>"
  git merge-base "$base" HEAD \
    || die "no merge-base between '$base' and HEAD — is this branch cut from $base?"
}

changed_files() {
  local fork="$1"
  {
    git diff --name-only --diff-filter=ACMR "$fork"
    git ls-files --others --exclude-standard
  } | sort -u | while IFS= read -r f; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}

filter_ext() {
  local pattern
  pattern="\.($(IFS='|'; echo "$*"))$"
  grep -E "$pattern" || true
}
