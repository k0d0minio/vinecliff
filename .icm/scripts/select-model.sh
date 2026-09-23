#!/usr/bin/env bash
# select-model.sh — which model, for which pass: complexity × stage → tier → alias (TEMPLATE-OWNED).
#
# A stub, a scope and a spec each carry a `complexity` line (`_shared/scope-template.md` → Complexity
# and the model; `intake/CONTEXT.md` → Formats). Which model that implies is the same answer every
# time, so it is not re-derived in conversation and not restated in a contract — it lives here once,
# as three tiers and three roles:
#
#   tier 1  haiku    fast, low cost      formatting, a single-file fix, a syntax repair, a lint pass
#   tier 2  sonnet   balanced            feature implementation, tests, a PR body, ordinary build work
#   tier 3  opus     frontier reasoning  architecture, a multi-file refactor, a plan, a race condition
#           fable    frontier reasoning  the answer is not known yet — a spike, an investigation
#
#   role      stages                                              tier
#   advisor   01_scope · 02_define (and revise)  — the planning passes   3 (opus; fable on research)
#   executor  03_build · 04_release · every lane · a subagent            2 (sonnet; opus when the
#                                                                          complexity is high, fable
#                                                                          on research)
#   validator pre-commit formatting, a lint fix, a syntax repair         1 (haiku, always)
#
# The advisor–executor split is the point: the model that PLANS a run (Scope settles the source,
# Define writes the spec) is the frontier one, and the model that EXECUTES the plan (Build, the
# lanes, the subagents Build dispatches) is the balanced one, escalated only by the work's own
# complexity. Without `--stage`, the answer is the complexity mapping alone — what the helper printed
# before it knew about roles, unchanged:
#
#   low · trivial · easy            → sonnet     well-trodden work, one surface
#   medium · standard               → sonnet     ordinary feature work
#   high · complex · architecture   → opus       a new boundary, a data-model change, a risky rewrite
#   research · investigation · spike → fable     the answer is not known yet
#
# Both vocabularies are read on purpose: a stub says low|medium|high|research, a spec says
# trivial|standard|complex (the labels depend on that one), and the helper is pointed at either.
# An explicit `recommended-model` line WINS over the mapping for the advisor and executor roles —
# that line is the operator's override for the work itself. It never overrides the validator: a
# lint fix on an `opus` stub is still a haiku job. A file with neither reads as `medium`, and the
# output says it was a default, not a reading.
#
# It PRINTS a recommendation. It starts no session, switches no model, dispatches no subagent, and
# no stage acts on it by itself — the operator reads the line when opening the session that will do
# the work, and a stage that dispatches a subagent reads the executor line for it. (The house rule:
# never build an orchestrator. This is a lookup, not a launcher.)
#
# Header forms read, in this order — the first `complexity` found is the one used:
#   - complexity: high                      the estate's `- key: value` header
#   complexity: "high" # a comment          a YAML front-matter block between `---` fences
# and the same two forms for `recommended-model` / `recommended_model`.
#
# The model is printed as an ALIAS (haiku | sonnet | opus | fable) — what `claude --model <alias>`
# takes — and as the harness flag (`flags: --model <alias>`). A harness that wants a full model id
# reads it from the project's own manifest, never from here: `.icm/project.json` →
# `"models": {"opus": "<id>", …}` adds an `id:` line for the chosen alias.
#
# Usage:
#   .icm/scripts/select-model.sh <epic>/<feature-slug> [--stage <stage>]   # .icm/intake/<epic>/<feature-slug>.md
#   .icm/scripts/select-model.sh <stub-name>           [--stage <stage>]   # found anywhere under .icm/intake/ (live)
#   .icm/scripts/select-model.sh <path-to-file>        [--stage <stage>]   # any stub, scope.md or spec.md
#   .icm/scripts/select-model.sh --complexity <word>   [--stage <stage>]   # no file — the words alone
#   .icm/scripts/select-model.sh --stage <stage>                           # complexity defaults to medium
#   … [--json]                                                             # one JSON object instead of the lines
#
#   <stage> is 01_scope | 02_define | 03_build | 04_release (the `NN_` prefix is optional), a lane
#   (bug | tweak | chore | hotfix | handover | knowledge), `revise`, `subagent`, or a validation word
#   (validate | pre-commit | format | lint | fix).
#
# Verdict (stdout, last line — stderr with --json, so the object pipes clean):
#   RESULT: MODEL <alias>   exit 0  — read from the file / the flags, or the `medium` default (the lines say which)
#   RESULT: INVALID         exit 2  — a complexity, model or stage word outside the vocabulary
#   (exit 1: usage, no such file, or an ambiguous stub name — the matches are listed)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
die() { echo "error: $*" >&2; exit 1; }
invalid() { echo "$*" >&2; echo "RESULT: INVALID"; exit 2; }

as_json=0; arg=""; stage_arg=""; complexity_arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json)         as_json=1; shift ;;
    --stage)        stage_arg="${2:-}"; [ -n "$stage_arg" ] || die "--stage needs a value"; shift 2 ;;
    --stage=*)      stage_arg="${1#--stage=}"; shift ;;
    --complexity)   complexity_arg="${2:-}"; [ -n "$complexity_arg" ] || die "--complexity needs a value"; shift 2 ;;
    --complexity=*) complexity_arg="${1#--complexity=}"; shift ;;
    -h|--help)      sed -n '2,66p' "${BASH_SOURCE[0]}"; exit 0 ;;
    --*)            die "unknown flag: $1" ;;
    *)              [ -z "$arg" ] && arg="$1" || die "unexpected argument: $1"; shift ;;
  esac
done
[ -n "$arg" ] || [ -n "$stage_arg" ] || [ -n "$complexity_arg" ] \
  || die "usage: select-model.sh <epic>/<feature-slug> | <stub-name> | <path> [--stage <stage>] [--complexity <word>] [--json]"
[ -z "$arg" ] || [ -z "$complexity_arg" ] || die "give a file OR --complexity, not both"

# --- resolve the file, when one was named ---------------------------------------------------------
file=""
if [ -n "$arg" ]; then
  if [ -f "$arg" ]; then
    file="$arg"
  elif [ -f ".icm/intake/${arg%.md}.md" ]; then
    file=".icm/intake/${arg%.md}.md"
  else
    # A bare stub name: look through the live intake folders (epics and triage), never the archives —
    # a consumed stub is not work anybody is about to open a session for.
    mapfile -t hits < <(find .icm/intake -name "${arg%.md}.md" -not -path '*/_done/*' 2>/dev/null | sort)
    case "${#hits[@]}" in
      0) die "no stub '$arg' under .icm/intake/ (give <epic>/<feature-slug>, a stub name, or a path)" ;;
      1) file="${hits[0]}" ;;
      *) printf '  %s\n' "${hits[@]}" >&2; die "stub name '$arg' is ambiguous — give <epic>/<feature-slug>" ;;
    esac
  fi
  file="${file#./}"
fi

# --- read one header key, either form ---------------------------------------------------------------
# Only the header is searched: everything before the first `## ` section. A body that happens to
# say "complexity: high" in a sentence is prose, not a field.
header_value() { # <key-regex>
  [ -n "$file" ] || return 0
  awk -v key="$1" '
    /^##[[:space:]]/ { exit }
    {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]+/, "", line)            # the estate "- key: value" form
      if (line ~ "^(" key ")[[:space:]]*:") {
        val = substr(line, index(line, ":") + 1)
        sub(/[[:space:]]+#.*$/, "", val)                     # a trailing "# comment"
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        gsub(/^["\047]|["\047]$/, "", val)                   # YAML quotes
        print tolower(val); exit
      }
    }
  ' "$file"
}

complexity="$(header_value 'complexity')"
override="$(header_value 'recommended[-_]model')"
[ -z "$complexity_arg" ] || complexity="$(printf '%s' "$complexity_arg" | tr '[:upper:]' '[:lower:]')"

# A template left unfilled ("<low | medium | …>", "low | medium | high") is not a reading.
case "$complexity" in *"<"*|*"|"*) complexity="" ;; esac
case "$override"   in *"<"*|*"|"*) override="" ;; esac

# --- normalise the complexity to the stub vocabulary --------------------------------------------------
source="complexity"
case "$complexity" in
  low|trivial|easy)                 level="low" ;;
  medium|standard)                  level="medium" ;;
  high|complex|architecture)        level="high" ;;
  research|investigation|spike)     level="research" ;;
  "")                               level="medium"; complexity="medium"; source="default" ;;
  *) invalid "${file:-<flags>}: complexity '$complexity' is not low|medium|high|research (or a spec's trivial|standard|complex)" ;;
esac

# --- the stage → role -----------------------------------------------------------------------------------
stage=""; role="none"; role_note=""
if [ -n "$stage_arg" ]; then
  stage="$(printf '%s' "$stage_arg" | tr '[:upper:]' '[:lower:]' | sed -E 's:/+$::; s:^\.icm/stages/::; s:^\.icm/lanes/::; s:/CONTEXT\.md$::')"
  bare="$(printf '%s' "$stage" | sed -E 's/^[0-9]{2}_//')"
  case "$bare" in
    scope|define|revise|plan)                          role="advisor";   role_note="planning pass" ;;
    build|release|review|subagent|executor|lane)       role="executor";  role_note="execution pass" ;;
    bug|tweak|chore|hotfix|handover|knowledge)         role="executor";  role_note="execution pass (lane)" ;;
    validate|validator|validation|pre-commit|precommit|format|lint|fix|syntax)
                                                       role="validator"; role_note="validation pass" ;;
    *) invalid "stage '$stage_arg' is not 01_scope|02_define|03_build|04_release, a lane, revise, subagent, or validate|pre-commit|format|lint|fix" ;;
  esac
fi

# --- the mapping: role × complexity → alias ---------------------------------------------------------------
model=""
case "$role" in
  advisor)
    case "$level" in research) model="fable" ;; *) model="opus" ;; esac ;;
  executor)
    case "$level" in low|medium) model="sonnet" ;; high) model="opus" ;; research) model="fable" ;; esac ;;
  validator)
    model="haiku" ;;
  none)
    case "$level" in low|medium) model="sonnet" ;; high) model="opus" ;; research) model="fable" ;; esac ;;
esac

if [ -n "$override" ]; then
  case "$override" in
    haiku|sonnet|opus|fable)
      if [ "$role" = "validator" ]; then
        override_note="the file's recommended-model ($override) is not applied to a validation pass"
      else
        model="$override"; source="recommended-model"
      fi ;;
    *) invalid "$file: recommended-model '$override' is not haiku|sonnet|opus|fable" ;;
  esac
fi

case "$model" in
  haiku)  tier=1; tier_note="fast, low cost" ;;
  sonnet) tier=2; tier_note="balanced" ;;
  opus)   tier=3; tier_note="frontier reasoning" ;;
  fable)  tier=3; tier_note="frontier reasoning — research" ;;
esac
flags="--model $model"

# --- the project's own id for that alias, when it keeps one ----------------------------------------
model_id=""
if command -v jq >/dev/null 2>&1; then
  # shellcheck source=lib/project.sh
  source "$(dirname "${BASH_SOURCE[0]}")/lib/project.sh"
  model_id="$(project_field ".models.${model}" '')"
fi

case "$source" in
  complexity)        why="from complexity: $complexity${role_note:+ · $role_note}" ;;
  recommended-model) why="the file's own recommended-model line (complexity: $complexity)" ;;
  default)           why="default — no complexity given, read as medium${role_note:+ · $role_note}" ;;
esac

if [ "$as_json" -eq 1 ]; then
  command -v jq >/dev/null 2>&1 || die "--json needs jq"
  jq -n --arg file "$file" --arg complexity "$complexity" --arg level "$level" --arg stage "$stage" \
        --arg role "$role" --argjson tier "$tier" --arg model "$model" --arg flags "$flags" \
        --arg source "$source" --arg id "$model_id" \
    '(if $file == "" then {} else {file: $file} end)
     + {complexity: $complexity, level: $level}
     + (if $stage == "" then {} else {stage: $stage} end)
     + {role: $role, tier: $tier, model: $model, flags: $flags, source: $source}
     + (if $id == "" then {} else {id: $id} end)'
else
  [ -z "$file" ]  || echo "file:       $file"
  echo "complexity: $complexity"
  [ -z "$stage" ] || echo "stage:      $stage → role: $role ($role_note)"
  echo "tier:       $tier ($tier_note)"
  echo "model:      $model  ($why)"
  [ -z "${override_note:-}" ] || echo "note:       $override_note"
  [ -z "$model_id" ] || echo "id:         $model_id  (.icm/project.json → models.$model)"
  echo "flags:      $flags"
  echo "open with:  claude $flags   ·   any other harness: its own name for \"$model\"${model_id:+ ($model_id)}"
fi
# --json keeps stdout for the object alone (`select-model.sh … --json | jq .model`); the verdict goes to stderr.
[ "$as_json" -eq 0 ] || exec >&2
echo "RESULT: MODEL $model"
