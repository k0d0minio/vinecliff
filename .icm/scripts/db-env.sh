#!/usr/bin/env bash
# db-env.sh — the environments' databases, as the repo declares them: production, UAT, previews, runs (TEMPLATE-OWNED).
#
# Only where the repo declares a Neon project (.icm/project.json → database.provider: neon and
# database.neon.project_id; /setup asks; decision D32). Without one every verb prints one line and
# RESULT: SKIP, exit 0: the database is whatever each deployment's variables name, as it always was.
#
# The topology, one home per fact (D24 — the names in project.json, the state in Neon):
#   production   the project's production branch (database.neon.production_branch, `main` by
#                default) — NEVER written, deleted or reset by anything in the pipeline.
#   UAT          where the repo declares uat.branch and database.neon.previews is `vercel`, the Neon
#                branch `preview/<uat.branch>` — CREATED BY THE VERCEL INTEGRATION on the UAT git
#                branch's first deployment, a copy of production at that moment, persistent as long
#                as the branch deploys. Nothing here creates it; `reset-uat` brings it back to
#                production's latest state on the operator's call (uat/CONTEXT.md → The UAT database).
#   previews     `preview/<git-branch>`, one per preview deployment, created and wired by the Vercel
#                integration (its Preview-branching toggle — an operator act `init` lists). The
#                reference workflow .github/workflows/neon-cleanup.yaml deletes one when its PR
#                closes; `prune` deletes the ones whose git branch is gone.
#   runs         `run/<slug>`, one per live run, created by db-branch.sh up (database.isolation:
#                neon) as a child of PRODUCTION with a 7-day expiry — never a child of UAT, so a UAT
#                reset is never blocked by them — and deleted by down; `prune` deletes the ones
#                whose run is archived or whose expiry passed unnoticed.
#
# Verbs:
#   status       (default) the branches by role — production (protected or not), the UAT branch
#                (present, or not yet), preview branches (count, newest), run branches (each with
#                its expiry and whether its run is still live) and every other branch by name (not
#                the pipeline's — yours). With a Vercel token in reach, the product project's build
#                command: the place previews and UAT apply their migrations. Read-only.
#                          RESULT: NEON <n> branch(es) · production <name> · uat <state> · previews <n> · runs <n>
#   init         prints the one-time acts only the operator can perform — the API key and where it
#                lives, the integration's Preview-branching toggle, the build command that applies
#                migrations, protecting the production branch, the cleanup workflow — and, with the
#                key in reach, reads the project once to say which are done. Writes nothing.
#                                                                                       RESULT: INIT
#   reset-uat [--apply]
#                reset the UAT branch from its parent (production): the client's test data is
#                gone and production's shape is back. Dry-run by default. Refuses a branch that
#                has children (Neon's rule) and never touches the production branch.
#                                                                         RESULT: DRY-RUN | RESET | SKIP
#   prune [--apply] [--days <n>]
#                delete run/* branches whose run is no longer live (or older than <n> days, default
#                7) and preview/* branches whose git branch no longer exists on origin. Never
#                production, never the UAT branch, never a name the pipeline did not give. Dry-run
#                by default.                                RESULT: DRY-RUN <n> | PRUNED <n> | UNCHANGED
#
# What never happens here: production is never written; the UAT branch is never created or deleted
# (the integration owns its birth; a reset is the one act, and only on --apply); no branch of a
# name the pipeline did not give is touched; nothing is scheduled; nothing watches. The key's value
# never reaches argv or stdout.
#
# Usage: .icm/scripts/db-env.sh [status|init|reset-uat|prune] [--apply] [--days <n>]
# Exit:  0 reported, reset, pruned or skipped · 1 the API refused (the die message) · 2 usage
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root" || exit 2
die() { echo "error: $*" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "error: jq not found" >&2; exit 2; }

verb="status"; apply=0; days=7
while [ $# -gt 0 ]; do
  case "$1" in
    status|init|reset-uat|prune) verb="$1"; shift ;;
    --apply) apply=1; shift ;;
    --days)  days="${2:-7}"; shift 2 ;;
    -h|--help) sed -n '2,52p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "error: unknown argument: $1 (usage: db-env.sh [status|init|reset-uat|prune] [--apply] [--days <n>])" >&2; exit 2 ;;
  esac
done

# shellcheck source=lib/project.sh
source "$here/lib/project.sh"
# shellcheck source=lib/neon.sh
source "$here/lib/neon.sh"

if ! neon_declared; then
  echo "no Neon project is declared in .icm/project.json (database.provider: neon + database.neon.project_id) — the database is whatever each deployment's variables name; /setup declares one"
  echo "RESULT: SKIP"; exit 0
fi
prod_name="$(neon_production_branch)"; uat_name="$(neon_uat_branch)"; previews="$(neon_previews)"
key_state="unset here"; [ -n "$neon_key" ] && key_state="set here"

# --- init: the operator's acts, and which are done ---------------------------------------------------------
if [ "$verb" = "init" ]; then
  echo "Neon project $neon_project · key \$$neon_key_name ($key_state) · production branch $prod_name · previews $previews${uat_name:+ · UAT branch $uat_name}"
  echo
  echo "One-time setup the operator completes by hand (this script does none of it):"
  if [ -n "$neon_key" ]; then echo "  [OK]   \$$neon_key_name is set in this shell"
  else echo "  [TODO] create a Neon API key (Neon Console → Account settings → API keys; a Vercel-managed organisation needs one for every CLI or API call) and export it as $neon_key_name on the machines that drive the pipeline — never in git"; fi
  echo "  [TODO] the same key as this repository's Actions secret, for the cleanup workflow:   printf '%s' \"\$$neon_key_name\" | .icm/scripts/env.sh add $neon_key_name --ci --github secret --note 'Neon API key: deletes the PR'\"'\"'s preview and run branches on close'"
  if [ "$previews" = "vercel" ]; then
    echo "  [TODO] Vercel → Storage → the database → Connect Project → Advanced options → Deployments configuration: enable Preview, and 'Resource must be active before deployment' — the integration then creates preview/<git-branch> for every preview deployment and injects its variables at deploy time (they never appear in the project's settings)"
    echo "  [TODO] the build must apply the branch's migrations, or a preview's (and UAT's) database is production's shape without them: run the repo's migrate step before the build — the build command in Vercel (Settings → Build and Deployment), or a vercel-build script — and record the choice in _shared/project-rules.md → The factory → The run's database"
    if [ -f .github/workflows/neon-cleanup.yaml ] || [ -f .github/workflows/neon-cleanup.yml ]; then echo "  [OK]   .github/workflows/neon-cleanup.yaml present — deletes preview/<branch> and run/<slug> when a PR closes"
    else echo "  [TODO] seed the reference cleanup workflow (setup.sh --fix --template <path>, or copy github-pipeline/workflows/neon-cleanup.yaml from the template) — the Vercel-managed integration otherwise keeps a preview branch until the deployment expires, which is months"; fi
    [ -n "$uat_name" ] && echo "  [INFO] the UAT database is the Neon branch $uat_name — the integration creates it on the UAT git branch's first deployment; db-env.sh status reads it, db-env.sh reset-uat --apply resets it from production"
  else
    echo "  [INFO] database.neon.previews is none — previews and the UAT branch share the Preview environment's variables; set it to vercel and enable the integration's Preview branching for a database per preview"
  fi
  echo "  [TODO] protect the production branch in Neon (Branches → $prod_name → Protect): a protected branch cannot be deleted or reset, and its children get credentials of their own"
  if neon_ready && neon_load_branches; then
    bj="$NEON_BRANCHES"
    prot="$(printf '%s' "$bj" | jq -r --arg n "$prod_name" '[.[] | select(.name == $n)] | first | if . == null then "missing" else (.protected | tostring) end')"
    case "$prot" in
      true)    echo "  [OK]   production branch $prod_name is protected" ;;
      false)   echo "  [..]   production branch $prod_name is not protected yet" ;;
      missing) echo "  [WARN] no branch named $prod_name in project $neon_project — database.neon.production_branch names the production branch" ;;
    esac
    if [ "$previews" = "vercel" ]; then
      np="$(printf '%s' "$bj" | jq '[.[] | select(.name | startswith("preview/"))] | length')"
      if [ "$np" -gt 0 ]; then echo "  [OK]   preview branching is live: $np preview/* branch(es)"; else echo "  [..]   no preview/* branch yet — after the toggle, the next preview deployment creates the first"; fi
      if [ -n "$uat_name" ]; then
        if [ -n "$(printf '%s' "$bj" | jq -r --arg n "$uat_name" '.[] | select(.name == $n) | .id')" ]; then echo "  [OK]   UAT branch $uat_name exists"
        else echo "  [..]   UAT branch $uat_name not created yet — it arrives with the UAT git branch's first deployment"; fi
      fi
    fi
  fi
  echo "RESULT: INIT"; exit 0
fi

# --- every other verb reads the project ---------------------------------------------------------------------
if ! neon_ready; then
  if [ -z "$neon_key" ]; then echo "Neon project $neon_project is declared but \$$neon_key_name is unset in this environment — nothing can be read (db-env.sh init lists the acts; export the key, never in git)"
  else echo "Neon project $neon_project is declared but curl or jq is missing — nothing can be read"; fi
  echo "RESULT: SKIP"; exit 0
fi
neon_load_branches || exit 1
bj="$NEON_BRANCHES"
now_epoch="$(date -u +%s)"
children_of() { printf '%s' "$bj" | jq -r --arg p "$1" '[.[] | select(.parent_id == $p)] | length'; }
to_epoch() { date -u -d "$1" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || echo 0; }
prod_id="$(printf '%s' "$bj" | jq -r --arg n "$prod_name" '[.[] | select(.name == $n)] | first | .id // empty')"
uat_id=""; [ -n "$uat_name" ] && uat_id="$(printf '%s' "$bj" | jq -r --arg n "$uat_name" '[.[] | select(.name == $n)] | first | .id // empty')"

case "$verb" in

status)
  total="$(printf '%s' "$bj" | jq 'length')"
  echo "Neon project $neon_project — $total branch(es), read via \$$neon_key_name"
  if [ -n "$prod_id" ]; then
    echo "production: $prod_name ($prod_id) — $(printf '%s' "$bj" | jq -r --arg n "$prod_name" '[.[] | select(.name == $n)] | first | if .protected then "protected" else "NOT protected (db-env.sh init)" end')"
  else
    echo "production: $prod_name — [WARN] no branch of that name in the project (database.neon.production_branch)"
  fi
  uat_state="n/a"
  if [ -n "$uat_name" ]; then
    if [ -n "$uat_id" ]; then
      uat_state="present"
      echo "uat:        $uat_name ($uat_id) — parent $(printf '%s' "$bj" | jq -r --arg id "$uat_id" '[.[] | select(.id == $id)] | first | .parent_id // "?"'), created $(printf '%s' "$bj" | jq -r --arg id "$uat_id" '[.[] | select(.id == $id)] | first | .created_at // "?"'); children: $(children_of "$uat_id") (a reset needs 0)"
    else
      uat_state="not yet"
      echo "uat:        $uat_name — not created yet; the integration creates it on the UAT git branch's first deployment (promote-uat.sh init → push the branch once)"
    fi
  fi
  np="$(printf '%s' "$bj" | jq '[.[] | select(.name | startswith("preview/"))] | length')"
  if [ "$previews" = "vercel" ]; then
    if [ "$np" -gt 0 ]; then echo "previews:   $np preview/* branch(es) — newest: $(printf '%s' "$bj" | jq -r '[.[] | select(.name | startswith("preview/"))] | sort_by(.created_at) | last | "\(.name) (\(.created_at))"')"
    else echo "previews:   none yet — is the integration's Preview branching enabled? (db-env.sh init); until it is, previews share the Preview environment's database"; fi
  else
    echo "previews:   database.neon.previews is none — previews share the Preview environment's variables$( [ "$np" -gt 0 ] && echo " ($np preview/* branch(es) exist all the same — the integration is on; declare previews: vercel)")"
  fi
  nr="$(printf '%s' "$bj" | jq '[.[] | select(.name | startswith("run/"))] | length')"
  echo "runs:       $nr run/* branch(es)$( [ "$(database_isolation)" != neon ] && echo " (database.isolation is $(database_isolation), not neon — db-branch.sh makes none here)")"
  while IFS=$'\t' read -r name exp; do
    [ -n "$name" ] || continue
    slug="${name#run/}"; live="archived"; [ -d ".icm/runs/$slug" ] && live="live"
    echo "  - $name — $live · expires ${exp:-never}"
  done < <(printf '%s' "$bj" | jq -r '.[] | select(.name | startswith("run/")) | [.name, (.expires_at // "")] | @tsv')
  others="$(printf '%s' "$bj" | jq -r --arg p "$prod_name" --arg u "$uat_name" '.[] | select(.name != $p and .name != $u and (.name | startswith("preview/") | not) and (.name | startswith("run/") | not)) | .name')"
  if [ -n "$others" ]; then echo "other:      not the pipeline's — yours to keep or delete in the Neon Console:"; printf '%s\n' "$others" | sed 's/^/  - /'; fi
  # The build command, where a Vercel token is in reach — the place previews and UAT apply migrations.
  if [ -f "$here/lib/vercel.sh" ] && project_has '.deploy.projects'; then
    bc="$( ( source "$here/lib/vercel.sh"; [ -n "$vercel_token" ] || exit 0
             deploy_projects | jq -r 'select((.class // "product") == "product") | .name' | head -n1 | while read -r pn; do
               vercel_project "$pn" 2>/dev/null | jq -r '"\(.name): \(.buildCommand // "the framework default")"'
             done ) 2>/dev/null || true )"
    [ -n "$bc" ] && echo "build:      $bc — previews and UAT carry a branch's migrations only if this runs the migrate step (db-env.sh init)"
  fi
  echo "RESULT: NEON $total branch(es) · production $prod_name · uat $uat_state · previews $np · runs $nr"
  exit 0 ;;

reset-uat)
  [ -n "$uat_name" ] || { echo "no UAT database: uat.branch is not declared, or database.neon.previews is not vercel (.icm/project.json) — nothing to reset"; echo "RESULT: SKIP"; exit 0; }
  [ -n "$uat_id" ]   || { echo "UAT branch $uat_name does not exist yet — it arrives with the UAT git branch's first deployment"; echo "RESULT: SKIP"; exit 0; }
  [ "$uat_id" != "$prod_id" ] || die "the UAT branch and the production branch are the same branch — refusing"
  parent="$(printf '%s' "$bj" | jq -r --arg id "$uat_id" '[.[] | select(.id == $id)] | first | .parent_id // empty')"
  [ -n "$parent" ] || die "UAT branch $uat_name has no parent (a root branch cannot be reset)"
  kids="$(children_of "$uat_id")"
  [ "$kids" -eq 0 ] || die "UAT branch $uat_name has $kids child branch(es) — Neon refuses a reset while they exist; delete them first (they are not the pipeline's: run/* branches are children of production)"
  if [ "$apply" -eq 0 ]; then
    echo "would: reset $uat_name ($uat_id) from its parent $parent — every row and every schema change on UAT since the last reset is replaced by production's latest state; connections drop for a moment and the connection string does not change"
    echo "RESULT: DRY-RUN"; exit 0
  fi
  neon_reset_branch "$uat_id" "$parent" "$uat_name"
  echo "reset: $uat_name now carries production's latest state (the next push to the UAT git branch re-applies the branch's own migrations at build)"
  echo "RESULT: RESET"; exit 0 ;;

prune)
  n=0; would=()
  while IFS=$'\t' read -r id name exp; do
    [ -n "$name" ] || continue
    [ "$name" != "$uat_name" ] || continue
    [ "$id" != "$prod_id" ] || continue
    reason=""
    case "$name" in
      run/*)
        slug="${name#run/}"
        if [ ! -d ".icm/runs/$slug" ]; then reason="its run is no longer live"
        elif [ -n "$exp" ] && [ "$(to_epoch "$exp")" -gt 0 ] && [ "$(to_epoch "$exp")" -lt "$now_epoch" ]; then reason="expired $exp"
        fi
        if [ -z "$reason" ] && [ "$days" -gt 0 ]; then
          created="$(printf '%s' "$bj" | jq -r --arg id "$id" '[.[] | select(.id == $id)] | first | .created_at // empty')"
          [ -n "$created" ] && [ "$(( (now_epoch - $(to_epoch "$created")) / 86400 ))" -ge "$days" ] && reason="older than $days day(s)"
        fi ;;
      preview/*)
        gb="${name#preview/}"
        if ! GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code --heads origin "$gb" >/dev/null 2>&1; then reason="git branch $gb no longer exists on origin"; fi ;;
      *) continue ;;
    esac
    [ -n "$reason" ] || continue
    if [ "$apply" -eq 1 ]; then neon_delete_branch "$id" "$name"; echo "deleted: $name — $reason"
    else would+=("$name — $reason"); fi
    n=$((n + 1))
  done < <(printf '%s' "$bj" | jq -r '.[] | [.id, .name, (.expires_at // "")] | @tsv')
  if [ "$apply" -eq 0 ]; then
    if [ "$n" -eq 0 ]; then echo "nothing to prune"; echo "RESULT: UNCHANGED"; exit 0; fi
    printf 'would delete: %s\n' "${would[@]}"
    echo "RESULT: DRY-RUN $n"; exit 0
  fi
  [ "$n" -gt 0 ] && echo "RESULT: PRUNED $n" || echo "RESULT: UNCHANGED"
  exit 0 ;;
esac
