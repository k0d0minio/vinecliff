#!/usr/bin/env bash
# client-status.sh — the client's view of this project, compiled from the pipeline's own files (TEMPLATE-OWNED).
#
# Four questions a client asks, answered without a meeting and without reading a PR:
#   1. Delivered to production    runs archived on main — the squash-merge, or the UAT promotion, is
#                                 what put them there — newest first, with the date they landed.
#   2. Ready to try on UAT        only where the repo declares a UAT environment (.icm/project.json →
#                                 uat; .icm/uat/CONTEXT.md): the batch on the UAT branch (its
#                                 .icm/uat/batch.json), the one fixed address to open, and whether the
#                                 client has signed the batch off.
#   3. Currently being worked on  stubs spun out of an epic whose run has not merged yet (an epic's
#                                 _done/ minus the archive) and lane work picked up from triage; with
#                                 a GitHub route, the open pipeline PRs name each item's stage.
#   4. Queued next                the epics with stubs still to spin out, in build order, plus a count
#                                 of the smaller items parked in triage.
#
# It writes ONE markdown file, .icm/output/client-status-latest.md, in plain words: the work items'
# own titles, never a slug, a branch, a SHA or a check name. Chores, promotions and runs announced
# `internal` are left out unless --all. It reads git refs first — origin/main for what shipped and
# what is queued (the board reads main; a live run exists only on its own branch until it merges),
# origin/<uat.branch> for the batch — and the working tree where a ref is not there, and says which
# at the foot of the file. GitHub is optional: without a route every live item reads "in progress".
#
# Deterministic for a given repo state and --today. Reads only; nothing is sent, nothing is
# committed. Whether the report is committed is the repo's call — on main it is what a dashboard
# can read; regenerated on demand it is a working file. NOT a repo check: the block-local-checks
# hook does not match it, and it runs in seconds. Every repo carries it (decision D31) — a UAT
# environment is not needed for the report, only for its second section.
#
# Usage:
#   .icm/scripts/client-status.sh [--out <path>] [--stdout] [--all] [--limit <n>] [--today YYYY-MM-DD]
#                                 [--no-fetch] [--no-github]
# Verdict (stdout, last line — with --stdout the report itself is the output and nothing follows):
#   RESULT: WRITTEN <path> — <d> delivered · <u> on UAT · <b> in progress · <q> queued   exit 0
#   (exit 2 on usage, or jq/git missing)
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root" || exit 2
die() { echo "error: $*" >&2; exit 2; }
command -v jq  >/dev/null 2>&1 || die "jq not found"
command -v git >/dev/null 2>&1 || die "git not found"

out=".icm/output/client-status-latest.md"; to_stdout=0; all=0; limit=10; today=""; fetch=1; use_github=1
while [ $# -gt 0 ]; do
  case "$1" in
    --out)       out="${2:-}"; [ -n "$out" ] || die "--out needs a path"; shift 2 ;;
    --stdout)    to_stdout=1; shift ;;
    --all)       all=1; shift ;;
    --limit)     limit="${2:-}"; printf '%s' "$limit" | grep -Eq '^[0-9]+$' || die "--limit must be an integer"; shift 2 ;;
    --today)     today="${2:-}"; printf '%s' "$today" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || die "--today must be YYYY-MM-DD"; shift 2 ;;
    --no-fetch)  fetch=0; shift ;;
    --no-github) use_github=0; shift ;;
    -h|--help)   sed -n '2,34p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown argument: $1 (usage: client-status.sh [--out <path>] [--stdout] [--all] [--limit <n>] [--today YYYY-MM-DD] [--no-fetch] [--no-github])" ;;
  esac
done
[ -n "$today" ] || today="$(date -u +%F)"

# shellcheck source=lib/project.sh
source "$here/lib/project.sh"
archive="$runs_archive_rel"; intake=".icm/intake"; intake_archive="$intake_archive_rel"
project="$(project_field .name)"; [ -n "$project" ] || project="$(basename "$repo_root")"

# --- which refs to read -------------------------------------------------------------------------------
in_git=0; git rev-parse --is-inside-work-tree >/dev/null 2>&1 && in_git=1
if [ "$in_git" -eq 1 ] && [ "$fetch" -eq 1 ] && git remote get-url origin >/dev/null 2>&1; then
  GIT_TERMINAL_PROMPT=0 git fetch origin --quiet >/dev/null 2>&1 || echo "note: git fetch origin failed — reading the refs as last fetched" >&2
fi
main_ref=""; [ "$in_git" -eq 1 ] && git rev-parse --verify -q origin/main >/dev/null 2>&1 && main_ref="origin/main"
uat_on=0; uat_ref=""; ub=""; uu=""
if uat_declared; then
  uat_on=1; ub="$(uat_branch)"; uu="$(uat_url)"
  [ "$in_git" -eq 1 ] && git rev-parse --verify -q "origin/$ub" >/dev/null 2>&1 && uat_ref="origin/$ub"
fi
sources="${main_ref:-the working tree}"
[ "$uat_on" -eq 1 ] && sources="$sources; the UAT batch from ${uat_ref:-the working tree}"

# --- readers: a ref when there is one, the working tree otherwise ------------------------------------------
read_at()    { if [ -n "$1" ]; then git show "$1:$2" 2>/dev/null; else [ -f "$2" ] && cat "$2"; fi; return 0; }
exists_at()  { if [ -n "$1" ]; then git cat-file -e "$1:$2" 2>/dev/null; else [ -e "$2" ]; fi; }
ls_dirs_at() { # <ref> <dir> → entry names of the sub-folders
  if [ -n "$1" ]; then git ls-tree --name-only -d "$1:${2%/}" 2>/dev/null
  else local d; for d in "$2"/*/; do [ -d "$d" ] && basename "$d"; done; fi
  return 0
}
ls_md_at() { # <ref> <dir> → the *.md file names at the top of <dir>
  if [ -n "$1" ]; then git ls-tree --name-only "$1:${2%/}" 2>/dev/null | grep -E '\.md$'
  else local f; for f in "$2"/*.md; do [ -f "$f" ] && basename "$f"; done; fi
  return 0
}

# --- text helpers (mawk-compatible) -------------------------------------------------------------------------
h1_title() { awk '/^# / { sub(/^# +/, ""); sub(/^[A-Za-z]+: +/, ""); print; exit }'; }
section()  { awk -v h="$1" '$0 ~ "^## +" h "[[:space:]]*$" { g = 1; next } g && /^## / { exit } g { print }'; }
dash() { # <field> ; stdin → the first '- <field>: <value>' (continuation lines joined)
  awk -v want="$1" '
    !grab && $0 ~ "^-[[:space:]]+" want ":" { v = substr($0, index($0, ":") + 1); grab = 1; next }
    grab && /^[[:space:]]+[^[:space:]]/ { v = v " " $0; next }
    grab { exit }
    END { gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); gsub(/[[:space:]]+/, " ", v); print v }'
}
one_liner() { # stdin → the first sentence, markdown stripped, at most 180 characters
  tr '\n' ' ' | sed -E 's/\[([^]]*)\]\([^)]*\)/\1/g; s/[`*_]//g; s/<[^>]*>//g' \
    | awk '{ s = $0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); gsub(/[[:space:]]+/, " ", s)
             i = index(s, ". "); if (i > 0) s = substr(s, 1, i)
             if (length(s) > 180) s = substr(s, 1, 177) "…"; print s }'
}
strip_path_prefix() { # "apps/web/x.tsx: what changed" → "what changed"
  sed -E 's#^[^ :]*[/.][^ :]*:[[:space:]]+##'
}
humanise() { # a-kebab-slug → "A kebab slug"
  printf '%s' "$1" | sed -E 's/[-_]+/ /g' | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }'
}
retired() { printf '%s\n' "$1" | grep -qE '^> *Dropped:|^- *superseded-by:'; }

# --- one run's client-facing facts --------------------------------------------------------------------------
# Sets ri_title, ri_line, ri_lane, ri_internal. Returns 1 for a front (Scope's folder — not a
# deliverable). Stage folders are globbed by suffix, so an older archive (03_define/04_build) reads
# the same as the current one (02_define/03_build).
ri_title=""; ri_line=""; ri_lane=""; ri_internal=0
run_info() { # <ref> <dir> <slug>
  local ref="$1" dir="$2" slug="$3" run_md lane spec="" notes="" lnotes="" sub f
  ri_title=""; ri_line=""; ri_internal=0; ri_lane="feature"
  run_md="$(read_at "$ref" "$dir/run.md")"
  lane="$(printf '%s\n' "$run_md" | dash lane)"; [ -n "$lane" ] || lane="feature"
  ri_lane="$lane"
  [ "$lane" = "front" ] && return 1
  if [ "$lane" = "feature" ] && printf '%s\n' "$run_md" | grep -q '^- story:' && ! printf '%s\n' "$run_md" | grep -qE '^- pr:'; then return 1; fi
  while IFS= read -r sub; do
    [ -n "$sub" ] || continue
    case "$sub" in
      *define) [ -n "$spec" ]  || spec="$(read_at "$ref" "$dir/$sub/output/spec.md")" ;;
      *build)  [ -n "$notes" ] || notes="$(read_at "$ref" "$dir/$sub/output/notes.md")" ;;
      lane)    lnotes="$(read_at "$ref" "$dir/lane/output/notes.md")" ;;
    esac
  done < <(ls_dirs_at "$ref" "$dir")
  if [ -n "$spec" ]; then
    ri_title="$(printf '%s\n' "$spec" | h1_title)"
    ri_line="$(printf '%s\n' "$spec" | section "Proposed change" | one_liner)"
  fi
  if [ -z "$ri_title" ] && [ -n "$lnotes" ]; then
    for f in change fix observed invariant incident handover; do
      ri_line="$(printf '%s\n' "$lnotes" | dash "$f")"; [ -n "$ri_line" ] && break
    done
    ri_line="$(printf '%s\n' "$ri_line" | strip_path_prefix | one_liner)"
  fi
  [ -n "$ri_title" ] || ri_title="$(humanise "$slug")"
  case "$lane" in chore|promote) ri_internal=1 ;; esac
  printf '%s\n%s\n' "$notes" "$lnotes" | grep -qiE '^[[:space:]]*-?[[:space:]]*(announce|audience):[[:space:]]*internal' && ri_internal=1
  return 0
}

# --- 1. delivered: the archive on main, dated by the commit that added each folder -------------------------
declare -A ddate=() on_main=()
log_ref="$main_ref"; [ -n "$log_ref" ] || { [ "$in_git" -eq 1 ] && log_ref="HEAD"; }
if [ -n "$log_ref" ]; then
  d=""
  while IFS= read -r line; do
    case "$line" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) d="$line" ;;
      "$archive"/*) s="${line#"$archive"/}"; s="${s%%/*}"; [ -n "${ddate[$s]:-}" ] || ddate[$s]="$d" ;;
    esac
  done < <(git log --format='%cs' --no-renames --diff-filter=A --name-only "$log_ref" -- "$archive" 2>/dev/null)
fi
deliv_rows=()
while IFS= read -r slug; do
  [ -n "$slug" ] || continue
  on_main[$slug]=1
  run_info "$main_ref" "$archive/$slug" "$slug" || continue
  [ "$ri_internal" -eq 1 ] && [ "$all" -eq 0 ] && continue
  deliv_rows+=("$(printf '%s\t%s\t%s\t%s' "${ddate[$slug]:-0000-00-00}" "$slug" "$ri_title" "$ri_line")")
done < <(ls_dirs_at "$main_ref" "$archive")
deliv_sorted=""
[ "${#deliv_rows[@]}" -eq 0 ] || deliv_sorted="$(printf '%s\n' "${deliv_rows[@]}" | sort -t"$(printf '\t')" -k1,1r -k2,2)"
deliv_n="${#deliv_rows[@]}"

# --- 2. the UAT batch, as the UAT branch holds it ---------------------------------------------------------
declare -A in_uat=()
uat_rows=(); approved="false"; approved_by=""; approved_on=""
if [ "$uat_on" -eq 1 ]; then
  bj="$(read_at "$uat_ref" ".icm/uat/batch.json")"
  printf '%s' "$bj" | jq -e . >/dev/null 2>&1 || bj='{}'
  approved="$(printf '%s' "$bj" | jq -r '.client_approved // false')"
  approved_by="$(printf '%s' "$bj" | jq -r '.approved_by // ""')"
  approved_on="$(printf '%s' "$bj" | jq -r '.approved_on // ""')"
  while IFS= read -r slug; do
    [ -n "$slug" ] || continue
    in_uat[$slug]=1
    if exists_at "$uat_ref" "$archive/$slug/run.md" && run_info "$uat_ref" "$archive/$slug" "$slug"; then :
    else ri_title="$(humanise "$slug")"; ri_line=""; ri_internal=0; fi
    [ "$ri_internal" -eq 1 ] && [ "$all" -eq 0 ] && continue
    uat_rows+=("$(printf '%s\t%s\t%s' "$slug" "$ri_title" "$ri_line")")
  done < <(printf '%s' "$bj" | jq -r '(.stubs // [])[] | if type == "object" then (.slug // empty) else . end')
  # Archived on the UAT branch, not on main, not in the batch: it IS on UAT — list it, and say so.
  if [ -n "$uat_ref" ]; then
    while IFS= read -r slug; do
      [ -n "$slug" ] || continue
      [ -n "${on_main[$slug]:-}" ] && continue
      [ -n "${in_uat[$slug]:-}" ] && continue
      run_info "$uat_ref" "$archive/$slug" "$slug" || continue
      in_uat[$slug]=1
      [ "$ri_internal" -eq 1 ] && [ "$all" -eq 0 ] && continue
      echo "[WARN] $slug is archived on $ub but not on main and not in .icm/uat/batch.json — listed under UAT; promote-uat.sh status shows the same gap" >&2
      uat_rows+=("$(printf '%s\t%s\t%s' "$slug" "$ri_title" "$ri_line")")
    done < <(ls_dirs_at "$uat_ref" "$archive")
  fi
fi
uat_n="${#uat_rows[@]}"

# --- 3. in progress: spun out, not merged — and the open PRs' stages when GitHub answers -----------------
declare -A p_title=() p_stage=() p_epic=() p_lane=()
p_order=()
add_progress() { # <slug> <title> <stage> <epic-title> <lane>
  [ -n "${p_title[$1]:-}" ] && return 0
  p_order+=("$1"); p_title[$1]="$2"; p_stage[$1]="$3"; p_epic[$1]="$4"; p_lane[$1]="$5"
}
lane_words() { case "$1" in bug) echo "being fixed" ;; tweak) echo "being adjusted" ;; hotfix) echo "urgent fix in progress" ;; handover) echo "handover in progress" ;; *) echo "in progress" ;; esac; }
while IFS= read -r epic; do
  [ -n "$epic" ] || continue
  case "$epic" in _done) continue ;; esac
  [ "$intake/$epic" = "$intake_archive" ] && continue
  if [ "$epic" = "triage" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue; slug="${f%.md}"
      [ -n "${on_main[$slug]:-}" ] || [ -n "${in_uat[$slug]:-}" ] && continue
      stub="$(read_at "$main_ref" "$intake/triage/_done/$f")"
      retired "$stub" && continue
      lane="$(printf '%s\n' "$stub" | dash lane)"
      t="$(printf '%s\n' "$stub" | h1_title)"; [ -n "$t" ] || t="$(humanise "$slug")"
      add_progress "$slug" "$t" "$(lane_words "$lane")" "" "$lane"
    done < <(ls_md_at "$main_ref" "$intake/triage/_done")
    continue
  fi
  etitle="$(read_at "$main_ref" "$intake/$epic/breakdown.md" | h1_title)"; [ -n "$etitle" ] || etitle="$(humanise "$epic")"
  while IFS= read -r f; do
    [ -n "$f" ] || continue; slug="${f%.md}"
    [ -n "${on_main[$slug]:-}" ] || [ -n "${in_uat[$slug]:-}" ] && continue
    stub="$(read_at "$main_ref" "$intake/$epic/_done/$f")"
    retired "$stub" && continue
    t="$(printf '%s\n' "$stub" | h1_title)"; [ -n "$t" ] || t="$(humanise "$slug")"
    add_progress "$slug" "$t" "in progress" "$etitle" "feature"
  done < <(ls_md_at "$main_ref" "$intake/$epic/_done")
done < <(ls_dirs_at "$main_ref" "$intake")

gh_note="stages not read (no GitHub route in this environment)"
if [ "$use_github" -eq 0 ]; then gh_note="stages not read (--no-github)"
elif [ "$in_git" -eq 1 ] && git remote get-url origin >/dev/null 2>&1; then
  # shellcheck source=lib/gh.sh
  if source "$here/lib/gh.sh" 2>/dev/null && { [ -n "${gh_token:-}" ] || (command -v gh >/dev/null 2>&1 && env -u GITHUB_TOKEN -u GH_TOKEN gh auth status >/dev/null 2>&1); }; then
    resp="$(gh_api GET "/repos/${repo}/pulls?state=open&per_page=100" 2>/dev/null)" || resp=""
    if [ "$(printf '%s' "$resp" | tail -n1)" = "200" ]; then
      gh_note="stages from the open pull requests"
      while IFS="$(printf '\t')" read -r num title draft labels slug; do
        [ -n "$slug" ] || continue
        stage="in progress"; lane="feature"
        case ",$labels," in
          *,type:promote,*)  continue ;;
          *,type:chore,*)    lane="chore" ;;
          *,type:bug,*)      lane="bug" ;;
          *,type:tweak,*)    lane="tweak" ;;
          *,type:hotfix,*)   lane="hotfix" ;;
          *,type:handover,*) lane="handover" ;;
        esac
        case ",$labels," in
          *,stage:release,*) stage="in final checks" ;;
          *,stage:build,*)   stage="being built" ;;
          *,stage:define,*)  stage="being specified" ;;
          *) [ "$lane" = "feature" ] || stage="$(lane_words "$lane")" ;;
        esac
        [ "$draft" = "false" ] && [ "$lane" = "feature" ] && [ "$stage" = "being built" ] && stage="built, being checked"
        if [ -n "${p_title[$slug]:-}" ]; then p_stage[$slug]="$stage"
        else
          [ -n "${on_main[$slug]:-}" ] || [ -n "${in_uat[$slug]:-}" ] && continue
          case "$title" in "$slug"|"") title="$(humanise "$slug")" ;; esac
          add_progress "$slug" "$title" "$stage" "" "$lane"
        fi
      done < <(printf '%s' "$resp" | sed '$d' | jq -r '
        def slug_of: ((.body // "") | split("\n") | map(sub("\r$"; ""))
          | map((capture("^\\s*- slug:\\s*(?<s>[^\\s]+)") | .s), (capture("^\\|\\s*\\*\\*Slug\\*\\*\\s*\\|\\s*`?(?<s>[^`| ]+)`?") | .s))
          | first // "");
        .[] | select((.body // "") | contains("PIPELINE RUN"))
          | [.number, (.title // ""), (.draft | tostring), ((.labels // []) | map(.name) | join(",")), slug_of] | @tsv' 2>/dev/null)
    else gh_note="stages not read (GitHub did not answer)"; fi
  fi
fi
prog_n=0
for slug in "${p_order[@]+"${p_order[@]}"}"; do
  [ "${p_lane[$slug]}" = "chore" ] && [ "$all" -eq 0 ] && continue
  prog_n=$((prog_n + 1))
done

# --- 4. queued: the epics with stubs still to spin out, in build order --------------------------------------
queue_md=""; queued_n=0
while IFS= read -r epic; do
  [ -n "$epic" ] || continue
  case "$epic" in triage|_done) continue ;; esac
  [ "$intake/$epic" = "$intake_archive" ] && continue
  rows=()
  while IFS= read -r f; do
    [ -n "$f" ] || continue; [ "$f" = "breakdown.md" ] && continue
    stub="$(read_at "$main_ref" "$intake/$epic/$f")"
    retired "$stub" && continue
    seq="$(printf '%s\n' "$stub" | dash sequence | grep -oE '^[0-9]+' || true)"; [ -n "$seq" ] || seq=999
    t="$(printf '%s\n' "$stub" | h1_title)"; [ -n "$t" ] || t="$(humanise "${f%.md}")"
    pr="$(printf '%s\n' "$stub" | dash priority)"
    blocked="$(printf '%s\n' "$stub" | dash blocked)"
    mark=""; [ "$pr" = "P0" ] && mark=" _(priority)_"; [ -n "$blocked" ] && mark="$mark _(waiting on: $blocked)_"
    rows+=("$(printf '%s\t%s%s' "$seq" "$t" "$mark")")
  done < <(ls_md_at "$main_ref" "$intake/$epic")
  [ "${#rows[@]}" -gt 0 ] || continue
  etitle="$(read_at "$main_ref" "$intake/$epic/breakdown.md" | h1_title)"; [ -n "$etitle" ] || etitle="$(humanise "$epic")"
  queue_md="$queue_md"$'\n'"**$etitle**"$'\n'
  queue_md="$queue_md$(printf '%s\n' "${rows[@]}" | sort -t"$(printf '\t')" -k1,1n | awk -F'\t' '{ printf "%d. %s\n", NR, $2 }')"$'\n'
  queued_n=$((queued_n + ${#rows[@]}))
done < <(ls_dirs_at "$main_ref" "$intake")
triage_n="$(ls_md_at "$main_ref" "$intake/triage" | wc -l | tr -d ' ')"

# --- render ---------------------------------------------------------------------------------------------------
{
  printf '# %s — where things stand\n\n' "$project"
  printf '_%s_ · %s delivered · ' "$today" "$deliv_n"
  [ "$uat_on" -eq 1 ] && printf '%s ready on UAT · ' "$uat_n"
  printf '%s in progress · %s queued\n\n' "$prog_n" "$queued_n"

  printf '## Delivered to production\n\n'
  if [ "$deliv_n" -eq 0 ]; then printf '_Nothing has shipped to production yet._\n\n'
  else
    printf '%s\n' "$deliv_sorted" | head -n "$limit" | while IFS="$(printf '\t')" read -r d slug t l; do
      when="on $d"; [ "$d" = "0000-00-00" ] && when="date not recorded"
      if [ -n "$l" ]; then printf -- '- **%s** — %s _(%s)_\n' "$t" "$l" "$when"; else printf -- '- **%s** _(%s)_\n' "$t" "$when"; fi
    done
    if [ "$deliv_n" -gt "$limit" ]; then printf -- '- _…and %s earlier — ask for the full list._\n' "$((deliv_n - limit))"; fi
    printf '\n'
  fi

  if [ "$uat_on" -eq 1 ]; then
    printf '## Ready for you to try on UAT\n\n'
    if [ -n "$uu" ]; then printf 'Open **%s** — everything below is live there, together, on one address that does not change.\n\n' "$uu"
    else printf 'The UAT address is not recorded yet — ask for it. Everything below is live there, together.\n\n'; fi
    if [ "$uat_n" -eq 0 ]; then printf '_Nothing is waiting on UAT right now._\n\n'
    else
      for row in "${uat_rows[@]}"; do
        IFS="$(printf '\t')" read -r slug t l <<<"$row"
        if [ -n "$l" ]; then printf -- '- **%s** — %s\n' "$t" "$l"; else printf -- '- **%s**\n' "$t"; fi
      done
      printf '\n'
      if [ "$approved" = "true" ]; then
        printf '_Signed off by %s on %s — this batch goes to production as one release next._\n\n' "${approved_by:-the client}" "${approved_on:-a recorded date}"
      else
        printf '_Awaiting your sign-off: when the batch looks right as a whole, say so and it goes to production as one release. Anything that is not right goes back before anything ships._\n\n'
      fi
    fi
  fi

  printf '## Currently being worked on\n\n'
  if [ "$prog_n" -eq 0 ]; then printf '_Nothing is in progress right now._\n\n'
  else
    for slug in "${p_order[@]}"; do
      [ "${p_lane[$slug]}" = "chore" ] && [ "$all" -eq 0 ] && continue
      if [ -n "${p_epic[$slug]}" ]; then printf -- '- **%s** — %s _(part of: %s)_\n' "${p_title[$slug]}" "${p_stage[$slug]}" "${p_epic[$slug]}"
      else printf -- '- **%s** — %s\n' "${p_title[$slug]}" "${p_stage[$slug]}"; fi
    done
    printf '\n'
  fi

  printf '## Queued next\n'
  if [ "$queued_n" -eq 0 ]; then printf '\n_The queue is empty — new work starts with a conversation._\n'
  else printf '%s' "$queue_md"; fi
  if [ "$triage_n" -gt 0 ]; then printf '\n_Plus %s smaller fix(es) and adjustment(s) parked, picked up in the flow._\n' "$triage_n"; fi
  printf '\n---\n\n'
  printf '_Compiled by the project'"'"'s own pipeline on %s from its records (%s; %s). Titles are the work items'"'"' own names — ask for detail on any line._\n' "$today" "$sources" "$gh_note"
} > "${TMPDIR:-/tmp}/client-status.$$"

if [ "$to_stdout" -eq 1 ]; then
  cat "${TMPDIR:-/tmp}/client-status.$$"; rm -f "${TMPDIR:-/tmp}/client-status.$$"; exit 0
fi
mkdir -p "$(dirname "$out")"
mv "${TMPDIR:-/tmp}/client-status.$$" "$out"
summary="$deliv_n delivered"
[ "$uat_on" -eq 1 ] && summary="$summary · $uat_n on UAT"
echo "RESULT: WRITTEN $out — $summary · $prog_n in progress · $queued_n queued"
exit 0
