#!/usr/bin/env bash
# wrap-reminder.sh — canonical estate hook (icm-board _system/template/claude/hooks/).
# Stop hook. Two questions, each asked once, neither ever acted on:
#
#   1. Uncommitted .icm/ changes — the board reads main, so an unpushed stub does not
#      exist.
#   2. Work shipped, stub left open — this branch has commits that changed files outside
#      .icm/, and an open stub matches the work (the branch is named for its slug, or a
#      legacy ticket ID appears in a commit subject), while no commit on the branch
#      touched that stub's file. The estate rule (the pr-conventions skill) is that the
#      PR finishing a stub's work moves it to its _done/; nothing ever verified it, so
#      tickets drifted open while their work merged.
#
# The second question is deliberately narrow. A commit touching only .icm/ is ticket
# administration, not work; and a branch that touched the stub file at all has already
# engaged with it. It asks; it never moves a stub. Gates are human checkboxes. Honours
# stop_hook_active so it can never loop, and is silent (exit 0) on any error, outside a
# repo, or where there is no origin/main to compare against.
set -uo pipefail

input="$(cat 2>/dev/null || true)"
# Already continued once because of us — let the session end.
if printf '%s' "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

repo="${CLAUDE_PROJECT_DIR:-.}"
command -v git >/dev/null 2>&1 || exit 0
git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# ── 1. uncommitted ticket work ───────────────────────────────────────────────
dirty="$(git -C "$repo" status --porcelain -- .icm 2>/dev/null || true)"
if [[ -n "$dirty" ]]; then
  cat <<'JSON'
{"decision": "block", "reason": "Uncommitted changes under .icm/ — the tickets board reads main, so unpushed ticket work does not exist. Wrap per the estate discipline: cut what's left into .icm/intake/ (epics or triage), then commit only .icm/ paths (message 'Plan: …' or 'Wrap: …') and push — or tell Jamie it is being left deliberately."}
JSON
  exit 0
fi

# ── 2. work shipped, stub left open ──────────────────────────────────────────
git -C "$repo" rev-parse --verify -q origin/main >/dev/null 2>&1 || exit 0
head_sha="$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)"
base="$(git -C "$repo" merge-base origin/main HEAD 2>/dev/null || true)"
# Nothing on this branch that origin/main does not already have.
[[ -n "$head_sha" && -n "$base" && "$base" != "$head_sha" ]] || exit 0

# Did any commit here change something outside .icm/? If not, it's ticket admin only.
worked=0
while read -r sha; do
  [[ -n "$sha" ]] || continue
  if git -C "$repo" show --pretty=format: --name-only "$sha" 2>/dev/null \
    | grep -qvE '^(\.icm/|$)'; then worked=1; break; fi
done < <(git -C "$repo" log --format='%H' "$base..HEAD" 2>/dev/null || true)
(( worked )) || exit 0

# Stub files this branch touched at all — any engagement buys silence.
touched="$(git -C "$repo" diff --name-only "$base..HEAD" -- .icm/intake 2>/dev/null || true)"

open=()

# (a) The branch slug: claude/<slug> (with or without a trailing -hash segment).
branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
slug="${branch#claude/}"
if [[ -n "$slug" && "$slug" != "$branch" ]]; then
  trimmed="$(sed -E 's/-[a-z0-9]{4,8}$//' <<<"$slug")"
  for cand in "$slug" "$trimmed"; do
    [[ -n "$cand" ]] || continue
    for f in "$repo"/.icm/intake/*/"$cand".md; do
      [[ -e "$f" ]] || continue
      case "$f" in */_done/*) continue ;; esac
      rel="${f#"$repo"/}"
      grep -qF "$rel" <<<"$touched" && continue
      open+=("${rel#.icm/intake/}")
    done
    (( ${#open[@]} )) && break
  done
fi

# (b) Legacy ticket IDs named by commit subjects (pre-migration repos).
while read -r sha subject; do
  [[ -n "$sha" ]] || continue
  git -C "$repo" show --pretty=format: --name-only "$sha" 2>/dev/null \
    | grep -qvE '^(\.icm/|$)' || continue
  while read -r id; do
    [[ -n "$id" ]] || continue
    compgen -G "$repo/.icm/intake/${id}-*.md" >/dev/null 2>&1 || continue
    grep -q "/${id}-" <<<"$touched" && continue
    open+=("$id")
  done < <(grep -oE '[A-Z]{2,}-[0-9]+' <<<"$subject" | sort -u || true)
done < <(git -C "$repo" log --format='%H %s' "$base..HEAD" 2>/dev/null || true)

(( ${#open[@]} )) || exit 0

list="$(printf '%s, ' "${open[@]}")"; list="${list%, }"
printf '{"decision": "block", "reason": "Work on this branch matches %s, still open in .icm/intake/ and untouched by any commit here. The estate rule (pr-conventions): the PR that finishes a stub'"'"'s work moves it to its _done/. Move it in this branch if the work is done, or tell Jamie why it stays open."}\n' "$list"
exit 0
