#!/usr/bin/env bash
# route-request.sh — UserPromptSubmit router: the operator never has to type `/pipeline`.
# Canonical estate hook (icm-board _system/template/claude/hooks/), promoted from sustentus by
# decision D44. Registered in every repo and silent in one without the pipeline: it only speaks
# where .claude/skills/pipeline/SKILL.md exists. The archive it searches for a finished run is the
# repo's own `runs_archive` in .icm/project.json (default .icm/runs/_done).
#
# Deterministic, sub-100ms, no LLM (modelled on block-local-checks.sh): reads the UserPromptSubmit
# payload on stdin, looks at the prompt, and injects ONE additionalContext line for the /pipeline
# router (.claude/skills/pipeline/SKILL.md). Two kinds of line:
#
#   [pipeline-router] Route: /pipeline <sub> [<slug>] (<why>)
#       Directive. Emitted when the prompt is a bare stage form — `<stage> <slug>` where the slug
#       resolves to a run, an archived run or an intake stub; `<lane> <triage-stub>` or
#       `<lane> <free text>` (a lane takes a triage stub name or a fresh report, and is never
#       resumed by slug); bare `new`; `scope <input>`; `triage report|batch|prune` (the backlog
#       verbs — a read, a cut into an intake epic, a deletion list; never a run);
#       `knowledge add|edit|remove <request>` (one project-knowledge page changed on a docs-only PR — the
#       one way to change project knowledge outside a Release; never a run) — or when it is
#       work-shaped and names nothing that exists (new content → Scope). The router runs that
#       command unless the user's own prompt overrides it.
#   [pipeline-router] Suggest: /pipeline <lane> "<…>" (<why>)
#       Advisory. The bug / tweak / chore classifiers are heuristics; the router announces the
#       suggestion and the user can redirect.
#
# `/pipeline <sub>` typed explicitly is the override: slash commands are never touched. Pure
# questions, analysis requests, webhook payloads and short conversational prompts stay silent.
# Re-verify with .claude/hooks/route-request.test.sh (bash, no framework — not a repo check).
#
# Contract:
#   exit 0 always — this hook NEVER blocks (never exits 2). Fail-open on any malformed input.
#   stdout on a match: {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"…"}}
#   stdout otherwise: nothing.
set -euo pipefail

input="$(cat 2>/dev/null || true)"
command -v jq >/dev/null 2>&1 || exit 0            # no jq → can't parse → stay silent
prompt="$(printf '%s' "$input" | jq -r '.prompt // ""' 2>/dev/null || true)"
[ -n "$prompt" ] || exit 0

# Slash commands are already routed — `/pipeline <sub>` is the explicit override.
case "$prompt" in /*) exit 0 ;; esac

# Webhook / injected-event payloads are not user requests — remote sessions (PR watching, task
# notifications) deliver them as prompts; classifying them produces stray lane hints. Stay silent.
case "$prompt" in
  *"<github-webhook-activity>"*|*"<untrusted_external_data"*|*"<task-notification"*) exit 0 ;;
esac

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# No pipeline router in this repo → nothing to route to.
[ -f "$root/.claude/skills/pipeline/SKILL.md" ] || exit 0
# Where finished runs are archived — the repo's own runs_archive (D20: project.json holds it).
archive="$(jq -r '.runs_archive // empty' "$root/.icm/project.json" 2>/dev/null || true)"
archive="${archive:-.icm/runs/_done}"; archive="${archive%/}"

emit() {
  jq -cn --arg ctx "$1" \
    '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
  exit 0
}
route_tail="This line comes from .claude/hooks/route-request.sh. A Route: line is authoritative — run that /pipeline command per .claude/skills/pipeline/SKILL.md unless the user's own prompt overrides it."
suggest_tail="This is an advisory classification from .claude/hooks/route-request.sh — announce the suggested lane, let the user override, and route per .claude/skills/pipeline/SKILL.md."

# One lowercased copy for matching (first 2000 chars is plenty and keeps grep fast).
p="$(printf '%.2000s' "$prompt" | tr '[:upper:]' '[:lower:]')"

# --- layer 1: bare stage forms (deterministic file lookups, no heuristics) ---------------------

# Where a slug lives, if anywhere. Prints the reason, or nothing.
#   <stage> decides whether triage/ counts: lanes consume triage stubs; `new` and the spine never
#   do. `_done/` is never searched (a spun-out stub has a run — found by the first two checks).
resolve_slug() {
  local stage="$1" slug="$2" f
  [ -f "$root/.icm/runs/$slug/run.md" ] && { printf 'run found in .icm/runs/%s/' "$slug"; return 0; }
  [ -d "$root/$archive/$slug" ] && { printf 'archived run in %s/%s/' "$archive" "$slug"; return 0; }
  case "$stage" in
    bug|tweak|chore)
      [ -f "$root/.icm/intake/triage/$slug.md" ] && { printf 'triage stub .icm/intake/triage/%s.md' "$slug"; return 0; } ;;
  esac
  for f in "$root"/.icm/intake/*/"$slug.md"; do
    [ -f "$f" ] || continue
    case "$f" in */triage/*) continue ;; esac
    printf 'intake stub %s' "${f#"$root"/}"; return 0
  done
  return 1
}

# Normalise: collapse whitespace, drop trailing punctuation, so `New`, `new.` and `build x ` match.
bare="$(printf '%s' "$p" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/[ .!]+$//')"
first_word="${bare%% *}"
rest="${bare#"$first_word"}"; rest="${rest# }"

# (b) bare `new` → the next stub in the batch.
if [ "$bare" = "new" ]; then
  emit "[pipeline-router] Route: /pipeline new (bare new — the router picks the next intake stub in the batch, checks its dependency and stops for confirmation). $route_tail"
fi

case "$first_word" in
  # `scope <anything>` — Scope takes input, not a slug; the whole remainder is the source.
  scope)
    [ -n "$rest" ] && emit "[pipeline-router] Route: /pipeline scope \"<the input after 'scope'>\" (explicit stage verb — Scope records the source, settles it in session and cuts the intake batch). $route_tail"
    ;;
  # (a) `<stage> <slug>` — exactly one kebab-case token after the verb. `revise` alone may carry
  #     text after the slug (the change to make); for every other verb trailing text is not a form.
  new|revise|build|release)
    slug="${rest%% *}"; after="${rest#"$slug"}"; after="${after# }"
    if [ -n "$slug" ] && { [ -z "$after" ] || [ "$first_word" = "revise" ]; } \
       && printf '%s' "$slug" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
      if where="$(resolve_slug "$first_word" "$slug")"; then
        emit "[pipeline-router] Route: /pipeline $first_word $slug ($where). $route_tail"
      elif printf '%s' "$slug" | grep -q -- '-'; then
        # Slug-shaped but not in this checkout. A run in flight lives on its own branch, so its
        # run.md is absent from main; the stage preamble (resolve-run.sh) finds it via the PR, and
        # the router resolves `new <name>` by substring or lists the batch. Never treat it as
        # new content.
        case "$first_word" in
          new) emit "[pipeline-router] Route: /pipeline new $slug (no stub with that exact name in .icm/intake/ — the router resolves it by substring, or lists the active batch and asks). $route_tail" ;;
          *)   emit "[pipeline-router] Route: /pipeline $first_word $slug (no run or stub named '$slug' in this checkout — the stage preamble resolves the run via its PR, or STOPs). $route_tail" ;;
        esac
      fi
    fi
    ;;
  # (c) `<lane> <arg>` — a lane is ONE invocation that ends in a PR the human merges from GitHub,
  #     so it is never resumed by slug and never runs the stage preamble. The argument is a triage
  #     stub name (one bare token) or a fresh report (anything longer); a bare token that is a
  #     run, not a stub, is named as such so the router can say the lane is not resumed.
  bug|tweak|chore)
    slug="${rest%% *}"; after="${rest#"$slug"}"; after="${after# }"
    if [ -z "$slug" ]; then
      :  # bare verb, no argument — conversation, not a form
    elif [ -z "$after" ] && printf '%s' "$slug" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
      if [ -f "$root/.icm/intake/triage/$slug.md" ]; then
        emit "[pipeline-router] Route: /pipeline $first_word $slug (triage stub .icm/intake/triage/$slug.md). $route_tail"
      elif [ -f "$root/.icm/runs/$slug/run.md" ] || [ -d "$root/$archive/$slug" ]; then
        emit "[pipeline-router] Route: /pipeline $first_word $slug ('$slug' is a run, not a triage stub — lanes are not resumed: an open lane PR is merged from GitHub, an archived one has shipped; the router says so and stops). $route_tail"
      elif printf '%s' "$slug" | grep -q -- '-'; then
        emit "[pipeline-router] Route: /pipeline $first_word $slug (no triage stub with that exact name in .icm/intake/triage/ — the router resolves it by substring, or asks whether it is a fresh report; lanes are never resumed). $route_tail"
      fi
    else
      # Free text after an explicit lane verb: a fresh report, run in one invocation.
      emit "[pipeline-router] Route: /pipeline $first_word \"<the text after '$first_word'>\" (explicit lane verb with a fresh report — one invocation: fix → green PR → close-out → hand over for a human squash-merge). $route_tail"
    fi
    ;;
  # (d) `triage <verb>` — the backlog (.icm/intake/triage/) has three verbs and no run: `report`
  #     runs triage-report.sh; `batch <area|lane> "<epic-title>"` dedupes the matching stubs and
  #     cuts them into an intake epic; `prune` lists deletion candidates for the human to confirm.
  #     Bare `triage` shows the three forms; `triage <anything else>` is conversation.
  triage)
    verb="${rest%% *}"; after="${rest#"$verb"}"; after="${after# }"
    case "$verb" in
      "")     emit "[pipeline-router] Route: /pipeline triage (bare triage — the router lists the three verbs: report, batch <area|lane> \"<epic-title>\", prune; runs nothing). $route_tail" ;;
      report) [ -z "$after" ] && emit "[pipeline-router] Route: /pipeline triage report (runs .icm/scripts/triage-report.sh — counts by lane / source / area / age and the near-duplicates; writes nothing). $route_tail" ;;
      prune)  [ -z "$after" ] && emit "[pipeline-router] Route: /pipeline triage prune (lists stubs older than 30 days or superseded, with the git rm for each — the human confirms every deletion; the agent never deletes on its own). $route_tail" ;;
      batch)  emit "[pipeline-router] Route: /pipeline triage batch <the selector and title after 'triage batch'> (dedupes the matching triage stubs into _done/ with superseded-by lines and cuts the survivors into an intake epic, validate-intake.sh → RESULT: OK, then stops — no run, no PR). $route_tail" ;;
    esac
    ;;
  # (e) `knowledge <verb> <request>` — the one way to change project knowledge (the repo's
  #     docs_path in .icm/project.json) outside a Release: `add`, `edit` or `remove` one page, routed
  #     through .icm/_shared/knowledge-map.md, on its own docs-only PR. Bare `knowledge`, or an
  #     unknown verb, shows the three forms (never a trip to Scope — the prompt named the lane); a
  #     known verb with no request is conversation.
  knowledge)
    verb="${rest%% *}"; after="${rest#"$verb"}"; after="${after# }"
    case "$verb" in
      add|edit|remove)
        [ -n "$after" ] && emit "[pipeline-router] Route: /pipeline knowledge $verb \"<the request after 'knowledge $verb'>\" (knowledge lane — routes to one project-knowledge page via .icm/_shared/knowledge-map.md, changes it under docs-sync's MDX rules, updates the map if a page was added or removed, validate-knowledge-map.sh → RESULT: OK, opens a docs-only PR and stops — no run, never resumed). $route_tail"
        exit 0 ;;
      "")  emit "[pipeline-router] Route: /pipeline knowledge (bare knowledge — the router lists the three forms: add|edit|remove \"<what>\"; changes nothing). $route_tail" ;;
      *)   emit "[pipeline-router] Route: /pipeline knowledge (unknown verb '$verb' — the router lists the three forms: add|edit|remove \"<what>\"; changes nothing). $route_tail" ;;
    esac
    ;;
esac

# --- silences: not work --------------------------------------------------------------------------

# Short prompts are conversation, not work.
[ "${#prompt}" -ge 15 ] || exit 0

# Pure questions / discussion pass through untouched: an interrogative opener, or a prompt that is
# a single question mark-terminated line with no imperative work verb anywhere.
q_word="$(printf '%s' "$p" | awk '{print $1; exit}' | tr -d '?,.!')"
case "$q_word" in
  what|why|how|where|when|who|which|is|are|was|were|can|could|does|do|did|should|would|will|explain|tell)
    exit 0 ;;
esac

# Investigation is not delivery. A request to analyse / audit / review / compare / explain the
# codebase produces findings, not a PR — and the classifiers below would happily route a long
# audit request to `scope` (length) or `chore` (the words "ci config", "tooling", "migration"
# appear in almost any config audit). Bail before that can happen.
if printf '%s' "$p" | grep -Eq '\b(analy[sz]e|analysis|audit|review|investigate|interrogate|compare|assess|evaluate|inspect|summari[sz]e|understand|walk me through|talk me through)\b'; then
  exit 0
fi
if printf '%s' "$p" | head -n1 | grep -q '?[[:space:]]*$' \
   && ! printf '%s' "$p" | grep -Eq '\b(fix|add|build|implement|create|change|update|rename|remove|refactor|upgrade|bump|migrate)\b'; then
  exit 0
fi

# --- layer 2: lane classifiers (advisory, most specific first) -----------------------------------

# Bug: something that used to work is now wrong.
if printf '%s' "$p" | grep -Eq "\b(bug|broken|breaks|crash(es|ed)?|error|exception|regression|500|404)\b|\b(doesn'?t|does not|won'?t|can'?t|stopped|no longer|fail(s|ed|ing)?) (work|load|open|save|send|render|show)|is (broken|failing|down)"; then
  emit "[pipeline-router] Suggest: /pipeline bug \"<the report>\" (this prompt looks like a BUG report — reproduce → fix → single merge-gate PR). $suggest_tail"
fi

# Tweak: tiny, fully-specified surface adjustment.
if printf '%s' "$p" | grep -Eq "\b(tweak|typo|reword|rename|re-?label|copy change|wording|spacing|padding|colou?r|font|icon|tooltip|placeholder)\b|\b(small|tiny|quick|minor) (change|fix|adjustment|update)\b"; then
  emit "[pipeline-router] Suggest: /pipeline tweak \"<the change>\" (this prompt looks like a TWEAK — small PR, merge gate only). $suggest_tail"
fi

# Chore: no user-facing behaviour change.
if printf '%s' "$p" | grep -Eq "\b(refactor|chore|clean ?up|dep(endency)? bump|bump (the )?dep|upgrade [a-z@]|update (the )?dependenc|migration|migrate (the )?(db|database|schema|data)|add (an? )?index|drop (an? )?index|ci (config|workflow)|tooling)\b"; then
  emit "[pipeline-router] Suggest: /pipeline chore \"<the task>\" (this prompt looks like a CHORE — no user-facing behaviour change; single merge-gate PR; migrations need a working down). $suggest_tail"
fi

# --- layer 3: new content → Scope ----------------------------------------------------------------

# A prompt that names an existing run or stub is not new content — say so instead of sending it
# to Scope; the user picks the stage. Only kebab-case tokens with a hyphen are checked (every slug
# has one), so ordinary words never hit the filesystem.
mentioned=""
for tok in $(printf '%s' "$p" | tr -c 'a-z0-9\n-' ' ' | tr ' ' '\n' | grep -E '^[a-z0-9]+(-[a-z0-9]+)+$' | sort -u | head -n 40); do
  if where="$(resolve_slug chore "$tok")"; then mentioned="${mentioned:+$mentioned; }$where"; fi
done
if [ -n "$mentioned" ]; then
  emit "[pipeline-router] Suggest: this prompt names existing pipeline work ($mentioned) — route to that run's or stub's stage (/pipeline new|build|release|bug|tweak|chore <slug>), not to Scope. $suggest_tail"
fi

# Big dump: many bullets/lines or very long → Scope, which cuts it into a batch.
bullet_lines="$(printf '%s\n' "$prompt" | grep -Ec '^[[:space:]]*([-*+•]|[0-9]+[.)])[[:space:]]' || true)"
if [ "${#prompt}" -gt 800 ] || [ "$bullet_lines" -ge 6 ]; then
  emit "[pipeline-router] Route: /pipeline scope \"<the story>\" (multi-feature dump — nothing in .icm/runs/ or .icm/intake/ matches it; Scope records the source, settles the scope in session and cuts the intake batch, one stub per future PR). $route_tail"
fi

# Work-shaped and not clearly a lane: new content. Every new piece of work enters through Scope.
if printf '%s' "$p" | grep -Eq "\b(add|build|implement|create|introduce|make|change|update|remove|delete|replace|extend|support|enable|allow|let|show|integrate|we need|we want|i want|i'?d like|need to|should be able to|new feature)\b"; then
  emit "[pipeline-router] Route: /pipeline scope \"<the request>\" (new content — nothing in .icm/runs/ or .icm/intake/ matches it; Scope records the source, settles the scope in session and cuts the batch, then new → build → release). $route_tail"
fi

# Nothing matched confidently — stay silent; the conversation proceeds untouched.
exit 0
