#!/usr/bin/env bash
# setup.sh — is this repo complete, current and configured, from the pipeline's point of view? (TEMPLATE-OWNED)
#
# The deterministic half of `/setup` (agency brief §4.7, flag 3): one report, eleven sections,
# `RESULT: OK | GAPS n`. Re-run any time, from any harness, in any repo. It never needs icm-board
# in view — everything it checks is in the repo (`.icm/MANIFEST` says what a complete pipeline is,
# `.icm/template-version` says how current this one is) — and the one thing it cannot do without a
# template source, seed a bare repo, it does only when `--template <path|url>` (or `ICM_TEMPLATE`)
# names one, and otherwise says `SKIP template (no source)`. There is NO default source: a
# relative `../../_system` would be the silent dependency on icm-board's layout that flag 1
# forbids, and would resolve to nothing everywhere but one machine.
#
# Sections, in order:
#    1. Baseline   every file .icm/MANIFEST names; the router and /setup skills; the two hooks
#                  registered in .claude/settings.json; opencode.jsonc (where AGENTS.md exists);
#                  the PR template with both gate anchors; .icm/template-version.
#                  `--fix` seeds only what is MISSING, from --template (never overwrites — D7);
#                  a diverged T file is drift, reported with the icm-sync.sh command.
#    2. Formatter  a formatter config that would touch T paths and no exclusion for them:
#                  reported with the exact lines to add (D17/D19: per repo, by hand; never written).
#    3. project.json  name, complexity, required_checks, personas, deploy, reporting, migrations
#                  (stamp/tool/out_of_order), database (isolation, provider — a Neon project is
#                  read once when its key is in the shell: production branch, preview branching,
#                  and with UAT the non-production project too; a MongoDB cluster's names and
#                  commands, and the cluster read once when its URI is in the shell — D35),
#                  security, support, health_endpoint, uat — missing or still at the stub's value
#                  is a line with the question. A declared UAT environment (D39: `uat: {target,
#                  url}`, both or neither) is checked — the UAT database declared (Neon, D41: a
#                  `nonprod_project_id` that is not production's), and with a Vercel token the
#                  custom environment exists on every product project, the team's
#                  `accountLimit.total` is at least 1 (else "UAT requires a Pro team") and, on a
#                  Neon repo, production's database variable is scoped to Production only (no
#                  Preview, no custom environment — D41; a [TODO] when the API does not show it).
#                  The retired shapes FAIL: a `uat.branch` key, a `.icm/uat/batch.json` (removed
#                  by hand — never by a script), a `database.neon.uat_branch`.
#                  Undeclared is one info line, never a gap.
#    4. Environment   env-check.sh (route + binaries) and env.sh audit (names only).
#    5. Tickets    validate-intake.sh over every live epic and triage/; triage-report.sh against
#                  the cap; a loose TODO.md/BACKLOG.md at the root.
#    6. Raw        process-raw.sh --dry-run: assets waiting, which need a missing local tool; a
#                  media file tracked under .icm/raw/ (media is never committed).
#    7. Runs       a merged run still in runs/ (the archive alarm); a live run whose PR is closed;
#                  usage.md pairs with a start and no end. Needs a GitHub route; says so without.
#    8. Knowledge  validate-knowledge-map.sh.
#    9. Reporting  kinds → channels; unset channel variables; announce_from vs the workflow.
#   10. Workflows  the reference release.yaml / labels.yaml present, or declared absent in
#                  _shared/project-rules.md; neon-cleanup.yaml where a Neon project branches per
#                  preview, mongodb-cleanup.yaml where a MongoDB repo has a database per preview
#                  (`--fix` seeds either from --template); type:hotfix and type:handover in
#                  .github/labels.yml. On a UAT repo the release workflow is REQUIRED (it is the
#                  promotion) and a db-migrate workflow must be callable from it (`workflow_call`).
#   11. Support    tier none → nothing; micro → `micro: no support line`; basic|retainer → the
#                  fail-safe page exists, the Sentry key is declared [production], alert maps to
#                  a channel or project-rules.md records the red-job default.
#
# [FAIL] counts as a gap; [WARN] and [INFO] never do (D15: gaps are the report's content).
# It REPORTS, and with --fix seeds; it never overwrites, never edits a formatter config, never
# writes a P file's values (the /setup skill asks and writes those), never pushes.
# `--report` prints the same bytes on two consecutive runs (no timestamps).
#
# Usage: .icm/scripts/setup.sh [--fix] [--template <path|url>] [--report]
# Verdict (stdout, last line): RESULT: OK · RESULT: GAPS n   (exit 0 either way; 2 on usage)
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
die() { echo "error: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq not found"

FIX=0; TEMPLATE="${ICM_TEMPLATE:-}"; REPORT=0; REPO_FLAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fix) FIX=1; shift ;;
    --template) TEMPLATE="${2:-}"; shift 2 ;;
    --report) REPORT=1; shift ;;
    --repo) REPO_FLAG="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,45p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown argument: $1 (usage: setup.sh [--fix] [--template <path|url>] [--report] [--repo <path>])" ;;
  esac
done
[ "$FIX" -eq 1 ] && [ "$REPORT" -eq 1 ] && die "--fix and --report are exclusive"
# A bare repo has no .icm/scripts/setup.sh yet, so its first run is the TEMPLATE's copy, invoked
# from the repo (`bash <template>/icm-pipeline/scripts/setup.sh --fix --template <template>`) or
# with --repo. Detect that: a copy whose ../.. is not a git work tree but whose sibling is the
# template MANIFEST is running from the template, and the repo is the current directory.
if [ -n "$REPO_FLAG" ]; then repo_root="$(cd "$REPO_FLAG" && pwd)" || die "--repo: not a directory: $REPO_FLAG"
elif [ ! -e "$repo_root/.git" ] && [ -f "$here/../MANIFEST" ] && [ ! -d "$repo_root/.icm" ]; then
  repo_root="$PWD"; [ -n "$TEMPLATE" ] || TEMPLATE="$(cd "$here/../.." && pwd)"
fi
cd "$repo_root" || die "cannot enter $repo_root"
# After a --fix the repo's own copy exists; every later call should be that one. Scripts this
# report calls (env-check.sh, env.sh, validate-*.sh …) are the repo's own under .icm/scripts/.
if [ -x "$repo_root/.icm/scripts/env-check.sh" ]; then here="$repo_root/.icm/scripts"; fi

# lib/project.sh derives the repo root from its own location; when this report runs from the
# template's copy against a bare repo, point it at the repo explicitly.
project_json="$repo_root/.icm/project.json"
# shellcheck source=lib/project.sh
source "$here/lib/project.sh"
project_json="$repo_root/.icm/project.json"

gaps=0; warns=0
ok()   { echo "  [OK]   $*"; }
info() { echo "  [INFO] $*"; }
todo() { echo "  [TODO] $*"; }   # an operator's check no API here can answer — never a gap
warn() { echo "  [WARN] $*"; warns=$((warns+1)); }
fail() { echo "  [FAIL] $*"; gaps=$((gaps+1)); }
fixed(){ echo "  [+]    $*"; }
last_line() { "$@" 2>/dev/null | tail -n1; }

# --- the template source (only for seeding / drift) ----------------------------------------------------------
tmpl_dir=""; tmpl_note="no source"
resolve_template() {
  [ -n "$TEMPLATE" ] || return 0
  case "$TEMPLATE" in
    http://*|https://*)
      command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 || { tmpl_note="curl/tar missing for a URL source"; return 0; }
      local t; t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
      if curl -sSL --max-time 60 "$TEMPLATE" | tar -xz -C "$t" 2>/dev/null; then
        tmpl_dir="$(find "$t" -maxdepth 3 -type d -name icm-pipeline -path '*template*' 2>/dev/null | head -1)"; tmpl_dir="${tmpl_dir%/icm-pipeline}"
      fi
      [ -n "$tmpl_dir" ] && tmpl_note="tarball $TEMPLATE" || tmpl_note="tarball did not unpack to a template folder" ;;
    *)
      if [ -d "$TEMPLATE/icm-pipeline" ]; then tmpl_dir="$(cd "$TEMPLATE" && pwd)"; elif [ -d "$TEMPLATE/_system/template/icm-pipeline" ]; then tmpl_dir="$(cd "$TEMPLATE/_system/template" && pwd)"; fi
      [ -n "$tmpl_dir" ] && tmpl_note="$tmpl_dir" || tmpl_note="$TEMPLATE is not a template folder (expected <path>/icm-pipeline/)" ;;
  esac
}
resolve_template
seed() { # <src> <dst> [+x]
  [ -e "$2" ] && return 1
  mkdir -p "$(dirname "$2")"; cp "$1" "$2"; [ "${3:-}" = "+x" ] && chmod +x "$2"; fixed "created ${2#./}"; return 0
}

echo "=== setup.sh — $(basename "$repo_root")$( [ "$FIX" -eq 1 ] && echo ' (--fix: seeding what is missing)') ==="

# --- 1. baseline ------------------------------------------------------------------------------------------------
echo "[1/11] Baseline — the files the pipeline promises"
manifest=".icm/MANIFEST"
[ -f "$manifest" ] || [ -z "$tmpl_dir" ] || [ "$FIX" -eq 0 ] || seed "$tmpl_dir/icm-pipeline/MANIFEST" "$manifest"
if [ -f "$manifest" ]; then
  ok ".icm/MANIFEST present ($(awk '$1=="T"' "$manifest" | wc -l | tr -d ' ') T · $(awk '$1=="P"' "$manifest" | wc -l | tr -d ' ') P)"
  while read -r owner path; do
    [ -n "$path" ] || continue
    if [ -f ".icm/$path" ]; then
      if [ "$owner" = "T" ] && [ -n "$tmpl_dir" ] && [ -f "$tmpl_dir/icm-pipeline/$path" ] && ! cmp -s "$tmpl_dir/icm-pipeline/$path" ".icm/$path"; then
        warn ".icm/$path differs from the template — drift; from icm-board: _system/scripts/icm-sync.sh --apply <this repo> (never edited here)"
      fi
    else
      if [ "$FIX" -eq 1 ] && [ -n "$tmpl_dir" ] && [ -f "$tmpl_dir/icm-pipeline/$path" ]; then
        if [ "$path" = "project.json" ]; then mkdir -p .icm; jq --arg n "$(basename "$repo_root")" '.name = $n' "$tmpl_dir/icm-pipeline/$path" > ".icm/$path"; fixed "created .icm/project.json (name filled)"
        else case "$path" in scripts/lib/*|scripts/lib/*.json) seed "$tmpl_dir/icm-pipeline/$path" ".icm/$path" ;; scripts/*.sh|skills/*/scripts/*.sh) seed "$tmpl_dir/icm-pipeline/$path" ".icm/$path" +x ;; *) seed "$tmpl_dir/icm-pipeline/$path" ".icm/$path" ;; esac; fi
      else
        fail ".icm/$path missing ($owner)$( [ -z "$tmpl_dir" ] && echo ' — no template source to seed from: --template <path|url>, or icm-sync.sh from icm-board')"
      fi
    fi
  done < <(grep -vE '^\s*(#|$)' "$manifest")
else
  fail ".icm/MANIFEST missing — this repo predates the in-repo manifest, or was never seeded: --fix --template <path|url>, or from icm-board icm-sync.sh --apply"
fi
# The rest of the baseline (icm/, claude/, claude-pipeline/, github-pipeline/ in the template).
baseline=( ".icm/CONTEXT.md|icm/CONTEXT.md" ".icm/intake/README.md|icm/intake/README.md" ".claude/settings.json|claude/settings.json"
  ".claude/hooks/session-start.sh|claude/hooks/session-start.sh|+x" ".claude/hooks/wrap-reminder.sh|claude/hooks/wrap-reminder.sh|+x"
  ".claude/skills/ticket-craft/SKILL.md|claude/skills/ticket-craft/SKILL.md" ".claude/skills/pr-conventions/SKILL.md|claude/skills/pr-conventions/SKILL.md"
  ".claude/skills/pipeline/SKILL.md|claude-pipeline/skills/pipeline/SKILL.md" ".claude/skills/setup/SKILL.md|claude-pipeline/skills/setup/SKILL.md"
  ".github/pull_request_template.md|github-pipeline/pull_request_template.md" )
for b in "${baseline[@]}"; do
  IFS='|' read -r dst src mode <<<"$b"
  if [ -f "$dst" ]; then :; elif [ "$FIX" -eq 1 ] && [ -n "$tmpl_dir" ] && [ -f "$tmpl_dir/$src" ]; then seed "$tmpl_dir/$src" "$dst" "${mode:-}"; else fail "$dst missing"; fi
done
for d in .icm/intake/triage/_done .icm/intake/_done .icm/docs; do
  [ -d "$d" ] || { if [ "$FIX" -eq 1 ]; then mkdir -p "$d"; [ -n "$(ls -A "$d")" ] || : > "$d/.gitkeep"; fixed "created $d/"; else fail "$d/ missing"; fi; }
done
if [ -f .claude/settings.json ]; then
  for h in session-start.sh wrap-reminder.sh; do
    [ -f ".claude/hooks/$h" ] && ! grep -q "$h" .claude/settings.json && warn ".claude/hooks/$h exists but .claude/settings.json never registers it (inert) — icm-check.sh --fix merges the entry (D18)"
  done
fi
if [ -f AGENTS.md ]; then
  [ -f opencode.jsonc ] || { if [ "$FIX" -eq 1 ] && [ -n "$tmpl_dir" ] && [ -f "$tmpl_dir/root/opencode.jsonc" ]; then seed "$tmpl_dir/root/opencode.jsonc" opencode.jsonc; else fail "opencode.jsonc missing (AGENTS.md present — the rails file is seeded beside it)"; fi; }
  [ -f CLAUDE.md ] || { if [ "$FIX" -eq 1 ] && [ -n "$tmpl_dir" ]; then seed "$tmpl_dir/root/CLAUDE.md" CLAUDE.md; else fail "CLAUDE.md importer missing (AGENTS.md present)"; fi; }
elif [ ! -f CLAUDE.md ]; then
  warn "no Layer-0 identity file (AGENTS.md + CLAUDE.md importer, or a legacy CLAUDE.md) — each repo writes its own; nothing is seeded"
fi
if [ -f .github/pull_request_template.md ]; then
  grep -q 'gate:spec-approved' .github/pull_request_template.md && grep -q 'gate:ready-to-merge' .github/pull_request_template.md \
    && ok ".github/pull_request_template.md carries both gate anchors" || fail ".github/pull_request_template.md lacks a gate anchor (gate:spec-approved / gate:ready-to-merge)"
fi
if [ -f .icm/template-version ]; then
  ok ".icm/template-version: $(tr '\n' ' ' < .icm/template-version | sed 's/ $//')"
elif [ "$FIX" -eq 1 ] && [ -n "$tmpl_dir" ]; then
  tv="$(git -C "$tmpl_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  printf 'template: icm-board %s\nsynced: %s\nmanifest: %s T files\n' "$tv" "$(date -u +%F)" "$( [ -f "$manifest" ] && awk '$1=="T"' "$manifest" | wc -l | tr -d ' ' || echo '?')" > .icm/template-version
  fixed "wrote .icm/template-version (icm-board $tv)"
else
  warn ".icm/template-version absent — currency unknown until icm-sync.sh --apply (or setup.sh --fix --template) writes it"
fi
[ -n "$tmpl_dir" ] && info "template source: $tmpl_note" || info "SKIP template (no source) — every in-repo check still runs; pass --template <path|url> to seed or compare"

# From here on every script this report calls is the repo's own — seeded a moment ago on --fix.
[ -x "$repo_root/.icm/scripts/env-check.sh" ] && here="$repo_root/.icm/scripts"

# --- 2. formatter exposure ---------------------------------------------------------------------------------------
echo "[2/11] Formatter exposure — would a formatter rewrite a template-owned file?"
t_paths=".icm/stages/ .icm/lanes/ .icm/_shared/ .icm/skills/ .icm/intake/CONTEXT.md .icm/scripts/ .icm/MANIFEST .claude/skills/ .github/pull_request_template.md opencode.jsonc"
fmt_cfg=""
for c in .prettierrc .prettierrc.json .prettierrc.js .prettierrc.cjs .prettierrc.yaml .prettierrc.yml prettier.config.js prettier.config.mjs biome.json biome.jsonc; do [ -f "$c" ] && fmt_cfg="${fmt_cfg:+$fmt_cfg }$c"; done
[ -f package.json ] && jq -e '.prettier' package.json >/dev/null 2>&1 && fmt_cfg="${fmt_cfg:+$fmt_cfg }package.json#prettier"
if [ -z "$fmt_cfg" ]; then ok "no formatter config at the root — nothing can rewrite the template-owned files"
else
  excluded=0
  { [ -f .prettierignore ] && grep -qE '^\.?/?\.icm/?' .prettierignore; } && excluded=1
  { [ -f biome.json ] && grep -q '!\*\*/\.icm' biome.json; } && excluded=1
  { [ -f biome.jsonc ] && grep -q '!\*\*/\.icm' biome.jsonc; } && excluded=1
  if [ "$excluded" -eq 1 ]; then ok "formatter ($fmt_cfg) excludes .icm/ — the template-owned paths are safe"
  else
    warn "formatter config present ($fmt_cfg) and no exclusion for the template-owned paths — a pre-commit format re-drifts every contract (D17/D19). Add BY HAND, never by script:"
    echo "         .prettierignore (Prettier):"; for p in $t_paths .icm/runs/; do echo "           $p"; done
    echo "         biome.json (Biome, files.includes): \"!**/.icm/**\", \"!**/.claude/skills/**\", \"!**/opencode.jsonc\", \"!**/.github/pull_request_template.md\""
  fi
fi

# --- 3. project.json ----------------------------------------------------------------------------------------------
echo "[3/11] project.json — the values a script reads"
if [ -f .icm/project.json ]; then
  [ -n "$(project_field .name)" ] && ok "name: $(project_field .name)" || fail "name is empty — the repo's short name (its folder name)"
  case "$(project_field .complexity standard)" in micro|standard) ok "complexity: $(project_field .complexity standard)" ;; *) fail "complexity must be micro|standard (is '$(project_field .complexity)') — is this a one-page site or a script repo (micro)?" ;; esac
  [ -n "$(project_list .required_checks)" ] && ok "required_checks: $(project_list .required_checks | paste -sd', ' -)" || warn "required_checks is empty — which check-run names must be green before a merge? (ci-status.sh waits for none until you say)"
  [ -n "$(project_list .personas)" ] && ok "personas: $(project_list .personas | paste -sd', ' -)" || info "personas empty — no persona labels are projected (fine for a repo with one kind of user)"
  if project_has '.deploy.projects'; then ok "deploy: $(deploy_projects | jq -r '.name + " (" + (.class // "product") + ")"' | paste -sd', ' -) on $(deploy_team) via \$$(deploy_token_env)"
    deploy_projects | jq -r 'select((.status_context // "") == "" or (.production_url // "") == "") | .name' | while read -r n; do [ -n "$n" ] && warn "deploy.projects[$n]: status_context or production_url empty — which commit-status context does it post, and where is production?"; done
  else warn "deploy not declared — which Vercel project(s) does this repo deploy as, on which team, under which token NAME? (deploy-status.sh, env.sh and rollback.sh stop without it)"; fi
  if jq -e '.reporting' .icm/project.json >/dev/null 2>&1; then ok "reporting: announce → $(reporting_channels announce | paste -sd', ' -) · alert → $(reporting_channels alert | paste -sd', ' - | sed 's/^$/none (red job)/') · from $(project_field .reporting.announce_from session)"
  else warn "reporting block absent — read as announce: [github-release], alert: none; add the block to change it"; fi
  if [ -n "$(migrations_paths)" ]; then ok "migrations: $(migrations_paths | paste -sd', ' -) · reversible: $(migrations_reversible) · stamp: $(migrations_stamp) · tool: $(migrations_tool) · out_of_order: $(migrations_out_of_order)"; else info "migrations.path empty — check-migrations.sh looks for tracked migrations/ folders; rollback.sh assumes forward-only (reversible: false); stamp: $(migrations_stamp), tool: $(migrations_tool)"; fi
  case "$(database_isolation)" in
    none) warn "database.isolation: none — does this repo have a database? neon (one Neon branch per run — curl and the key named by database.neon.api_key_env, no psql), database (one MongoDB database per run on the repo's cluster — node and its driver), schema (one Postgres schema per run on \$$(database_url_env)) or container (one local Postgres per run) gives each run its own; none is right for a repo without one" ;;
    database) if [ "$(database_provider)" = mongodb ]; then ok "database: database isolation — run_<slug> on the cluster \$$(database_url_env) names, migrated and seeded by the repo's own commands"; else fail "database.isolation is database but database.provider is not mongodb — set provider: mongodb and the database.mongodb block"; fi ;;
    neon) if [ "$(database_provider)" = neon ]; then ok "database: neon isolation — run/<slug> branches of $(neon_split && echo "the UAT database, in the non-production project" || neon_production_branch), via \$$(database_url_env)"; else fail "database.isolation is neon but database.provider is not — set provider: neon and database.neon.project_id"; fi ;;
    *)    ok "database: $(database_isolation) isolation via \$$(database_url_env)$( [ "$(database_isolation)" = container ] && echo " · $(database_image), db $(database_name)")" ;;
  esac
  if [ "$(database_provider)" = neon ]; then
    if [ -z "$(neon_project_id)" ]; then fail "database.provider is neon but database.neon.project_id is empty — the Neon project id (Neon Console → Settings; a Vercel-managed database: Storage → Open in Neon)"
    else
      ok "neon: project $(neon_project_id) · key \$$(neon_api_key_env) · production branch $(neon_production_branch) · previews $(neon_previews)$( [ -n "$(neon_split && neon_nonprod_project_id)" ] && echo " · non-production project $(neon_nonprod_project_id) (UAT, previews, runs)")"
      # shellcheck source=lib/neon.sh
      if source "$here/lib/neon.sh" 2>/dev/null && neon_ready; then
        # Production's project first (read only); with UAT the previews live in the other one (D41).
        np_project="$neon_project"; neon_use_project "$neon_prod_project"
        nb="$(neon_branches 2>/dev/null)" || nb=""
        neon_use_project "$np_project"
        nnb="$nb"; neon_split && { nnb="$(neon_branches 2>/dev/null)" || nnb=""; }
        if [ -z "$nb" ]; then warn "neon: project $(neon_project_id) could not be read via \$$(neon_api_key_env) — .icm/scripts/lib/neon.sh --check says why"
        elif [ -z "$nnb" ]; then warn "neon: the non-production project $np_project could not be read via \$$(neon_api_key_env) — the key must reach both projects (.icm/scripts/lib/neon.sh --check)"
        else
          if printf '%s' "$nb" | jq -e --arg n "$(neon_production_branch)" '[.[] | select(.name == $n)] | length > 0' >/dev/null; then
            ok "neon: production branch $(neon_production_branch) present, $(printf '%s' "$nb" | jq -r --arg n "$(neon_production_branch)" '[.[] | select(.name == $n)] | first | if .protected then "protected" else "not protected (db-env.sh init)" end')"
          else fail "neon: no branch named $(neon_production_branch) in project $(neon_project_id) — database.neon.production_branch names it"; fi
          if neon_split && [ "$np_project" != "$neon_prod_project" ]; then
            ns="$(printf '%s' "$nb" | jq '[.[] | select(.name | test("^(preview|run)/"))] | length')"
            [ "$ns" -eq 0 ] || warn "neon: production's project carries $ns preview/* or run/* branch(es) — its database still branches previews, or they predate D41 (db-env.sh status lists them; the pipeline never deletes there)"
            ok "neon: UAT database $(printf '%s' "$nnb" | jq -r '[.[] | select(.default == true)] | first | "\(.name) (\(.id))"') — the default branch of $np_project"
          fi
          if [ "$(neon_previews)" = vercel ]; then
            np="$(printf '%s' "$nnb" | jq '[.[] | select(.name | startswith("preview/"))] | length')"
            if [ "$np" -gt 0 ]; then ok "neon: preview branching is live — $np preview/* branch(es)"
            else warn "neon: no preview/* branch yet — is the Vercel integration's Preview branching enabled? (db-env.sh init lists the toggle); until it is, previews share the Preview environment's database"; fi
          fi
        fi
      elif neon_split && [ -z "$(neon_nonprod_project_id)" ]; then
        info "neon: branches not read — the non-production project is not declared (uat, below)"
      else
        info "neon: \$$(neon_api_key_env) unset in this shell (or curl missing) — names checked, branches not read; export it and re-run, or db-env.sh status"
      fi
    fi
  fi
  if [ "$(database_provider)" = mongodb ]; then
    mp="$(mongo_production_name)"; ms="$(mongo_preview_name)"
    if [ -z "$mp" ] || [ -z "$ms" ]; then fail "database.provider is mongodb but database.mongodb.production_name or preview_name is empty — the names of the two long-lived databases (never dropped or reset; every drop refuses them by name)"
    elif [ "$mp" = "$ms" ]; then fail "database.mongodb.production_name and preview_name are the same ($mp) — previews would share production's database"
    else ok "mongodb: cluster via \$$(database_url_env) · production $mp · shared preview $ms · name via \$$(mongo_name_env) · previews $(mongo_previews)$( [ -n "$(mongo_uat_database)" ] && echo " · UAT $(mongo_uat_database)") · caps $(mongo_limit_databases)/$(mongo_limit_collections) · names ≤ $(mongo_limit_name_bytes)B"; fi
    { [ -n "$(mongo_seed_command)" ] && [ -n "$(mongo_migrate_command)" ]; } && ok "mongodb: seed \`$(mongo_seed_command)\` · migrate \`$(mongo_migrate_command)\`" \
      || fail "database.mongodb.seed_command or migrate_command is empty — the repo's own commands (the migrate command takes up [<name>] [--single] and down <name> [--single]); the template never designs seeding"
    [ "$(migrations_tool)" = mongodb ] || warn "database.provider is mongodb but migrations.tool is $(migrations_tool) — db-branch.sh prove reads the epoch form a MongoDB runner writes (migrations.stamp: epoch, tool: mongodb)"
    ue="$(database_url_env)"
    if [ -n "${!ue:-}" ] && command -v node >/dev/null 2>&1; then
      if ml="$(node "$here/lib/mongo.mjs" list 2>/dev/null)"; then
        for n in "$mp" "$ms"; do [ -z "$n" ] || { printf '%s' "$ml" | jq -e --arg n "$n" 'any(.[]; .name == $n)' >/dev/null && ok "mongodb: $n present" || warn "mongodb: no database named $n on the cluster — is the name right?"; }; done
        ok "mongodb: $(printf '%s' "$ml" | jq 'length') database(s), $(printf '%s' "$ml" | jq --arg a "$ms" --arg b "$mp" '[.[] | select((.name | test("^(run|preview)_")) and .name != $a and .name != $b)] | length') of them the pipeline's (db-env.sh status)"
      else warn "mongodb: the cluster could not be read via \$$(database_url_env) — node .icm/scripts/lib/mongo.mjs check says why (the repo's dependencies installed?)"; fi
    else info "mongodb: \$$(database_url_env) unset in this shell (or node missing) — names checked, the cluster not read; export it and re-run, or db-env.sh status"; fi
  fi
  [ -n "$(security_audit_command)" ] && ok "security.audit_command: $(security_audit_command)" || info "security.audit_command empty — security-check.sh audits npm/pnpm/yarn lockfiles it finds; set it for another ecosystem (pip-audit, cargo audit)"
  ok "support: tier $(support_tier)$( [ -n "$(support_failsafe)" ] && echo " · fail-safe $(support_failsafe)") · sentry via \$$(support_sentry_env)"
  # The retired branch model (D31, retired by D39) is a failure, never a fallback.
  project_has '.uat.branch' && fail "uat.branch is set — the branch model is retired (D39): main is the only long-lived branch; UAT is a Vercel custom environment declared as uat: {target, url} (/setup). Merge the UAT branch into main per the cutover checklist, then replace the key"
  project_has '.database.neon.uat_branch' && fail "database.neon.uat_branch is set — the named-branch UAT database is retired (D41): a branch of production's project sent every UAT build to production. The UAT database is a second Marketplace database: declare its Neon project as database.neon.nonprod_project_id and remove the key (db-env.sh init lists the acts)"
  [ -e .icm/uat/batch.json ] && fail ".icm/uat/batch.json exists — the batch file is retired (D39): the batch is git log <last published release>..origin/main. Remove it by hand (git rm -r .icm/uat)"
  if project_has '.uat.target' && ! project_has '.uat.url'; then fail "uat.target is '$(project_field .uat.target)' but uat.url is empty — both, or neither: the url is the domain attached to the custom environment"
  elif project_has '.uat.url' && ! project_has '.uat.target'; then fail "uat.url is '$(project_field .uat.url)' but uat.target is empty — both, or neither: the target is the Vercel custom environment's slug"
  elif uat_declared; then
    ok "uat: target $(uat_target) → $(uat_url) (every merge deploys there; production is promoted when the operator publishes the Release promote.sh approve drafts — _shared/promotion.md)"
    case "$(database_provider)" in
      neon)    if [ -z "$(neon_nonprod_project_id)" ]; then fail "uat is declared but database.neon.nonprod_project_id is empty — the Neon project of the second Marketplace database ('uat-$(project_field .name)', connected to '$(uat_target)' + Preview): UAT is its default branch, previews and runs live in it (D41; db-env.sh init lists the acts)"
               elif [ "$(neon_nonprod_project_id)" = "$(neon_project_id)" ]; then fail "database.neon.nonprod_project_id is production's project ($(neon_project_id)) — UAT, previews and runs must live in a second Marketplace database, never production's (D41)"
               else ok "uat database: the default branch of Neon project $(neon_nonprod_project_id) — a second Marketplace database; production's $(neon_project_id) is read, never written (D41)"; fi
               [ -n "$(neon_reset_command)" ] && ok "neon: reset_command \`$(neon_reset_command)\` — db-env.sh reset-uat --apply re-makes the UAT database with it" \
                 || info "neon: reset_command empty — db-env.sh reset-uat says SKIP; which command empties the UAT database and re-migrates and re-seeds it (prisma: npx prisma migrate reset --force)?" ;;
      mongodb) [ -n "$(mongo_uat_database)" ] && ok "uat database: $(mongo_uat_database)" || fail "uat is declared but database.mongodb.uat_name is empty — the database behind the UAT environment (D39 (3); 'uat' by convention)" ;;
    esac
    # The environment and the plan, read once where a Vercel token is in reach — names only.
    if project_has '.deploy.projects' && command -v curl >/dev/null 2>&1; then
      # shellcheck source=lib/vercel.sh
      if source "$here/lib/vercel.sh" 2>/dev/null && [ -n "$vercel_token" ]; then
        while IFS= read -r pn; do
          [ -n "$pn" ] || continue
          ce="$(vercel_get "/v9/projects/$pn/custom-environments" 2>/dev/null)" || ce=""
          if [ "$(printf '%s' "$ce" | tail -n1)" != "200" ]; then warn "vercel: custom environments of $pn could not be read (HTTP $(printf '%s' "$ce" | tail -n1)) — lib/vercel.sh --check says why"; continue; fi
          ce="$(printf '%s' "$ce" | sed '$d')"
          lim="$(printf '%s' "$ce" | jq -r '(.accountLimit.total // 0) | tonumber? // 0')"
          if [ "$lim" -lt 1 ]; then fail "vercel: $pn allows $lim custom environment(s) — UAT requires a Pro team (D39 (2)); undeclare uat, or move the project"
          elif printf '%s' "$ce" | jq -e --arg t "$(uat_target)" 'any((.environments // [])[]; .slug == $t)' >/dev/null; then
            ok "vercel: $pn has the custom environment $(uat_target)$(printf '%s' "$ce" | jq -r --arg t "$(uat_target)" '[(.environments // [])[] | select(.slug == $t)] | first | ((.domains // []) | map(.name) | if length > 0 then " · domains " + join(", ") else " · no domain attached yet (promote.sh init)" end)')"
          else fail "vercel: $pn has no custom environment '$(uat_target)' ($lim allowed) — the operator creates it (promote.sh init lists the acts)"; fi
          # D41: production's database is connected to Production only. Its variable (url_env) must
          # target production alone — a Preview or custom-environment scope on the same entry means
          # production's database reaches UAT. Names and targets only; values are never read.
          if [ "$(database_provider)" = neon ]; then
            ue="$(database_url_env)"
            if envs="$(vercel_get_all "/v9/projects/$pn/env" envs "" '{key, target: (.target // []), ce: (.customEnvironmentIds // [])}' 2>/dev/null)"; then
              pe="$(printf '%s' "$envs" | jq -c --arg k "$ue" '[.[] | select(.key == $k and (.target | index("production")))]')"
              if [ "$(printf '%s' "$pe" | jq 'length')" -eq 0 ]; then todo "vercel: $pn shows no \$$ue on Production — the API cannot say how production's database is connected; check it by hand: Storage → production's database → Production only, preview branching off (D41)"
              elif printf '%s' "$pe" | jq -e 'any(.[]; (.target | length) > 1 or (.ce | length) > 0)' >/dev/null; then fail "vercel: $pn's production \$$ue also targets $(printf '%s' "$pe" | jq -r '[.[] | (.target - ["production"])[], (if (.ce | length) > 0 then "a custom environment" else empty end)] | unique | join(", ")') — production's database is connected beyond Production and reaches UAT (D41): Storage → production's database → its connection → Production only"
              else ok "vercel: $pn's production \$$ue targets Production only (D41)"; fi
            else todo "vercel: the variables of $pn could not be read — the API cannot say how production's database is connected; check it by hand (D41)"; fi
          fi
        done < <(deploy_projects | jq -r 'select((.class // "product") == "product") | .name')
      else info "vercel: no token in this shell — the custom environment and the Pro plan are not checked; export \$$(deploy_token_env) and re-run"; fi
    fi
  else
    info "uat: not declared — every merge to main is the production release; /setup declares uat: {target, url} for a client UAT environment on a Pro team (_shared/promotion.md)"
  fi
  if [ -n "$(health_endpoints | head -n1)" ]; then ok "health_endpoint: $(health_endpoints | paste -sd', ' -) — health-check.sh reads it once after the merge"
  elif project_has '.deploy.projects'; then warn "health_endpoint empty while deploy is declared — which URL on each production project answers 200 when it is up (e.g. https://<production_url>/api/health)? Until it is set, health-check.sh reports SKIP after every merge and nobody is told production is down"
  else info "health_endpoint empty — health-check.sh reports SKIP after the merge; set it with the deploy block (which URL answers 200 when production is up?)"; fi
  jq -e '.profile' .icm/project.json >/dev/null 2>&1 && info "a \"profile\" key is present and ignored (D22) — remove it when convenient"
else
  fail ".icm/project.json missing — the manifest every script reads"
fi

# --- 4. environment ---------------------------------------------------------------------------------------------
echo "[4/11] Environment — the route, the binaries, the keys (names only)"
if [ -x "$here/env-check.sh" ]; then r="$(last_line "$here/env-check.sh")"; case "$r" in *PASS*) ok "env-check.sh → $r" ;; *) fail "env-check.sh → ${r:-no verdict} (run it for the lines)" ;; esac; else fail "env-check.sh missing"; fi
if [ -x "$here/env.sh" ]; then r="$(last_line "$here/env.sh" audit)"; case "$r" in *"RESULT: OK"*) ok "env.sh audit → $r" ;; *GAPS*) warn "env.sh audit → $r (run .icm/scripts/env.sh audit for the rows — each names its fix)" ;; *UNKNOWN*) warn "env.sh audit → $r (a surface could not be read — env-check.sh above says whether the token sees every project)" ;; *) info "env.sh audit → ${r:-no verdict}" ;; esac; else fail "env.sh missing"; fi

# --- 5. tickets ---------------------------------------------------------------------------------------------------
echo "[5/11] Tickets — every live epic's bookkeeping, the parking lane, nothing loose"
if [ -x "$here/validate-intake.sh" ]; then
  n_epics=0
  for d in .icm/intake/*/; do
    [ -d "$d" ] || continue; e="$(basename "$d")"; case "$e" in _done|triage) continue ;; esac
    n_epics=$((n_epics+1)); r="$(last_line "$here/validate-intake.sh" "$e")"; case "$r" in *"RESULT: OK"*|*SKIP*) ok "epic $e → $r" ;; *) fail "epic $e → ${r:-no verdict}" ;; esac
  done
  [ "$n_epics" -gt 0 ] || info "no live epics in .icm/intake/"
  if [ -d .icm/intake/triage ] && ls .icm/intake/triage/*.md >/dev/null 2>&1; then
    r="$(last_line "$here/validate-intake.sh" .icm/intake/triage)"; case "$r" in *"RESULT: OK"*) ok "triage/ → $r" ;; *) fail "triage/ → ${r:-no verdict} (a stub without a valid lane: nothing can consume it)" ;; esac
    [ -x "$here/triage-report.sh" ] && { r="$(last_line "$here/triage-report.sh")"; case "$r" in *"over"*|*"cap"*"exceeded"*) warn "triage-report.sh → $r" ;; *) ok "triage-report.sh → ${r:-ran}" ;; esac; }
  else info "triage/ is empty"; fi
fi
for loose in TODO.md BACKLOG.md; do [ -f "$loose" ] && fail "loose $loose at the root — planning is stubs in .icm/intake/, never a loose file"; done

# --- 6. raw -------------------------------------------------------------------------------------------------------
echo "[6/11] Raw — what a client sent and nothing has read yet"
if [ -x "$here/process-raw.sh" ]; then
  out="$("$here/process-raw.sh" --dry-run 2>/dev/null)"; r="$(printf '%s\n' "$out" | tail -n1)"
  case "$r" in *EMPTY*) ok "process-raw.sh → nothing waiting" ;; *) info "process-raw.sh → $r"; printf '%s\n' "$out" | grep -E '^\s+skipped' | sed 's/^/         /' ;; esac
fi
media="$(git ls-files .icm/raw 2>/dev/null | grep -iE '\.(mp4|mov|m4a|mp3|wav|webm|mkv|aac|ogg|opus|amr|flac)$' || true)"
[ -z "$media" ] && ok "no media tracked under .icm/raw/" || warn "media tracked under .icm/raw/ — recordings are never committed (git rm --cached, add the pattern to .gitignore; keep the transcript): $(printf '%s' "$media" | paste -sd', ' -)"

# --- 7. runs ------------------------------------------------------------------------------------------------------
echo "[7/11] Runs — live folders hold only live work"
gh_ok=0
if [ -d .icm/runs ]; then
  if source "$here/lib/gh.sh" 2>/dev/null && { [ -n "${gh_token:-}" ] || (command -v gh >/dev/null 2>&1 && env -u GITHUB_TOKEN -u GH_TOKEN gh auth status >/dev/null 2>&1); }; then gh_ok=1; fi
  n_live=0
  for d in .icm/runs/*/; do
    [ -d "$d" ] || continue; s="$(basename "$d")"; [ "$s" = "_done" ] && continue; [ -f "$d/run.md" ] || continue
    n_live=$((n_live+1))
    pr="$(grep -m1 '^- pr:' "$d/run.md" | sed -E 's/^- pr:[[:space:]]*//; s#^.*/pull/##; s/^#//; s/[^0-9].*$//' || true)"
    if [ -n "$pr" ] && [ "$gh_ok" -eq 1 ]; then
      st="$(gh_api GET "/repos/${repo}/pulls/${pr}" 2>/dev/null | sed '$d' | jq -r 'if .merged then "merged" else (.state // "unknown") end' 2>/dev/null)"
      case "$st" in merged) fail "run $s: PR #$pr merged but the run is still in .icm/runs/ — the close-out was missed (a fault in that Release; close-out.sh on a branch)" ;; closed) warn "run $s: PR #$pr closed unmerged — an abandoned run is not history; delete the folder deliberately or reopen" ;; *) ok "run $s: PR #$pr $st" ;; esac
    elif [ -n "$pr" ]; then info "run $s: PR #$pr (state not read — no GitHub route in this environment)"
    else info "run $s: a front (no PR)"; fi
    if [ -f "$d/usage.md" ]; then
      open_pairs="$(awk '/^- usage: /{k=$3"|"$5; for(i=6;i<=NF;i++){split($i,kv,"="); if(kv[1]=="session")k=$3"|"kv[2]} if($4=="start")s[k]=1; if($4=="end")e[k]=1} END{n=0; for(k in s) if(!(k in e)) n++; print n}' "$d/usage.md")"
      [ "$open_pairs" = "0" ] || info "run $s: $open_pairs stage(s) with a usage start and no end (still running, or resumed elsewhere)"
    fi
  done
  [ "$n_live" -gt 0 ] || ok "no live runs"
else info "no .icm/runs/ yet"; fi

# --- 8. knowledge ---------------------------------------------------------------------------------------------------
echo "[8/11] Knowledge — the map resolves"
if [ -x "$here/validate-knowledge-map.sh" ]; then r="$(last_line "$here/validate-knowledge-map.sh")"; case "$r" in *"RESULT: OK"*|*SKIP*) ok "validate-knowledge-map.sh → $r" ;; *) fail "validate-knowledge-map.sh → ${r:-no verdict}" ;; esac; else fail "validate-knowledge-map.sh missing (P)"; fi

# --- 9. reporting ----------------------------------------------------------------------------------------------------
echo "[9/11] Reporting — kinds, channels, variables"
for kind in announce alert economics; do
  chans="$(reporting_channels "$kind" | paste -sd' ' -)"
  if [ -z "$chans" ]; then
    if [ "$kind" = "alert" ]; then
      grep -qiE 'red job|red CI job|no alert channel|alert.*none' .icm/_shared/project-rules.md 2>/dev/null && ok "alert → none, recorded in project-rules.md (the red CI job is the alert)" || warn "alert → none and project-rules.md does not record the red-job default — write it under Reporting so 'none' is a decision, not a hole"
    else info "$kind → none"; fi
    continue
  fi
  ok "$kind → $chans"
  for ch in $chans; do case "$ch" in slack|email)
    for var in $(jq -r ".reporting.channels[\"$ch\"] // {} | to_entries[] | select(.key | endswith(\"_env\")) | .value" .icm/project.json 2>/dev/null); do
      [ -n "${!var:-}" ] && ok "$ch: $var set here" || info "$ch: $var unset in this shell — report.sh prints SKIPPED $ch until it exists where it runs (env.sh add $var --ci)"
    done ;; esac; done
done
af="$(project_field .reporting.announce_from session)"
has_release=0; { [ -f .github/workflows/release.yaml ] || [ -f .github/workflows/release.yml ]; } && has_release=1
if uat_declared; then
  # On a UAT repo the merge announces nothing and the release workflow IS the promotion (D39 (5)).
  [ "$has_release" -eq 1 ] && ok "uat: the release workflow exists — it promotes and announces when the operator publishes a Release (announce_from applies to no-UAT repos only)" || fail "uat is declared but no .github/workflows/release.yaml — nothing promotes a published Release (/setup seeds the reference github-pipeline/workflows/release.yaml)"
elif [ "$af" = "ci" ]; then [ "$has_release" -eq 1 ] && ok "announce_from: ci and a release workflow exists" || fail "announce_from: ci but no .github/workflows/release.yaml — nothing announces (seed the reference workflow, or set session)"
else [ "$has_release" -eq 1 ] && warn "announce_from: session but .github/workflows/release.yaml exists — its merge job announces only with announce_from: ci, so it is idle here; set announce_from: ci or remove the workflow" || ok "announce_from: session (Release step 9 calls report.sh)"; fi

# --- 10. workflows -----------------------------------------------------------------------------------------------------
echo "[10/11] Workflows — the reference workflows, present or declared absent"
for wf in release labels; do
  if [ -f ".github/workflows/$wf.yaml" ] || [ -f ".github/workflows/$wf.yml" ]; then ok "$wf workflow present"
  elif grep -qiE "$wf(\.yaml|\.yml)?.*(absent|none|not (used|seeded)|no )" .icm/_shared/project-rules.md 2>/dev/null; then ok "$wf workflow declared absent in project-rules.md"
  else info "$wf workflow absent and project-rules.md does not say so — /setup seeds the reference one (announce_from: ci) or records the absence"; fi
done
if [ "$(database_provider)" = neon ] && [ "$(neon_previews)" = vercel ]; then
  if [ -f .github/workflows/neon-cleanup.yaml ] || [ -f .github/workflows/neon-cleanup.yml ]; then ok "neon-cleanup workflow present (deletes preview/<branch> and run/<slug> when a PR closes)"
  elif grep -qiE "neon-cleanup(\.yaml|\.yml)?.*(absent|none|not (used|seeded)|no )" .icm/_shared/project-rules.md 2>/dev/null; then ok "neon-cleanup workflow declared absent in project-rules.md"
  elif [ "$FIX" -eq 1 ] && [ -n "$tmpl_dir" ] && [ -f "$tmpl_dir/github-pipeline/workflows/neon-cleanup.yaml" ]; then seed "$tmpl_dir/github-pipeline/workflows/neon-cleanup.yaml" .github/workflows/neon-cleanup.yaml
  else warn "neon-cleanup workflow absent — the Vercel-managed integration keeps a preview branch until its deployment expires (months); setup.sh --fix --template <path> seeds the reference one, or record the absence in project-rules.md → Reporting → Workflows"; fi
fi
if [ "$(database_provider)" = mongodb ] && [ "$(mongo_previews)" = branch ]; then
  if [ -f .github/workflows/mongodb-cleanup.yaml ] || [ -f .github/workflows/mongodb-cleanup.yml ]; then ok "mongodb-cleanup workflow present (drops preview_<branch> and run_<slug> when a PR closes)"
  elif grep -qiE "mongodb-cleanup(\.yaml|\.yml)?.*(absent|none|not (used|seeded)|no )" .icm/_shared/project-rules.md 2>/dev/null; then ok "mongodb-cleanup workflow declared absent in project-rules.md"
  elif [ "$FIX" -eq 1 ] && [ -n "$tmpl_dir" ] && [ -f "$tmpl_dir/github-pipeline/workflows/mongodb-cleanup.yaml" ]; then seed "$tmpl_dir/github-pipeline/workflows/mongodb-cleanup.yaml" .github/workflows/mongodb-cleanup.yaml
  else warn "mongodb-cleanup workflow absent — nothing drops a closed PR's preview_<branch> database; setup.sh --fix --template <path> seeds the reference one, or record the absence in project-rules.md → Reporting → Workflows"; fi
fi
if [ -f .github/labels.yml ]; then
  for l in type:hotfix type:handover; do
    if grep -q "$l" .github/labels.yml; then ok "$l in .github/labels.yml"
    else warn "$l missing from .github/labels.yml — add it (and create the label once in GitHub) before the lane's first PR"; fi
  done
  grep -q 'type:promote' .github/labels.yml && info "type:promote in .github/labels.yml — retired with the promotion PR (D39); remove it when convenient"
else info "no .github/labels.yml — the label vocabulary is not documented here (new-run.sh dies if a type:<lane> label does not exist in GitHub)"; fi
# D39 (5): on a UAT repo production migrates at the promotion, never on the push to main.
if uat_declared; then
  mig=""; for f in .github/workflows/db-migrate.yml .github/workflows/db-migrate.yaml; do [ -f "$f" ] && mig="$f"; done
  if [ -z "$mig" ]; then info "no .github/workflows/db-migrate.yml — the release workflow's migrate job must be removed if production has no migrator (the reference release.yaml calls it)"
  elif grep -q 'workflow_call' "$mig"; then ok "$mig is callable (workflow_call) — the release workflow migrates production before it promotes"
  else fail "$mig has no workflow_call trigger — on a UAT repo production migrates at the promotion, not on push to main (D39 (5)); take the reference github-pipeline/workflows/db-migrate.yml shape"; fi
fi

# --- 11. support -------------------------------------------------------------------------------------------------------
echo "[11/11] Support — what the deal promised after handover"
tier="$(support_tier)"
if [ "$(project_field .complexity standard)" = "micro" ] && [ "$tier" = "none" ]; then info "micro: no support line"
else
  case "$tier" in
    none) ok "support.tier: none — no after-handover line (a landing page, or a client-owned pattern on a retainer)" ;;
    basic|retainer)
      fs="$(support_failsafe)"
      if [ -z "$fs" ]; then warn "support.tier $tier but failsafe_page is undeclared — which page says 'technical difficulties' when the app is down? (basic support requires it)"
      elif [ -e "$fs" ] || ls "$fs"* >/dev/null 2>&1; then ok "fail-safe page: $fs"
      else fail "support.failsafe_page '$fs' declared but absent — basic support requires the fail-safe page (Release stop class 3)"; fi
      sv="$(support_sentry_env)"
      if grep -rqsE "^${sv}=" --include=.env.example . 2>/dev/null; then
        grep -rhsB3 -E "^${sv}=" --include=.env.example . | grep -q '\[.*production' && ok "$sv declared in .env.example [production]" || warn "$sv declared in .env.example but not scoped [production] — Sentry is a production key"
      else fail "$sv (support.monitoring.sentry_dsn_env) is not declared in any .env.example — basic support requires Sentry (env.sh doc $sv --targets production)"; fi
      if [ -n "$(reporting_channels alert)" ]; then ok "alert maps to $(reporting_channels alert | paste -sd', ' -)"
      elif grep -qiE 'red job|red CI job' .icm/_shared/project-rules.md 2>/dev/null; then ok "alert → none, the red-job default recorded"
      else fail "support.tier $tier with alert → none and no recorded red-job default — a crash must reach someone: map alert to a channel, or record the default in project-rules.md → Reporting"; fi ;;
    *) fail "support.tier must be none|basic|retainer (is '$tier')" ;;
  esac
fi

echo "-------------------------------------------------"
if [ "$gaps" -eq 0 ]; then echo "RESULT: OK ($warns warnings)"; else echo "RESULT: GAPS $gaps ($warns warnings)"; fi
exit 0
