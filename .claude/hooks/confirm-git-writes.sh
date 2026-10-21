#!/usr/bin/env bash
# confirm-git-writes.sh — global PreToolUse(Bash) guard.
# Home: ~/.claude/hooks/confirm-git-writes.sh, registered in ~/.claude/settings.json.
#
# Doctrine: this machine runs in auto mode, and CLAUDE.md declares outward git work
# autonomous — "your job ends at git push", PRs open without asking. So the ordinary loop
# (add, commit, push a feature branch, open the PR) runs free and silent.
#
# Four things still stop and ask, because they are not recoverable by another commit:
#   1. History rewrites      — rebase, amend, reset --hard, filter-branch, reflog expire
#   2. Force / destructive push — --force, --force-with-lease, --mirror, --delete, +refspec
#   3. Pushing the default branch — main/master, whether named explicitly or as the
#                                   currently checked-out branch of a bare `git push`
#   4. Merge or release      — gh pr merge, gh release create; the house boundary says
#                              never merge or release, so the human makes that call
# Everything else git does — add, commit, ordinary push, fetch, merge, stash, checkout,
# switch, restore, branch, tag, worktree, config, gh pr create — is auto-approved.
# `worktree` and `config` are deliberately NOT guarded: the built-in worktree flow
# (worktree.baseRef "fresh") drives git worktree itself, and `git config --get` is a read.
#
# This hook exists because permission rules match a command prefix only, so a compound
# invocation (`cd apps/web && git push --force`) slips past them. The hook inspects the
# whole command string and forces the prompt on any segment.
#
# Contract: reads the PreToolUse payload on stdin, inspects tool_input.command and cwd.
#   exit 0, no output          → defer to normal permission resolution (also the fail-open
#                                path on malformed/empty input or a missing jq).
#   exit 0 + permissionDecision "ask" → force the confirmation prompt.
# It matches at a command-segment boundary (start, ; , && , || , | ) and strips heredoc
# bodies, so a git verb inside a quoted string — `git log --grep "force"`, or a commit
# message mentioning "rebase" — is never caught.
set -euo pipefail

# Defer to a repo-owned copy of this guard, matching block-local-checks.sh: the repo
# defines its own semantics and registers the hook itself.
# The same file may run as that repo copy: defer only when the repo copy is another file.
repo_copy="${CLAUDE_PROJECT_DIR:-}/.claude/hooks/confirm-git-writes.sh"
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$repo_copy" ] \
  && [ "$(realpath "$repo_copy" 2>/dev/null)" != "$(realpath "$0" 2>/dev/null)" ]; then
  exit 0
fi

input="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || exit 0            # no jq → can't parse → fail open
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
[ -n "$cmd" ] || exit 0
cwd="$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null || true)"

# Heredoc bodies are data, not commands — drop everything from the first heredoc marker on.
# (A `gh pr create --body <<EOF` body mentioning "force push" must not trip this.)
cmd="${cmd%%<<*}"
[ -n "$cmd" ] || exit 0

b='(^|[;&|(])[[:space:]]*'                                  # command-segment boundary
# `git`, optionally carrying global flags that precede the subcommand: -C <dir>, -c k=v,
# --git-dir=…, --work-tree=… . Without this, `git -C apps/web push` reads as a non-match.
git='git([[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+|--(git-dir|work-tree|namespace)=[^[:space:]]+|-c[[:space:]]+[^[:space:]]+))*[[:space:]]+'
seg='[^;&|]*'                                               # rest of this command segment

hit=""

# ── 1. History rewrites ───────────────────────────────────────────────────────────────
printf '%s' "$cmd" | grep -Eq "${b}${git}(rebase|filter-branch|filter-repo)([[:space:]]|$|[;&|)])" \
  && hit="history rewrite"
printf '%s' "$cmd" | grep -Eq "${b}${git}commit${seg}[[:space:]]--amend([[:space:]=]|$|[;&|)])" \
  && hit="history rewrite (commit --amend)"
printf '%s' "$cmd" | grep -Eq "${b}${git}reset${seg}[[:space:]]--hard([[:space:]=]|$|[;&|)])" \
  && hit="destructive reset --hard"
printf '%s' "$cmd" | grep -Eq "${b}${git}reflog[[:space:]]+expire" && hit="history rewrite (reflog expire)"
printf '%s' "$cmd" | grep -Eq "${b}${git}update-ref([[:space:]]|$)" && hit="history rewrite (update-ref)"
# Force branch delete / rename: -D, -M, --delete --force. Plain -d on a merged branch and
# every read-only flag (--list, --show-current, -a, -r, -v) stay auto-approved.
printf '%s' "$cmd" | grep -Eq "${b}${git}branch${seg}[[:space:]]-[a-zA-Z]*[DM]([[:space:]]|$|[;&|)])" \
  && hit="force branch delete/rename"

# ── 2. Force / destructive push ───────────────────────────────────────────────────────
pushforce='(--force([-a-z]*)?|-[a-zA-Z]*f|--mirror|--delete|-[a-zA-Z]*d)([[:space:]=]|$|[;&|)])'
printf '%s' "$cmd" | grep -Eq "${b}${git}push${seg}[[:space:]]${pushforce}" && hit="force/destructive push"
# `git push origin +main` — the leading + is a force refspec.
printf '%s' "$cmd" | grep -Eq "${b}${git}push${seg}[[:space:]]\+[^[:space:]]+" && hit="force push (+refspec)"

# ── 3. Pushing the default branch ─────────────────────────────────────────────────────
dfl='(main|master|trunk)'
# Named explicitly: `git push origin main`, `git push origin HEAD:main`, `git push -u origin main`
printf '%s' "$cmd" | grep -Eq "${b}${git}push${seg}[[:space:]](${dfl}|[^[:space:]]*:${dfl})([[:space:]]|$|[;&|)])" \
  && hit="push to default branch"
# Implicit: a push that names no refspec, while the checked-out branch IS the default
# branch. A push that DOES name one (`git push -u origin feature/x`) is already fully
# judged by the explicit rule above — re-checking HEAD there would flag every feature
# push made while main happens to be checked out elsewhere in the worktree.
explicit_refspec=0
# Everything after the `push` verb, up to the end of this command segment. Counted by
# hand rather than captured from $git, whose own groups would shift a sed backreference.
pushargs="$(printf '%s' "$cmd" | sed -E 's/.*[[:space:]]push([[:space:]]|$)/ /; s/[;&|].*//' || true)"
n=0
for tok in $pushargs; do
  case "$tok" in -*) continue ;; esac
  n=$((n + 1))
done
[ "$n" -ge 2 ] && explicit_refspec=1
if [ -z "$hit" ] && [ "$explicit_refspec" -eq 0 ] && printf '%s' "$cmd" | grep -Eq "${b}${git}push([[:space:]]|$|[;&|)])"; then
  # Honour `git -C <dir>`; otherwise resolve against the session cwd.
  d="$(printf '%s' "$cmd" | grep -oE "${git}push" | grep -oE -- '-C[[:space:]]+[^[:space:]]+' | head -1 | sed -E 's/^-C[[:space:]]+//' || true)"
  [ -n "$d" ] || d="$cwd"
  if [ -n "$d" ] && [ -d "$d" ]; then
    br="$(git -C "$d" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    case "$br" in main|master|trunk) hit="push to default branch ($br)" ;; esac
  fi
fi

# ── gh: merge, release, and the irreversible ones ─────────────────────────────────────
# `gh pr create` / `edit` / `ready` are autonomous. Merging and releasing reach the estate,
# and deleting a repo or a published release is not recoverable, so those check in.
printf '%s' "$cmd" | grep -Eq "${b}gh[[:space:]]+pr[[:space:]]+merge" && hit="gh pr merge"
printf '%s' "$cmd" | grep -Eq "${b}gh[[:space:]]+release[[:space:]]+create" && hit="gh release create"
printf '%s' "$cmd" | grep -Eq "${b}gh[[:space:]]+(repo|release)[[:space:]]+delete" && hit="gh delete (irreversible)"

[ -n "$hit" ] || exit 0

reason="Checking in first ($hit): on this machine the ordinary git loop — add, commit, \
push a feature branch, open the PR — runs without asking. Only the operations that another \
commit cannot undo stop here: history rewrites, force/destructive pushes, pushes to the \
default branch, merges and releases. Confirm if that is what you intended."

jq -nc --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $r
  }
}'
exit 0
