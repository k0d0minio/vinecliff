#!/usr/bin/env bash
# db-env.sh — the environments' databases, as the repo declares them: production, UAT, previews, runs (TEMPLATE-OWNED).
#
# Only where the repo declares a Neon project (.icm/project.json → database.provider: neon and
# database.neon.project_id; /setup asks; decision D32) or a MongoDB cluster (database.provider:
# mongodb; decision D35 — its own section below). Without either every verb prints one line and
# RESULT: SKIP, exit 0: the database is whatever each deployment's variables name, as it always was.
#
# MongoDB (D35) — the same verbs on the one cluster the repo already uses, every database beside the
# others, the names from database.mongodb (lib/project.sh), the transport lib/mongo.mjs:
#   production   database.mongodb.production_name — never dropped or reset by anything here.
#   shared       database.mongodb.preview_name — the preview database every preview used before
#                D35, and still uses while MONGODB_PREVIEW_PER_BRANCH is unset. Never dropped or reset.
#   previews     `preview_<branch>` (lib/db-name.mjs) where mongodb.previews is `branch`: the app
#                derives the name at runtime, the repo's preview-migrate workflow migrates and seeds
#                it on each PR push, the reference mongodb-cleanup.yaml drops it when the PR closes.
#   UAT          `database.mongodb.uat_name`, where uat is declared (D39): a long-lived database the
#                operator names in /setup and sets on the UAT custom environment's variables.
#                `reset-uat --apply` drops it and re-makes it with the repo's seed and migrate
#                commands — there is no copy of production to reset from, by design.
#   runs         `run_<slug>`, made by db-branch.sh up (isolation: database).
#   status  the databases by role — production, shared, UAT, preview_* and run_* (each live or
#           not: a git branch on origin, a run folder), and every other database by name (not the
#           pipeline's); the cluster's database and collection counts against mongodb.limits.
#                RESULT: MONGODB <n> database(s) · production <state> · shared <state> · uat <state> · previews <n> · runs <n>
#   init    the operator's one-time acts (below, in the script) and which are done. Writes nothing.
#   prune   drop run_* whose run is archived and preview_* whose git branch is gone. Never
#           production_name, preview_name or the UAT database. `--days` has no meaning here (a
#           database carries no expiry) and is ignored.
#
# The topology, one home per fact (D24 — the names in project.json, the state in Neon):
#   production   the production project's production branch (database.neon.project_id,
#                database.neon.production_branch — `main` by default) — NEVER written, deleted or
#                reset by anything in the pipeline.
#   UAT          where the repo declares uat (D41), the DEFAULT BRANCH of a second Neon project —
#                the second Marketplace database (`uat-<repo>`, database.neon.nonprod_project_id),
#                connected by the operator to the UAT custom environment + Preview while
#                production's database is connected to Production only. Every variable is the
#                integration's; the UAT build migrates it. Nothing here creates it; `reset-uat`
#                empties and re-makes it with the repo's own reset_command on the operator's call —
#                there is no parent to reset from, and nothing is ever copied from production
#                (_shared/promotion.md → The UAT database).
#   previews     `preview/<git-branch>`, one per preview deployment, created and wired by the Vercel
#                integration (its Preview-branching toggle — an operator act `init` lists) — in the
#                non-production project where uat is declared, else in the one project. The
#                reference workflow .github/workflows/neon-cleanup.yaml deletes one when its PR
#                closes; `prune` deletes the ones whose git branch is gone.
#   runs         `run/<slug>`, one per live run, created by db-branch.sh up (database.isolation:
#                neon) with a 7-day expiry — a child of production without uat, a child of the UAT
#                database in the non-production project with it (D41) — and deleted by down; `prune`
#                deletes the ones whose run is archived or whose expiry passed unnoticed.
#   Where uat is declared, production's project is only ever READ (status, init): lib/neon.sh
#   refuses every write there.
#
# Verbs:
#   status       (default) the branches by role — production (protected or not), the UAT database
#                (present, or not yet), preview branches (count, newest), run branches (each with
#                its expiry and whether its run is still live) and every other branch by name (not
#                the pipeline's — yours). With uat, both projects: a preview/* or run/* branch in
#                production's project is a [WARN] (its database still branches previews — D41).
#                With a Vercel token in reach, the product project's build command: the place
#                previews and UAT apply their migrations — with uat and no override, the
#                vercel-build script in the project's root-directory package.json, which Vercel
#                runs ahead of build. Read-only.
#                          RESULT: NEON <n> branch(es) · production <name> · uat <state> · previews <n> · runs <n>
#   init         prints the one-time acts only the operator can perform — the API key and where it
#                lives, the integration's Preview-branching toggle, the build command that applies
#                migrations, protecting the production branch, the cleanup workflow, and (UAT) the
#                second Marketplace database and its connections (D41) — and, with the key in
#                reach, reads the project(s) once to say which are done. Writes nothing.
#                                                                                       RESULT: INIT
#   reset-uat [--apply]
#                run database.neon.reset_command with the url variable pointed at the UAT database
#                (the non-production project's default branch, unpooled): the repo's own command
#                empties it and re-migrates and re-seeds it — the client's test data is gone, the
#                shape is main's migrations. Dry-run by default. Never production's project.
#                                                                         RESULT: DRY-RUN | RESET | SKIP
#   prune [--apply] [--days <n>]
#                delete run/* branches whose run is no longer live (or older than <n> days, default
#                7) and preview/* branches whose git branch no longer exists on origin. Never
#                production, never the UAT database, never a name the pipeline did not give, never
#                production's project on a UAT repo. Dry-run by default.
#                                                           RESULT: DRY-RUN <n> | PRUNED <n> | UNCHANGED
#
# What never happens here: production is never written; the UAT database is never created or
# deleted (the operator owns its birth; a reset is the one act, and only on --apply); no branch of a
# name the pipeline did not give is touched; nothing is scheduled; nothing watches. The key's value
# and every connection string never reach argv or stdout.
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
    -h|--help) sed -n '2,89p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "error: unknown argument: $1 (usage: db-env.sh [status|init|reset-uat|prune] [--apply] [--days <n>])" >&2; exit 2 ;;
  esac
done

# shellcheck source=lib/project.sh
source "$here/lib/project.sh"

# --- MongoDB (D35): one cluster, databases by name --------------------------------------------------------------
if [ "$(database_provider)" = mongodb ]; then
  url_env="$(database_url_env)"; prod="$(mongo_production_name)"; shared="$(mongo_preview_name)"; previews="$(mongo_previews)"
  mongo() { node "$here/lib/mongo.mjs" "$@"; }
  names() { node "$here/lib/db-name.mjs" "$@"; }
  uat_db="$(mongo_uat_database)"
  head_line="MongoDB cluster via \$$url_env ($( [ -n "${!url_env:-}" ] && echo "set here" || echo "unset here")) · production ${prod:-<undeclared>} · shared preview ${shared:-<undeclared>} · previews $previews${uat_db:+ · UAT $uat_db}"

  if [ "$verb" = init ]; then
    echo "$head_line"
    echo
    echo "One-time setup the operator completes by hand (this script does none of it):"
    [ -n "${!url_env:-}" ] && echo "  [OK]   \$$url_env is set in this shell" || echo "  [TODO] export $url_env (the NON-production cluster's URI — never production's credentials; never in git) on the machines that drive the pipeline"
    { [ -n "$prod" ] && [ -n "$shared" ] && [ "$prod" != "$shared" ]; } && echo "  [OK]   production_name and preview_name declared, and different" || echo "  [TODO] declare database.mongodb.production_name and preview_name in .icm/project.json (/setup) — every drop refuses them by name"
    { [ -n "$(mongo_seed_command)" ] && [ -n "$(mongo_migrate_command)" ]; } && echo "  [OK]   seed_command and migrate_command declared" || echo "  [TODO] declare database.mongodb.seed_command and migrate_command (the repo's own; the migrate command takes up [<name>] [--single] and down <name> [--single])"
    echo "  [INFO] the database user behind \$$url_env creates and drops run_* and preview_* databases: it needs readWrite on them and the dropDatabase action (Atlas: readWriteAnyDatabase + dbAdminAnyDatabase) — without dropDatabase, lib/mongo.mjs drops every collection instead"
    echo "  [INFO] no role can fence $prod off from a user that creates databases by prefix: keep production on a cluster of its own, behind a user limited to it, and point \$$url_env, the Preview target and the preview CI secret at the non-production cluster (D36) — here production then reads absent, by design. A Vercel storage integration's one variable spans every environment: set the two URIs by hand instead"
    echo "  [INFO] cluster caps (database.mongodb.limits): $(mongo_limit_databases) databases · $(mongo_limit_collections) collections (0 = uncapped; the shared Atlas tiers cap both — every run and preview database counts) · names at most $(mongo_limit_name_bytes) bytes (38 on a shared Atlas tier, 63 on a dedicated one — lib/db-name.mjs hashes a longer branch down to it)"
    if [ "$previews" = branch ]; then
      echo "  [INFO] the app reads VERCEL_ENV and VERCEL_GIT_COMMIT_REF at runtime — Vercel exposes its system variables by default (there is no project toggle any more); nothing to switch on"
      echo "  [TODO] the app reads its database name through lib/db-name.mjs → databaseName(process.env, \"$(mongo_name_env)\"$( [ "$(mongo_limit_name_bytes)" = 38 ] || echo ", $(mongo_limit_name_bytes)")) — the one line in its connection code (a chore; record it in project-rules.md)"
      echo "  [TODO] the repo's preview-migrate workflow makes and migrates preview_<branch> on each PR push instead of the shared database:  $(mongo_name_env)=\"\$(node .icm/scripts/lib/db-name.mjs preview \"\$HEAD_REF\")\"  then \`<migrate_command> up\` and the seed command; its concurrency keys on the PR (one database per branch — no global queue). Where the seed creates no tenant or login, the preview opens on nothing: make the database on first push as a copy of $shared instead (mongodump | mongorestore --nsFrom/--nsTo on the one cluster — D36), and migrate $shared on each merge so it stays at main's shape"
      echo "  [TODO] the preview smoke check waits for that job — a preview's first request otherwise meets an empty database"
      if [ -f .github/workflows/mongodb-cleanup.yaml ] || [ -f .github/workflows/mongodb-cleanup.yml ]; then echo "  [OK]   .github/workflows/mongodb-cleanup.yaml present — drops preview_<branch> and run_<slug> when a PR closes"
      else echo "  [TODO] seed the reference cleanup workflow (setup.sh --fix --template <path>, or copy github-pipeline/workflows/mongodb-cleanup.yaml) — nothing else drops a closed PR's database"; fi
      echo "  [LAST] set MONGODB_PREVIEW_PER_BRANCH=1 once on the Preview target — and as a repository variable of the same name where the repo's workflows read it (a workflow cannot read Vercel's) — the switch; unsetting it is the whole revert (every preview back on $shared)"
    else
      echo "  [INFO] database.mongodb.previews is none — every preview uses the shared preview database $shared, as before; previews: branch gives each its own"
    fi
    if uat_declared; then
      if [ -n "$uat_db" ]; then
        echo "  [TODO] set $(mongo_name_env)=$uat_db (and the non-production cluster's URI as \$$url_env) on the UAT custom environment '$(uat_target)' only — MONGODB_PREVIEW_PER_BRANCH stays unset there, so the app reads the name as given (D39 (3))"
        echo "  [TODO] migrate and seed $uat_db on each merge to main — the repo's migrate workflow on push to main (MONGODB name = $uat_db); db-env.sh reset-uat --apply re-makes it from nothing"
      else
        echo "  [TODO] uat is declared but database.mongodb.uat_name is empty — name the UAT database (/setup; 'uat' by convention)"
      fi
    fi
    if [ -n "${!url_env:-}" ] && command -v node >/dev/null 2>&1; then
      if c="$(mongo check 2>&1)"; then echo "  [OK]   the cluster answers: $c"; else echo "  [WARN] the cluster did not answer: $c"; fi
    fi
    echo "RESULT: INIT"; exit 0
  fi

  if [ -z "${!url_env:-}" ] || ! command -v node >/dev/null 2>&1; then
    echo "MongoDB is declared but \$$url_env is unset here, or node is missing — nothing can be read (db-env.sh init lists the acts)"
    echo "RESULT: SKIP"; exit 0
  fi
  dbs="$(mongo list)" || exit 1
  # Liveness: a run database is live while its run folder is; a preview database while its git branch is on origin.
  live_runs="$(for d in .icm/runs/*/; do [ -d "$d" ] || continue; sl="$(basename "$d")"; case "$sl" in _*) continue ;; esac; names run "$sl"; done 2>/dev/null | sort -u)"
  live_previews="$(GIT_TERMINAL_PROMPT=0 git ls-remote --heads origin 2>/dev/null | sed -E 's#.*refs/heads/##' | names preview --stdin | cut -f1 | sort -u)"
  is_in() { printf '%s\n' "$2" | grep -qxF -- "$1"; }

  case "$verb" in
  status)
    total="$(printf '%s' "$dbs" | jq 'length')"; ncol="$(printf '%s' "$dbs" | jq '[.[].collections] | add // 0')"
    has() { printf '%s' "$dbs" | jq -e --arg n "$1" 'any(.[]; .name == $n)' >/dev/null; }
    echo "MongoDB cluster via \$$url_env — $total database(s), $ncol collection(s) (caps: $(mongo_limit_databases) · $(mongo_limit_collections); 0 = none)"
    ps="absent"; [ -n "$prod" ] && has "$prod" && ps="present"
    ss="absent"; [ -n "$shared" ] && has "$shared" && ss="present"
    echo "production: ${prod:-<undeclared>} — $ps$( [ "$ps" = absent ] && echo " on this cluster (on its own cluster, as D36 prefers)") · never dropped or reset"
    echo "shared:     ${shared:-<undeclared>} — $ss · the preview database while MONGODB_PREVIEW_PER_BRANCH is unset"
    us="n/a"
    if [ -n "$uat_db" ]; then us="not yet"; has "$uat_db" && us="present"; echo "uat:        $uat_db — $us (reset-uat --apply re-migrates and re-seeds it)"; fi
    np=0; nr=0
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      case "$n" in
        "$prod"|"$shared"|"$uat_db") continue ;;
        preview_*) np=$((np + 1)); is_in "$n" "$live_previews" && echo "  - $n — branch live" || echo "  - $n — branch gone (prune drops it)" ;;
        run_*)     nr=$((nr + 1)); is_in "$n" "$live_runs" && echo "  - $n — run live" || echo "  - $n — run archived (prune drops it)" ;;
      esac
    done < <(printf '%s' "$dbs" | jq -r '.[].name')
    echo "previews:   $np preview_* database(s)$( [ "$previews" = branch ] || echo " (mongodb.previews is none — none expected)")"
    echo "runs:       $nr run_* database(s)$( [ "$(database_isolation)" = database ] || echo " (database.isolation is $(database_isolation), not database — db-branch.sh makes none)")"
    others="$(printf '%s' "$dbs" | jq -r --arg p "$prod" --arg s "$shared" --arg u "$uat_db" '.[].name | select(. != $p and . != $s and . != $u and (test("^(run|preview)_") | not))')"
    if [ -n "$others" ]; then echo "other:      not the pipeline's — yours:"; printf '%s\n' "$others" | sed 's/^/  - /'; fi
    echo "RESULT: MONGODB $total database(s) · production $ps · shared $ss · uat $us · previews $np · runs $nr"
    exit 0 ;;
  reset-uat)
    [ -n "$uat_db" ] || { echo "no UAT database: uat is not declared, or database.mongodb.uat_name is empty — nothing to reset"; echo "RESULT: SKIP"; exit 0; }
    { [ -n "$(mongo_seed_command)" ] && [ -n "$(mongo_migrate_command)" ]; } || die "database.mongodb.seed_command and migrate_command must both be declared"
    if [ "$apply" -eq 0 ]; then
      echo "would: drop $uat_db and re-make it with \`migrate up\` and the repo's seed command — the client's test data is gone, the shape is main's migrations on a seeded database (nothing is copied from production)"
      echo "RESULT: DRY-RUN"; exit 0
    fi
    mongo drop "$uat_db" --uat || exit 1
    ( export "$(mongo_name_env)=$uat_db"; bash -c "$(mongo_migrate_command) up" && bash -c "$(mongo_seed_command)" ) 2>&1 | sed -E 's#mongodb(\+srv)?://[^[:space:]"]*#mongodb://<redacted>#g'
    [ "${PIPESTATUS[0]}" -eq 0 ] || die "$uat_db dropped but the migrate or seed command failed — re-run reset-uat --apply"
    echo "reset: $uat_db migrated up and re-seeded"
    echo "RESULT: RESET"; exit 0 ;;
  prune)
    n=0; would=()
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      case "$name" in "$prod"|"$shared"|"$uat_db") continue ;; esac
      reason=""
      case "$name" in
        run_*)     is_in "$name" "$live_runs" || reason="its run is no longer live" ;;
        preview_*) is_in "$name" "$live_previews" || reason="its git branch is gone from origin" ;;
        *) continue ;;
      esac
      [ -n "$reason" ] || continue
      if [ "$apply" -eq 1 ]; then mongo drop "$name" >/dev/null || exit 1; echo "dropped: $name — $reason"
      else would+=("$name — $reason"); fi
      n=$((n + 1))
    done < <(printf '%s' "$dbs" | jq -r '.[].name')
    if [ "$apply" -eq 0 ]; then
      if [ "$n" -eq 0 ]; then echo "nothing to prune"; echo "RESULT: UNCHANGED"; exit 0; fi
      printf 'would drop: %s\n' "${would[@]}"
      echo "RESULT: DRY-RUN $n"; exit 0
    fi
    [ "$n" -gt 0 ] && echo "RESULT: PRUNED $n" || echo "RESULT: UNCHANGED"
    exit 0 ;;
  esac
fi

# shellcheck source=lib/neon.sh
source "$here/lib/neon.sh"

if ! neon_declared; then
  if [ -n "$(neon_undeclared_why)" ]; then neon_undeclared_why
  else echo "no Neon project or MongoDB cluster is declared in .icm/project.json (database.provider: neon + database.neon.project_id, or mongodb) — the database is whatever each deployment's variables name; /setup declares one"; fi
  echo "RESULT: SKIP"; exit 0
fi
prod_name="$(neon_production_branch)"; previews="$(neon_previews)"; url_env="$(database_url_env)"
# D41: with uat, two projects — production's (read only) and the non-production one every write
# goes to (lib/neon.sh starts on it). Without uat they are one, and split stays 0.
split=0; neon_split && split=1
np_project="$neon_project"
[ "$split" -eq 0 ] || [ "$np_project" != "$neon_prod_project" ] || die "database.neon.nonprod_project_id is production's project ($neon_prod_project) — refusing: UAT, previews and runs live in a second Marketplace database, never production's (D41; setup.sh)"
key_state="unset here"; [ -n "$neon_key" ] && key_state="set here"

# --- init: the operator's acts, and which are done ---------------------------------------------------------
if [ "$verb" = "init" ]; then
  if [ "$split" -eq 1 ]; then
    echo "Neon production project $neon_prod_project · non-production project $np_project (UAT, previews, runs) · key \$$neon_key_name ($key_state) · production branch $prod_name · previews $previews"
  else
    echo "Neon project $neon_project · key \$$neon_key_name ($key_state) · production branch $prod_name · previews $previews"
  fi
  echo
  echo "One-time setup the operator completes by hand (this script does none of it):"
  if [ -n "$neon_key" ]; then echo "  [OK]   \$$neon_key_name is set in this shell"
  else echo "  [TODO] create a Neon API key (Neon Console → Account settings → API keys; a Vercel-managed organisation needs one for every CLI or API call) and export it as $neon_key_name on the machines that drive the pipeline — never in git"; fi
  [ "$split" -eq 1 ] && echo "  [INFO] the key must reach both projects — an organisation key of the Neon organisation both Marketplace databases live in does"
  echo "  [TODO] the same key as this repository's Actions secret, for the cleanup workflow:   printf '%s' \"\$$neon_key_name\" | .icm/scripts/env.sh add $neon_key_name --ci --github secret --note 'Neon API key: deletes the PR'\"'\"'s preview and run branches on close'"
  if [ "$previews" = "vercel" ]; then
    if [ "$split" -eq 1 ]; then
      echo "  [TODO] Vercel → Storage → the NON-production database (project $np_project) → its connection → Advanced options → Deployments configuration: enable Preview, and 'Resource must be active before deployment' — the integration then creates preview/<git-branch> inside it for every preview deployment and injects its variables at deploy time (they never appear in the project's settings)"
    else
      echo "  [TODO] Vercel → Storage → the database → Connect Project → Advanced options → Deployments configuration: enable Preview, and 'Resource must be active before deployment' — the integration then creates preview/<git-branch> for every preview deployment and injects its variables at deploy time (they never appear in the project's settings)"
    fi
    echo "  [TODO] the build must apply the branch's migrations, or a preview's (and UAT's) database is production's shape without them: run the repo's migrate step before the build — the build command in Vercel (Settings → Build and Deployment), or a vercel-build script — and record the choice in _shared/project-rules.md → The factory → The run's database"
    if [ -f .github/workflows/neon-cleanup.yaml ] || [ -f .github/workflows/neon-cleanup.yml ]; then echo "  [OK]   .github/workflows/neon-cleanup.yaml present — deletes preview/<branch> and run/<slug> when a PR closes"
    else echo "  [TODO] seed the reference cleanup workflow (setup.sh --fix --template <path>, or copy github-pipeline/workflows/neon-cleanup.yaml from the template) — the Vercel-managed integration otherwise keeps a preview branch until the deployment expires, which is months"; fi
  else
    echo "  [INFO] database.neon.previews is none — previews share the Preview environment's variables; set it to vercel and enable the integration's Preview branching for a database per preview"
  fi
  if [ "$split" -eq 1 ]; then
    echo "  [OK]   the UAT database's project is declared: $np_project (database.neon.nonprod_project_id) — a second Marketplace database (Vercel → Storage → Create Database → Neon, 'uat-$(project_field .name)', production's region); its default branch is the UAT database (D41)"
    echo "  [TODO] its connection → environments: the custom environment '$(uat_target)' + Preview (+ Development), no prefix — every database variable UAT and the previews read comes from it; set none by hand"
    echo "  [TODO] production's database → its connection → Production ONLY, preview branching off: still connected to Preview it runs its Preview Deployment Action on every UAT deployment and binds it to production; connected to '$(uat_target)' it hands UAT its Preview secret — production's string again (D41). setup.sh reads this through the Vercel API"
    echo "  [TODO] where the app uses Neon Auth: configure it once on the UAT database to match production's — verification, the OAuth providers, the SMTP sender, trusted origins = $(uat_url), its webhooks at $(uat_url)"
    echo "  [TODO] every other variable the app needs on '$(uat_target)' (.env.example → [preview]) set on that environment by hand — secrets only, never a database string"
    echo "  [INFO] the UAT build migrates the UAT database like a preview's: inside the custom environment VERCEL_ENV is preview and VERCEL_TARGET_ENV is '$(uat_target)'"
    if [ -n "$(neon_reset_command)" ]; then echo "  [OK]   database.neon.reset_command: $(neon_reset_command) — db-env.sh reset-uat --apply runs it against the UAT database"
    else echo "  [TODO] declare database.neon.reset_command (/setup) — the repo's own command that empties the UAT database and re-migrates and re-seeds it (prisma: npx prisma migrate reset --force; otherwise the repo's script), run with \$$url_env pointed at it; it never drops a schema the app does not own (neon_auth, where Neon Auth is on). Empty: reset-uat says SKIP"; fi
  fi
  echo "  [TODO] protect the production branch in Neon (Branches → $prod_name → Protect): a protected branch cannot be deleted or reset, and its children get credentials of their own"
  if neon_ready; then
    [ "$split" -eq 1 ] && neon_use_project "$neon_prod_project"
    if neon_load_branches; then
      bj="$NEON_BRANCHES"
      prot="$(printf '%s' "$bj" | jq -r --arg n "$prod_name" '[.[] | select(.name == $n)] | first | if . == null then "missing" else (.protected | tostring) end')"
      case "$prot" in
        true)    echo "  [OK]   production branch $prod_name is protected" ;;
        false)   echo "  [..]   production branch $prod_name is not protected yet" ;;
        missing) echo "  [WARN] no branch named $prod_name in project $neon_project — database.neon.production_branch names the production branch" ;;
      esac
      if [ "$split" -eq 1 ]; then
        ns="$(printf '%s' "$bj" | jq '[.[] | select(.name | test("^(preview|run)/"))] | length')"
        if [ "$ns" -gt 0 ]; then echo "  [WARN] production's project still carries $ns preview/* or run/* branch(es) — its database still branches previews, or they predate D41; the pipeline never writes there: turn its Preview branching off and delete them in the Neon Console"
        else echo "  [OK]   production's project carries no preview/* or run/* branch"; fi
        neon_use_project "$np_project"
        neon_load_branches && bj="$NEON_BRANCHES" || bj=""
        [ -z "$bj" ] || echo "  [OK]   UAT database: $(printf '%s' "$bj" | jq -r '[.[] | select(.default == true)] | first | "\(.name) (\(.id))"'), the default branch of $np_project"
      fi
      if [ "$previews" = "vercel" ] && [ -n "$bj" ]; then
        np="$(printf '%s' "$bj" | jq '[.[] | select(.name | startswith("preview/"))] | length')"
        if [ "$np" -gt 0 ]; then echo "  [OK]   preview branching is live: $np preview/* branch(es)"; else echo "  [..]   no preview/* branch yet — after the toggle, the next preview deployment creates the first"; fi
      fi
    fi
  fi
  echo "RESULT: INIT"; exit 0
fi

# --- every other verb reads the project(s) ------------------------------------------------------------------
if ! neon_ready; then
  if [ -z "$neon_key" ]; then echo "Neon project $neon_project$( [ "$split" -eq 1 ] && echo " (and production's, $neon_prod_project)") is declared but \$$neon_key_name is unset in this environment — nothing can be read (db-env.sh init lists the acts; export the key, never in git)"
  else echo "Neon project $neon_project is declared but curl or jq is missing — nothing can be read"; fi
  echo "RESULT: SKIP"; exit 0
fi
neon_load_branches || exit 1
bj="$NEON_BRANCHES"          # the working project: previews and runs (and, split, UAT) — the only one written
pbj="$bj"                    # production's project — the same one unless split
if [ "$split" -eq 1 ]; then
  neon_use_project "$neon_prod_project"; neon_load_branches || exit 1; pbj="$NEON_BRANCHES"
  neon_use_project "$np_project"; NEON_BRANCHES="$bj"
fi
now_epoch="$(date -u +%s)"
children_of() { printf '%s' "$bj" | jq -r --arg p "$1" '[.[] | select(.parent_id == $p)] | length'; }
to_epoch() { date -u -d "$1" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || echo 0; }
prod_id="$(printf '%s' "$pbj" | jq -r --arg n "$prod_name" '[.[] | select(.name == $n)] | first | .id // empty')"
uat_id=""; uat_name=""
if [ "$split" -eq 1 ]; then
  uat_id="$(printf '%s' "$bj" | jq -r '[.[] | select(.default == true)] | first | .id // empty')"
  uat_name="$(printf '%s' "$bj" | jq -r '[.[] | select(.default == true)] | first | .name // empty')"
fi
keep_id="$prod_id"; [ "$split" -eq 1 ] && keep_id="$uat_id"   # the working project's branch nothing here writes

case "$verb" in

status)
  total="$(printf '%s' "$bj" | jq 'length')"
  if [ "$split" -eq 1 ]; then
    ptotal="$(printf '%s' "$pbj" | jq 'length')"
    echo "Neon production project $neon_prod_project — $ptotal branch(es), read via \$$neon_key_name (never written)"
  else
    echo "Neon project $neon_project — $total branch(es), read via \$$neon_key_name"
  fi
  if [ -n "$prod_id" ]; then
    echo "production: $prod_name ($prod_id) — $(printf '%s' "$pbj" | jq -r --arg n "$prod_name" '[.[] | select(.name == $n)] | first | if .protected then "protected" else "NOT protected (db-env.sh init)" end')"
  else
    echo "production: $prod_name — [WARN] no branch of that name in the project (database.neon.production_branch)"
  fi
  uat_state="n/a"
  if [ "$split" -eq 1 ]; then
    stray="$(printf '%s' "$pbj" | jq -r '.[] | select(.name | test("^(preview|run)/")) | .name')"
    if [ -n "$stray" ]; then echo "[WARN]      production's project carries preview/* or run/* branches — its database still branches previews, or they predate D41; the pipeline never deletes there (Neon Console):"; printf '%s\n' "$stray" | sed 's/^/  - /'; fi
    pothers="$(printf '%s' "$pbj" | jq -r --arg p "$prod_name" '.[] | select(.name != $p and (.name | test("^(preview|run)/") | not)) | .name')"
    if [ -n "$pothers" ]; then echo "other:      in production's project, not the pipeline's — yours:"; printf '%s\n' "$pothers" | sed 's/^/  - /'; fi
    echo "Neon non-production project $np_project — $total branch(es): UAT, previews, runs"
    if [ -n "$uat_id" ]; then
      uat_state="present"
      echo "uat:        $uat_name ($uat_id) — the UAT database (the project's default branch), created $(printf '%s' "$bj" | jq -r --arg id "$uat_id" '[.[] | select(.id == $id)] | first | .created_at // "?"'); children: $(children_of "$uat_id") (previews and runs)"
    else
      uat_state="not yet"
      echo "uat:        [WARN] no default branch in $np_project — is database.neon.nonprod_project_id the UAT database's project?"
    fi
    total=$((total + ptotal))
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
  if [ "$split" -eq 1 ]; then
    others="$(printf '%s' "$bj" | jq -r --arg u "$uat_id" '.[] | select(.id != $u and (.name | startswith("preview/") | not) and (.name | startswith("run/") | not)) | .name')"
  else
    others="$(printf '%s' "$bj" | jq -r --arg p "$prod_name" '.[] | select(.name != $p and (.name | startswith("preview/") | not) and (.name | startswith("run/") | not)) | .name')"
  fi
  if [ -n "$others" ]; then echo "other:      not the pipeline's — yours to keep or delete in the Neon Console:"; printf '%s\n' "$others" | sed 's/^/  - /'; fi
  # The build command, where a Vercel token is in reach — the place previews and UAT apply migrations.
  if [ -f "$here/lib/vercel.sh" ] && project_has '.deploy.projects'; then
    bc="$( ( source "$here/lib/vercel.sh"; [ -n "$vercel_token" ] || exit 0
             deploy_projects | jq -r 'select((.class // "product") == "product") | .name' | head -n1 | while read -r pn; do
               pj="$(vercel_project "$pn" 2>/dev/null)"
               # With UAT: no override means Vercel runs the root directory's vercel-build script ahead of build — name it.
               rd="$(printf '%s' "$pj" | jq -r '.rootDirectory // "" | sub("^\\./"; "") | sub("/$"; "")')"; pkg="${rd:+$rd/}package.json"
               if [ "$split" -eq 1 ] && printf '%s' "$pj" | jq -e '(.buildCommand // "") == ""' >/dev/null && vb="$(jq -er '.scripts["vercel-build"] // empty' "$pkg" 2>/dev/null)"; then
                 printf '%s: the vercel-build script in %s (`%s`)\n' "$(printf '%s' "$pj" | jq -r .name)" "$pkg" "$vb"
               else printf '%s' "$pj" | jq -r '"\(.name): \(.buildCommand // "the framework default")"'; fi
             done ) 2>/dev/null || true )"
    [ -n "$bc" ] && echo "build:      $bc — previews and UAT carry a branch's migrations only if this runs the migrate step (db-env.sh init)"
  fi
  echo "RESULT: NEON $total branch(es) · production $prod_name · uat $uat_state · previews $np · runs $nr"
  exit 0 ;;

reset-uat)
  [ "$split" -eq 1 ] || { echo "no UAT database: uat is not declared (.icm/project.json) — nothing to reset"; echo "RESULT: SKIP"; exit 0; }
  [ -n "$uat_id" ] || die "Neon project $np_project has no default branch — is database.neon.nonprod_project_id the UAT database's project?"
  cmd="$(neon_reset_command)"
  [ -n "$cmd" ] || { echo "no reset command: database.neon.reset_command is empty — the repo's own command that empties the UAT database and re-migrates and re-seeds it (db-env.sh init); there is no parent to reset from (D41)"; echo "RESULT: SKIP"; exit 0; }
  if [ "$apply" -eq 0 ]; then
    echo "would: run \`$cmd\` with \$$url_env pointed at the UAT database $uat_name ($uat_id) in Neon project $np_project, unpooled — the client's test data is gone, the shape is main's migrations on a seeded database (nothing is copied from production); the connection string does not change"
    echo "RESULT: DRY-RUN"; exit 0
  fi
  url="$(neon_connection_uri "$uat_id" --unpooled)" || exit 1
  [ -n "$url" ] || die "Neon answered without a connection string for the UAT database"
  ( export "$url_env=$url"; bash -c "$cmd" ) 2>&1 | sed -E 's#postgres(ql)?://[^[:space:]"'"'"']*#postgresql://<redacted>#g'
  [ "${PIPESTATUS[0]}" -eq 0 ] || die "the reset command failed on the UAT database — read its output above, fix, re-run reset-uat --apply"
  echo "reset: $uat_name re-made by \`$cmd\` (the next UAT deployment of main migrates it as usual)"
  echo "RESULT: RESET"; exit 0 ;;

prune)
  n=0; would=()
  while IFS=$'\t' read -r id name exp; do
    [ -n "$name" ] || continue
    [ "$id" != "$keep_id" ] || continue
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
