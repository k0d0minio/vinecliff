#!/usr/bin/env bash
# route-request.sh — UserPromptSubmit router: names the contract to follow for each prompt.
# The blueprint renders it into every build, never into a workspace. It speaks only where
# .icm/intake/CONTEXT.md exists. The contracts it names are the loop (.icm/intake/CONTEXT.md),
# the lanes (.icm/lanes/<lane>/CONTEXT.md) and, where it exists, .icm/uat/CONTEXT.md.
#
# Deterministic, under 100 ms, no model (modelled on block-local-checks.sh): reads the
# UserPromptSubmit payload on stdin, looks at the prompt, and injects ONE additionalContext
# line. It reads files only: no git, no gh. Each process costs time, so the matching uses bash
# builtins where it can: [[ =~ ]] with an explicit word boundary in place of grep's \b. A
# common prompt starts two jq processes and few others. Two kinds of line:
#
#   [router] Route: <the contract to read and the command to run> (<why>)
#       Directive. Emitted for a bare form — `new`, `new <slug>`, `build <slug>`,
#       `revise <slug> ["<change>"]`, `merge <slug>|<number>`, `release`,
#       `bug|tweak|chore <slug>|<free text>`, `hotfix <text>`, `plan|scope <text>`,
#       `promote [status|approve <who>|run <tag>]` — or for work-shaped text that names nothing
#       that exists (write the stub first), or for a multi-feature dump (cut an epic).
#       The session reads that contract before anything else, unless the user's own prompt
#       overrides it.
#   [router] Suggest: <a lane, or the forms for a named stub> (<why>)
#       Advisory. The bug / tweak / chore classifiers are heuristics. The session says the
#       lane it takes, and the user can change it.
#
# A slug is one kebab-case token, or <epic>/<slug>, or triage/<slug>. It resolves against
# .icm/intake/ in four tiers (resolve_slug): an open epic stub, an open triage stub, a started
# stub in any _done/, a stub in a closed epic in .icm/intake/_done/.
#
# A slash command is never touched. A skill's own raw body (its YAML frontmatter, `---` then
# `name: …`) is silenced too: it is instruction content being read, not a fresh request. A
# user-typed `/<name>` already exits above (Claude Code delivers that literal text, not the
# expanded body — verified against code.claude.com/docs/en/{hooks,skills}.md, 2026-09-28), so
# this is a defensive backstop for whatever harness or resumed-session path resubmits the
# expansion instead. A prompt that contains .icm/intake/ or new-run.sh is already routed: the
# desk's start prompt and a stub's own prompt. Pure questions, analysis requests, webhook and
# event payloads and short conversational prompts stay silent.
# Re-verify with .claude/hooks/route-request.test.sh. check.yml in the blueprint runs it.
#
# Contract:
#   exit 0 always — this hook NEVER blocks (never exits 2). Fail-open on any malformed input.
#   stdout on a match: {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"…"}}
#   stdout otherwise: nothing.
set -Eeuo pipefail
trap 'exit 0' ERR

IFS= read -r -d '' input || true
command -v jq >/dev/null 2>&1 || exit 0            # no jq → can't parse → stay silent
prompt="$(printf '%s' "$input" | jq -r '.prompt // ""' 2>/dev/null || true)"
[ -n "$prompt" ] || exit 0

# Slash commands are already routed.
case "$prompt" in /*) exit 0 ;; esac

# A skill or slash-command's own raw file — its YAML frontmatter (`---` then `name: …`) — is
# not a fresh request; trim leading blank lines first so a wrapped/re-submitted body still
# matches.
nl=$'\n'
trimmed="$prompt"
while [ "${trimmed:0:1}" = "$nl" ]; do trimmed="${trimmed#"$nl"}"; done
line1="${trimmed%%"$nl"*}"; line2="${trimmed#*"$nl"}"; line2="${line2%%"$nl"*}"
if [ "$line1" = "---" ] && [[ $line2 =~ ^name:[[:space:]] ]]; then
  exit 0
fi

# Webhook / injected-event payloads are not user requests — remote and desktop sessions (pull
# request watching, task notifications, CI and side-session events) deliver them as prompts;
# classifying them produces stray lane hints. Stay silent.
case "$prompt" in
  *"<github-webhook-activity>"*|*"<untrusted_external_data"*|*"<task-notification"*) exit 0 ;;
  *"<ci-monitor-event"*|*"<side-sessions-event"*) exit 0 ;;
esac

# The desk's start prompt and a stub's own prompt name the ticket and the script already.
case "$prompt" in *".icm/intake/"*|*"new-run.sh"*) exit 0 ;; esac

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
intake="$root/.icm/intake"
# No ticket contract in this repo → nothing to route to.
[ -f "$intake/CONTEXT.md" ] || exit 0
uat=0
[ -f "$root/.icm/uat/CONTEXT.md" ] && uat=1

emit() {
  jq -cn --arg ctx "[router] $1" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
  exit 0
}
route() { emit "Route: $1 This line comes from .claude/hooks/route-request.sh. A Route: line names the contract to read before anything else. The user's own prompt overrides it."; }
suggest() { emit "Suggest: $1 This line comes from .claude/hooks/route-request.sh. A Suggest: line is advisory. Say the lane you take. The user can change it."; }

loop=".icm/intake/CONTEXT.md"

# One lowercased copy for matching (first 2000 chars is plenty and keeps the matching fast).
# bash 3.2 (macOS) has no ${p,,}: tr does it there.
p="${prompt:0:2000}"
if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then p="${p,,}"; else p="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"; fi

# A word boundary for [[ =~ ]], portable where \b is not: start or a non-word character before,
# a non-word character or the end after.
B='(^|[^a-z0-9_])'
E='([^a-z0-9_]|$)'
has() { [[ $p =~ $1 ]]; }

# --- resolve_slug: where a slug lives, if anywhere ------------------------------------------------

# resolve_slug <token> → returns 0 and sets $tier and $hits (the relative paths, one per line)
# for the first tier with a hit. Tiers: open (an epic stub), triage (an open triage stub),
# started (a stub in any _done/), shipped (a stub in a closed epic). `breakdown` is never a slug.
tier=""; hits=""
resolve_slug() {
  local tok="$1" ep="*" s="$1" f
  case "$tok" in */*) ep="${tok%%/*}"; s="${tok#*/}" ;; esac
  tier=""; hits=""
  [ "$s" != "breakdown" ] || return 1
  for f in "$intake"/$ep/"$s.md"; do
    [ -f "$f" ] || continue
    case "${f#"$intake"/}" in triage/*|_done/*) continue ;; esac
    hits="${hits:+$hits
}${f#"$root"/}"
  done
  [ -z "$hits" ] || { tier=open; return 0; }
  case "$ep" in
    "*"|triage) [ -f "$intake/triage/$s.md" ] && { tier=triage; hits=".icm/intake/triage/$s.md"; return 0; } ;;
  esac
  for f in "$intake"/$ep/_done/"$s.md"; do
    [ -f "$f" ] || continue
    case "${f#"$intake"/}" in _done/*) continue ;; esac
    hits="${hits:+$hits
}${f#"$root"/}"
  done
  [ -z "$hits" ] || { tier=started; return 0; }
  for f in "$intake"/_done/$ep/"$s.md" "$intake"/_done/$ep/_done/"$s.md"; do
    [ -f "$f" ] || continue
    hits="${hits:+$hits
}${f#"$root"/}"
  done
  [ -z "$hits" ] || { tier=shipped; return 0; }
  return 1
}

# The paths in $hits, on one line.
hit_list() { printf '%s' "$hits" | tr '\n' ',' | sed 's/,/, /g'; }
many() { [ "$(printf '%s\n' "$hits" | wc -l)" -gt 1 ]; }
# The branch of the one hit: triage/<slug> for a triage stub, <slug> for an epic stub.
branch_of() {
  local f="$hits" s
  s="${f##*/}"; s="${s%.md}"
  case "$f" in .icm/intake/triage/*) printf 'triage/%s' "$s" ;; *) printf '%s' "$s" ;; esac
}
# The ticket of the one open hit, as new-run.sh takes it: <epic>/<slug> or triage/<slug>.
ticket_of() {
  local f="${hits#.icm/intake/}"
  printf '%s' "${f%.md}"
}
# The lane line of the one hit, or nothing.
lane_of() { sed -n 's/^- lane:[[:space:]]*\([a-z]*\).*/\1/p' "$root/$hits" 2>/dev/null | head -n1 || true; }

# The open stubs for `new <slug>` not found: 5 at most. P0 stubs first, then the others. In
# each group, the epic order of .icm/intake/README.md § Order (triage is one line of it), then
# the epics it does not name by folder name. In an epic by sequence, in triage by file name.
open_list() {
  local order files=() f
  order="$(sed -n '/^## Order/,/^## /p' "$intake/README.md" 2>/dev/null \
    | sed -n 's/^[0-9][0-9]*\.[[:space:]]*`\{0,1\}\([a-z0-9-]*\).*/\1/p' | tr '\n' ' ' || true)"
  for f in "$intake"/*/*.md; do
    [ -f "$f" ] || continue
    case "${f#"$intake"/}" in _done/*|*/breakdown.md) continue ;; esac
    files+=("$f")
  done
  [ "${#files[@]}" -gt 0 ] || return 0
  awk -v order="$order" -v base="$intake/" '
    FNR == 1 { n++; name[n] = FILENAME }
    /^- priority:/ { pr[FILENAME] = $3 }
    /^- sequence:/ { sq[FILENAME] = $3 + 0 }
    END {
      k = split(order, o, " ")
      for (i = 1; i <= k; i++) rank[o[i]] = i
      for (i = 1; i <= n; i++) {
        f = name[i]; rel = substr(f, length(base) + 1); sub(/\.md$/, "", rel)
        ep = rel; sub(/\/.*/, "", ep)
        r = (ep in rank) ? rank[ep] : 999
        p0 = (pr[f] == "P0") ? 0 : 1
        printf "%d\t%03d\t%s\t%06d\t%s%s\n", p0, r, ep, sq[f] + 0, rel, (p0 ? "" : " (P0)")
      }
    }' "${files[@]}" | sort | cut -f5 | head -n 5 | tr '\n' ',' | sed 's/,$//; s/,/, /g'
  printf '\t%s' "${#files[@]}"
}

# The words for a slug that is not in this checkout. A lane's triage stub can live on its branch
# only: the lane does not commit it to main.
not_here() {
  printf "no stub named %s in this checkout. A lane's triage stub can live on its branch only: look for the branch %s or triage/%s. No branch: stop and say so." "$1" "${1##*/}" "${1##*/}"
}

# --- layer 1: bare forms (deterministic file lookups, no heuristics) ------------------------------

# Normalise: collapse whitespace, drop trailing punctuation, so `New`, `new.` and `build x ` match.
bare="${p//[[:space:]]/ }"
while [[ $bare == *"  "* ]]; do bare="${bare//  / }"; done
bare="${bare# }"
while [[ $bare == *[\ .!] ]]; do bare="${bare%?}"; done
first_word="${bare%% *}"
rest="${bare#"$first_word"}"; rest="${rest# }"
slug="${rest%% *}"; after="${rest#"$slug"}"; after="${after# }"
is_slug=0
if [[ $slug =~ ^([a-z0-9]+(-[a-z0-9]+)*/)?[a-z0-9]+(-[a-z0-9]+)*$ ]]; then is_slug=1; fi
# A slug with a hyphen or a slash is a name. A plain word that resolves nowhere is conversation.
named=0
case "$slug" in *-*|*/*) named=1 ;; esac

case "$first_word" in
  # `new` → the next stub. `new <slug>` → that stub, or the list to ask from.
  new)
    if [ -z "$rest" ]; then
      route "$loop § The loop, step 1: take the next stub in the order of .icm/intake/README.md § Order, then start it with .icm/scripts/new-run.sh (bare new)."
    elif [ "$is_slug" -eq 1 ] && [ -z "$after" ]; then
      if resolve_slug "$slug"; then
        if many; then
          route "two or more stubs carry the slug $slug: $(hit_list). Ask which one, then run .icm/scripts/new-run.sh <epic>/<slug> ($loop § The loop, step 2)."
        fi
        case "$tier" in
          open) route "read the stub $hits, then run .icm/scripts/new-run.sh $(ticket_of) ($loop § The loop, step 2). When the branch $(branch_of) exists, new-run.sh refuses: resume at step 0." ;;
          triage)
            lane="$(lane_of)"
            route "the open triage stub $hits. Read .icm/lanes/${lane:-<its lane>}/CONTEXT.md, then run .icm/scripts/new-run.sh $(ticket_of) (the lane line of the stub)." ;;
          started) route "$hits is started. Resume at $loop § The loop, step 0, on the branch $(branch_of). No branch and no pull request: it shipped. Say so." ;;
          shipped) route "$hits is in a closed epic: it shipped. Start nothing. Say so." ;;
        esac
      elif [ "$named" -eq 1 ]; then
        list="$(open_list)"; tab="$(printf '\t')"; names="${list%"$tab"*}"; total="${list##*"$tab"}"
        if [ -n "$names" ]; then
          route "no open stub named $slug. The first open stubs, P0 first, then the epic order ($((total < 5 ? total : 5)) of $total): $names. Ask which one. Start nothing before the answer."
        else
          route "no open stub named $slug, and no open stub at all. Say so. Start nothing."
        fi
      fi
    fi
    ;;
  # `build <slug>` → resume a started ticket, or stop. `revise <slug> ["<change>"]` → § Revise.
  build|revise)
    if [ "$is_slug" -eq 1 ] && { [ -z "$after" ] || [ "$first_word" = "revise" ]; }; then
      if [ "$first_word" = "build" ]; then
        what="resume at $loop § The loop, step 0"
      else
        what="$loop § Revise, with the change after the slug"
      fi
      if resolve_slug "$slug"; then
        if many; then route "two or more stubs carry the slug $slug: $(hit_list). Ask which one."; fi
        case "$tier" in
          shipped) route "$hits is in a closed epic: it shipped. Change nothing. Say so." ;;
          *) route "$what, on the branch $(branch_of): read the stub, the pull request body and its gates. No branch and no pull request: stop and say so ($hits)." ;;
        esac
      elif [ "$named" -eq 1 ]; then
        route "$(not_here "$slug")"
      fi
    fi
    ;;
  # `merge <number>` or `merge <slug>` → merge.sh after the tick, then one read of ci on main.
  merge)
    if [ -z "$after" ] && [[ $slug =~ ^[0-9]+$ ]]; then
      route "run .icm/scripts/merge.sh $slug ($loop § The loop, step 7). It refuses without the Ready to merge tick. Then read ci on main once and say what moved."
    elif [ "$is_slug" -eq 1 ] && [ -z "$after" ]; then
      if resolve_slug "$slug"; then
        if many; then route "two or more stubs carry the slug $slug: $(hit_list). Ask which one."; fi
        case "$tier" in
          shipped) route "$hits is in a closed epic: it shipped. Merge nothing. Say so." ;;
          *) route "find the pull request with gh pr view $(branch_of) --json number, then run .icm/scripts/merge.sh <number> ($loop § The loop, step 7). It refuses without the Ready to merge tick. Then read ci on main once and say what moved ($hits)." ;;
        esac
      elif [ "$named" -eq 1 ]; then
        route "$(not_here "$slug")"
      fi
    fi
    ;;
  # `release` → release.sh on Jamie's word. It takes no argument.
  release)
    if [ -z "$rest" ]; then
      if [ "$uat" -eq 1 ]; then
        route "run .icm/scripts/release.sh ($loop § After the tick). This build has UAT: the merge makes the tag and moves nothing. Read .icm/uat/CONTEXT.md § The promotion for the next step."
      else
        route "run .icm/scripts/release.sh ($loop § After the tick). The merge makes the tag and the changelog. Production already follows main."
      fi
    fi
    ;;
  # `<lane> <arg>` — the argument is a triage stub name (one token) or a fresh report.
  bug|tweak|chore)
    if [ -z "$rest" ]; then
      :  # bare verb, no argument — conversation, not a form
    elif [ "$is_slug" -eq 1 ] && [ -z "$after" ]; then
      if resolve_slug "$slug"; then
        if many; then route "two or more stubs carry the slug $slug: $(hit_list). Ask which one."; fi
        case "$tier:$hits" in
          triage:*) route ".icm/lanes/$first_word/CONTEXT.md with the open triage stub $hits. Run .icm/scripts/new-run.sh $(ticket_of) (explicit lane verb)." ;;
          started:.icm/intake/triage/*) route "$hits is started. Resume at $loop § The loop, step 0, on the branch $(branch_of). No branch and no pull request: it shipped. Say so." ;;
          *) route "$hits is not an open triage stub. Ask: a fresh report, or a mistyped name. For an epic stub, the forms are new, build, revise and merge." ;;
        esac
      elif [ "$named" -eq 1 ]; then
        route "no triage stub named $slug. Ask: a fresh report for .icm/lanes/$first_word/CONTEXT.md, or a mistyped name. Start nothing before the answer."
      fi
    else
      # Free text after an explicit lane verb: a fresh report.
      route ".icm/lanes/$first_word/CONTEXT.md with a fresh report: the text after '$first_word'. Write the triage stub first, then run .icm/scripts/new-run.sh triage/<slug> (explicit lane verb)."
    fi
    ;;
  # `hotfix <text>` is Jamie's word for the hotfix lane. An open triage stub by name is that stub.
  hotfix)
    if [ -n "$rest" ]; then
      if [ "$is_slug" -eq 1 ] && [ -z "$after" ] && resolve_slug "$slug" && [ "$tier" = triage ] && ! many; then
        route ".icm/lanes/hotfix/CONTEXT.md with the open triage stub $hits. Run .icm/scripts/new-run.sh $(ticket_of) --ready (explicit hotfix)."
      fi
      route ".icm/lanes/hotfix/CONTEXT.md with a fresh report: the text after 'hotfix'. Write the triage stub first, then run .icm/scripts/new-run.sh triage/<slug> --ready (explicit hotfix)."
    fi
    ;;
  # `plan <text>` or `scope <text>` → cut an epic, then stop for Jamie's review.
  plan|scope)
    if [ -n "$rest" ]; then
      route "$loop § A request with no stub, case 2: cut an epic with a breakdown from the text after '$first_word'. Push it. Stop for Jamie's review. Build nothing (explicit plan)."
    fi
    ;;
  # `promote [status|approve <who>|run <tag>]` → the UAT contract, where it exists.
  promote)
    verb="${rest%% *}"; arg="${rest#"$verb"}"; arg="${arg# }"
    if [ "$uat" -eq 0 ]; then
      route "this build has no .icm/uat/CONTEXT.md: it has no UAT and no promotion. Production follows main. Say so. Run nothing."
    fi
    case "$verb" in
      "")      route ".icm/uat/CONTEXT.md § The promotion: run .icm/scripts/promote.sh status, then .icm/scripts/promote.sh run --tag <the tag that status names> (Jamie's word promote)." ;;
      status)  [ -z "$arg" ] && route ".icm/uat/CONTEXT.md: run .icm/scripts/promote.sh status." ;;
      approve)
        if [ -n "$arg" ]; then
          route ".icm/uat/CONTEXT.md § The batch and the sign-off: run .icm/scripts/promote.sh approve --by \"<the name after 'approve'>\" (Jamie's word that the client approved)."
        else
          route ".icm/uat/CONTEXT.md § The batch and the sign-off: ask who approved, then run .icm/scripts/promote.sh approve --by \"<who>\"."
        fi ;;
      run)
        if [ -n "$arg" ]; then
          route ".icm/uat/CONTEXT.md § The promotion: run .icm/scripts/promote.sh run --tag <the tag after 'run'>."
        else
          route ".icm/uat/CONTEXT.md § The promotion: run .icm/scripts/promote.sh status, then .icm/scripts/promote.sh run --tag <the tag that status names>."
        fi ;;
      *)       route ".icm/uat/CONTEXT.md: promote has three verbs: status, approve <who>, run <tag>. Ask which one. Run nothing (unknown verb '$verb')." ;;
    esac
    ;;
esac

# --- silences: not work --------------------------------------------------------------------------

# Short prompts are conversation, not work.
[ "${#prompt}" -ge 15 ] || exit 0

# Pure questions / discussion pass through untouched: an interrogative opener, or a prompt that is
# a single question mark-terminated line with no imperative work verb anywhere.
q_word="${p#"${p%%[![:space:]]*}"}"; q_word="${q_word%%[[:space:]]*}"; q_word="${q_word//[?,.!]/}"
case "$q_word" in
  what|why|how|where|when|who|which|is|are|was|were|can|could|does|do|did|should|would|will|explain|tell)
    exit 0 ;;
esac

# Investigation is not delivery. A request to analyse / audit / review / compare / explain the
# codebase produces findings, not a pull request — and the classifiers below would happily route
# a long audit request to an epic (length) or `chore` (the words "ci config", "tooling",
# "migration" appear in almost any config audit). Bail before that can happen.
if has "${B}(analy[sz]e|analysis|audit|review|investigate|interrogate|compare|assess|evaluate|inspect|summari[sz]e|understand|walk me through|talk me through)${E}"; then
  exit 0
fi
if [[ ${p%%"$nl"*} =~ \?[[:space:]]*$ ]] \
   && ! has "${B}(fix|add|build|implement|create|change|update|rename|remove|refactor|upgrade|bump|migrate)${E}"; then
  exit 0
fi

# --- layer 2: lane classifiers (advisory, most specific first) -----------------------------------

lane_hint() { printf '.icm/lanes/%s/CONTEXT.md with the report: write the triage stub first, then run .icm/scripts/new-run.sh triage/<slug>' "$1"; }

# Bug: something that used to work is now wrong.
if has "${B}(bug|broken|breaks|crash(es|ed)?|error|exception|regression|500|404)${E}|${B}(doesn'?t|does not|won'?t|can'?t|stopped|no longer|fail(s|ed|ing)?) (work|load|open|save|send|render|show)|is (broken|failing|down)"; then
  suggest "$(lane_hint bug) (this prompt looks like a bug report: reproduce, then fix the cause)."
fi

# Tweak: tiny, fully-specified surface adjustment.
if has "${B}(tweak|typo|reword|rename|re-?label|copy change|wording|spacing|padding|colou?r|font|icon|tooltip|placeholder)${E}|${B}(small|tiny|quick|minor) (change|fix|adjustment|update)${E}"; then
  suggest "$(lane_hint tweak) (this prompt looks like a tweak: a small change that the request fully specifies)."
fi

# Chore: no user-facing behaviour change.
if has "${B}(refactor|chore|clean ?up|dep(endency)? bump|bump (the )?dep|upgrade [a-z@]|update (the )?dependenc|migration|migrate (the )?(db|database|schema|data)|add (an? )?index|drop (an? )?index|ci (config|workflow)|tooling)${E}"; then
  suggest "$(lane_hint chore) (this prompt looks like a chore: no change in behaviour. Migrations are forward-only)."
fi

# --- layer 3: new content → write the stub first --------------------------------------------------

# A prompt that names an existing stub is not new content — say so instead of a new stub; the
# user picks the form. Only kebab-case tokens with a hyphen are checked (every slug in practice
# has one), so ordinary words never hit the filesystem.
mentioned=""; seen=" "; checked=0
for tok in ${p//[^a-z0-9-]/ }; do
  [[ $tok =~ ^[a-z0-9]+(-[a-z0-9]+)+$ ]] || continue
  case "$seen" in *" $tok "*) continue ;; esac
  seen="$seen$tok "; checked=$((checked + 1))
  [ "$checked" -le 40 ] || break
  if resolve_slug "$tok"; then mentioned="${mentioned:+$mentioned; }$tier: $(hit_list)"; fi
done
if [ -n "$mentioned" ]; then
  suggest "this prompt names existing work ($mentioned). Use the form for that stub: new, build, revise or merge <slug>, or bug, tweak or chore <slug> for a triage stub. Do not write a new stub."
fi

# Big dump: many bullets/lines or very long → cut an epic.
bullet_lines=0
if [ "${#prompt}" -le 800 ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ $line =~ ^[[:space:]]*([-*+]|•|[0-9]+[.\)])[[:space:]] ]]; then bullet_lines=$((bullet_lines + 1)); fi
  done <<<"$prompt"
fi
if [ "${#prompt}" -gt 800 ] || [ "$bullet_lines" -ge 6 ]; then
  route "$loop § A request with no stub, case 2: cut an epic with a breakdown, one stub per pull request. Push it. Stop for Jamie's review. Build nothing (multi-feature dump, and no stub in .icm/intake/ matches it)."
fi

# Work-shaped and not clearly a lane: new content. Every new piece of work gets a stub first.
if has "${B}(add|build|implement|create|introduce|make|change|update|remove|delete|replace|extend|support|enable|allow|let|show|integrate|we need|we want|i want|i'?d like|need to|should be able to|new feature)${E}"; then
  route "$loop § A request with no stub: write the stub first. A one-off is a triage stub and its lane (case 1). A plan or a request that holds a decision is an epic, then a stop for Jamie's review (case 2) (new content, and no stub in .icm/intake/ matches it)."
fi

# Nothing matched confidently — stay silent; the conversation proceeds untouched.
exit 0
