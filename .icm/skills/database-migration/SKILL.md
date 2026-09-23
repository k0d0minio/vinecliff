---
name: database-migration
description: Write, name, isolate and order a schema migration so parallel runs merge in any order and never touch a shared database.
triggers:
  - migration, migrations/, schema, prisma, drizzle, flyway, mongodb, mongoose
  - check-migrations.sh, db-branch.sh
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
   `run/<slug>`, a copy of production made now with a 7-day expiry — needs the key
   `database.neon.api_key_env` names in the shell, nothing else. `SKIP` means this repo declares
   no isolation (`.icm/project.json` → `database.isolation`), or the engine it names is out of
   reach: then **run no migration locally** — the preview database and CI apply it, and the
   spec's data-model change is verified there. Never point a session at production. A MongoDB
   repo is always this case today — the three engines are Postgres-shaped, so it stays
   `isolation: none` and the preview database is the one the branch's migrations reach.
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
5. Release stop class 3 asks `env.sh audit --changed` and reads `migrations.reversible`: a
   forward-only migration in a merge with no rollback path is recorded in the `## Release`
   record's `- migrations:` line, not hidden.

## Where a preview or UAT applies the migration

On a Neon repo with `database.neon.previews: vercel`, every preview deployment — and the UAT
branch's — has a database of its own (`preview/<git-branch>`, a child of production) and applies
the branch's migrations **at build**, because the repo's build command runs the migrate step
(`_shared/project-rules.md` → The factory → The environments' databases says so, or says it does
not). A preview whose build does not migrate shows production's shape without this run's change;
say so in the stop message rather than assuming the preview proved the migration.

## After the merge

- `db-branch.sh <slug> down` releases the run's schema, container or Neon branch; `close-out.sh`
  archives the run and its `- db:` pointer with it. A `run/<slug>` branch a session forgot
  expires on its own after 7 days, and the reference `neon-cleanup.yaml` deletes it when the PR
  closes.

## References

- `references/tools.md` — how flyway, prisma, drizzle and a plain SQL runner each order
  migrations, and where the out-of-order setting lives for each.
- `bash .icm/skills/database-migration/scripts/preflight.sh <slug>` — bind + check in one call
  (Level 3).
