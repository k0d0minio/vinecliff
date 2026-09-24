---
name: database-migration
description: Write, name, isolate and order a schema migration so parallel runs merge in any order and never touch a shared database.
triggers:
  - migration, migrations/, schema, prisma, drizzle, flyway, mongodb, mongoose
  - check-migrations.sh, db-branch.sh, db-branch.sh prove
  - touches a data model
  - migrations.reversible, stop class 3
---

# Database migration — one run, one database, one correctly stamped file

Two template-owned scripts carry the mechanics; this skill is the order they are used in.
`.icm/scripts/check-migrations.sh` names and orders migrations; `.icm/scripts/db-branch.sh`
gives the run a database of its own. Both headers are the specification.

## Before writing the migration

1. **Bind the run's database** — `db-branch.sh <slug> up` → `BOUND`, then
   `eval "$(.icm/scripts/db-branch.sh <slug> env)"` in the shell that will run the repo's
   migration tool. On a Neon repo (`database.isolation: neon`) that is a branch of its own,
   `run/<slug>`, a copy of production made now with a 7-day expiry — on a UAT repo a copy of the
   UAT database, in the non-production project (D41), never production — needs the key
   `database.neon.api_key_env` names in the shell, nothing else. `SKIP` means this repo declares
   no isolation (`.icm/project.json` → `database.isolation`), or the engine it names is out of
   reach: then **run no migration locally** — the preview database and CI apply it, and the
   spec's data-model change is verified there. Never point a session at production. On a
   MongoDB repo (`database.provider: mongodb`, `isolation: database`) the run's database is
   `run_<slug>` on the repo's own cluster, beside production and the shared preview database:
   `up` runs the repo's migrate command, then its seed command (migrate first: the seed's
   models build the head's indexes), with the name variable (`database.mongodb.name_env`) set to it — and `env` prints just that one export. Nothing is
   cloned from production; the seed is the repo's, unchanged (D35).
2. **Name the file with the script, never by hand**:
   `check-migrations.sh --new "<what it does>" --apply` → `CREATED <path>`. The name carries a UTC
   millisecond stamp in the repo's declared form (`migrations.stamp`, default `millis`:
   `V20260922070000104__add_tokens.sql`), after everything `main` and this branch already have.
   A tool that generates its own files (prisma, drizzle) keeps its own naming inside its folder;
   the stamp rule applies to the migrations `migrations.path` names. A MongoDB repo on
   ts-migrate-mongoose or migrate-mongo declares `stamp: epoch` and `extension: ts` (or `js`):
   the same call names `1782500000000-add-tokens.ts` — kebab-case, the epoch-millisecond stamp
   those runners write — and orders it exactly like a SQL one. Prefer the script over the
   runner's own `create`: the runner reads the clock now, the script reads it after `main`'s
   newest stamp.

## Writing it

- **Forward-only unless the repo says otherwise** (`migrations.reversible`, default `false`):
  no `down` script is expected, so a code revert must tolerate the newer schema — additive
  columns with defaults, no drops in the same release as the code that stops using them. Where
  `reversible` is `true`, write the `down` and test it against the run's own database.
- **A single migration may be irreversible on a reversible repo** (D42) — a manual backfill, a
  destructive rename, anything with no honest `down`: declare it with `irreversible = true` in
  the migration file itself (an exported const, or the CommonJS `exports.irreversible = true`),
  and skip writing a `down` for it. `prove` reads the marker without running anything, proves
  that migration's `up` and its idempotency only, and names it in the output. Nothing at or
  before it in this branch's own migrations is down-tested either — a down assumes an unbroken
  chain back from the current state, and skipping one mid-chain breaks that for every down
  beneath it.
- One migration per concern; the spec's `touches:` names the data model, so a migration the
  spec does not imply is a spec gap → `revise`.
- Never edit a migration `main` already has. A fix is a new migration.

## Before the ready flip, and again before the merge

3. **After `git merge origin/main`** (Build step 10, Release step 7a):
   `check-migrations.sh` → `OK`. `STALE n` means main merged a newer migration first — re-run
   with `--apply`, commit the renames, and reset the run's database (`db-branch.sh <slug> down`,
   then `up`, then apply again). `MISNAMED n` means a file is in the other form — `--apply` fixes
   the name and keeps the stamp. Either way the renames are listed; they are never committed for
   you.
4. **Out of order is expected**: `migrations.out_of_order` (default `true`) says the repo's tool
   accepts a migration stamped before one it already applied. The script prints the tool's own
   setting (`references/tools.md`); the tool's config file is the repo's to change, in this
   branch, when it does not already say so.
5. **On a MongoDB repo, prove the round trip** (after step 3's `OK`, Build step 10 and Release
   step 7): `db-branch.sh <slug> prove` → `PROVEN`. On a fresh, unseeded `run_<slug>` migrated
   through exactly `main`'s migrations (the runner follows the stamp, so where this branch's are
   stamped before some of `main`'s, those go up — and this branch's come down — one at a time,
   `--single`) it runs this branch's own migrations up → down → up and compares the collection list and every
   index spec: `down` must restore them where `migrations.reversible` is true (and every file
   must export a `down`, unless it declares itself irreversible); the second `up` must reproduce
   the first; and, the runner's records of them forgotten the way a re-stamp forgets them, one
   more `up` must change nothing.
   `UNPROVEN n` names what failed — fix it on this branch. The seed runs only after `PROVEN`.
6. Release stop class 3 asks `env.sh audit --changed` and reads `migrations.reversible`: a
   forward-only migration in a merge with no rollback path is recorded in the `## Release`
   record's `- migrations:` line, not hidden.

## Where a preview or UAT applies the migration

On a Neon repo with `database.neon.previews: vercel`, every preview deployment has a database of
its own (`preview/<git-branch>`, a child of production — on a UAT repo, of the UAT database in
the second Marketplace database, D41) and applies the branch's migrations **at
build**, because the repo's build command runs the migrate step (`_shared/project-rules.md` → The
factory → The environments' databases says so, or says it does not). A preview whose build does
not migrate shows production's shape without this run's change; say so in the stop message rather
than assuming the preview proved the migration.

On a UAT repo (`_shared/promotion.md`) the merge into `main` deploys the UAT environment, whose
build migrates the UAT database (on Neon the second Marketplace database's default branch, D41;
on MongoDB `database.mongodb.uat_name`) the same way — inside a custom environment `VERCEL_ENV` is `preview`. **Production is migrated at
the promotion, not on the merge:** the release workflow calls the repo's `db-migrate.yml` when the
operator publishes the Release, before it promotes. So a migration merged today is live on UAT
today and reaches production only with its batch — schema and code move at the same promotion,
migration first. A failed production migration stops the release before the promote (the
`- migrations:` line and the operator's recovery, as below).

On a MongoDB repo with `database.mongodb.previews: branch`, every preview reads its own
`preview_<branch>` — the app derives the name at runtime through `.icm/scripts/lib/db-name.mjs`
once `MONGODB_PREVIEW_PER_BRANCH=1` is set on the Preview target — and the repo's preview-migrate
workflow migrates and seeds it on each PR push; the smoke check waits for that job. With the flag
unset, every preview shares `preview_name`, exactly as before.

## After the merge

- `db-branch.sh <slug> down` releases the run's schema, container, Neon branch or MongoDB
  database; `close-out.sh` archives the run and its `- db:` pointer with it. A `run/<slug>`
  branch a session forgot expires on its own after 7 days, and the reference `neon-cleanup.yaml`
  deletes it when the PR closes; a forgotten `run_<slug>` database is dropped by
  `mongodb-cleanup.yaml` on close, or by `db-env.sh prune --apply` once the run is archived.

## References

- `references/tools.md` — how flyway, prisma, drizzle, a plain SQL runner and a MongoDB runner
  each order migrations, where the out-of-order setting lives for each, and the MongoDB
  round-trip rule.
- `bash .icm/skills/database-migration/scripts/preflight.sh <slug>` — bind + check in one call
  (Level 3).
