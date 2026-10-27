# Database — the Neon base, a preview branch for a migration, and the migration at build

This build answered `neon` to `database` in `copier.yml`. This file is the database rule for
every environment. `.copier-answers.yml` names `migrations_path`, the folder of the migration
files. Below, `<migrations_path>` is that folder.

## Inputs

| Shape | Neon projects | The base | Reads the base | Integration | `MIGRATE_AT_BUILD=1` on | Production migrates |
|---|---|---|---|---|---|---|
| With UAT | one for production, one for UAT | the UAT project's default branch | Vercel Preview and `uat` | Production only, or none | `uat` | in `promote.yml`, on `promote.sh run` |
| Without UAT | one | its default branch, production's database | Vercel Preview | Production only, or none | Production | at the build of `main` |

- `NEON_PROJECT_ID` names the project that holds the base. The preview branches are cut from
  it. With UAT, no script reaches the production project. `promote.yml` reaches it through
  the secret `DATABASE_URL` only.
- A preview without a migration reads and writes the base's rows. A tester knows it (why: a
  preview that changes no schema needs no copy · Jamie, 2026-10-27).
- The Neon integration never serves Preview. It makes a branch for every pull request, and the
  branch rule below makes one only for a migration.

## Process

**The branch rule.** A pull request whose diff touches `<migrations_path>/**` gets the Neon
branch `preview/<git branch>`. `preview-db.yml` cuts it from the base, with the base's data.
The branch has its own `DATABASE_URL`, `DATABASE_URL_UNPOOLED` and `MIGRATE_AT_BUILD=1`, on
the Vercel Preview environment, scoped to the git branch. The pull request closes, and
`neon-cleanup.yml` deletes the branch and the three variables. Nothing else deletes a branch
(why: a migration must not change the base before the merge · Jamie, 2026-10-27).

**The migration rule.** `package.json` names `db:migrate` and `db:verify`. The build's
`vercel-build` script runs `db:migrate`, then `db:verify`, then the build, when
`MIGRATE_AT_BUILD` is `1`. Otherwise it only builds:

```json
"vercel-build": "if [ \"$MIGRATE_AT_BUILD\" = 1 ]; then npm run db:migrate && npm run db:verify; fi && next build"
```

- The variable means: this deployment owns its database. A preview branch carries it from
  `preview-db.sh`. A plain preview never carries it (why: a preview without its own branch must
  not migrate the base. The first build of a pull request can run before its branch
  exists · 2026-10-27).
- With UAT, `uat` carries it always and production never, because `promote.yml` migrates
  production. Without UAT, Production carries it always: the build of `main` migrates
  production, then serves it.
- `db:migrate` uses `DATABASE_URL_UNPOOLED` when it has a value: a migration needs a direct connection.
- A migration at build runs while the previous deployment still serves. So a migration must be
  forward-compatible with the code it replaces.

**The script.** `.icm/scripts/preview-db.sh <verb> <git branch>`. `create`, `delete` and
`status`. `create` redeploys the branch's newest preview only when it changed something. The
two workflows run it. A session runs `status` to read a branch, and `create` or `delete` only
to repair a run that failed.

## Outputs

- `preview/<git branch>` in the project that `NEON_PROJECT_ID` names, while the pull request is
  open, and its three variables on Vercel Preview, scoped to the git branch.
- A migrated database for each deployment that carries `MIGRATE_AT_BUILD=1`.

## Setup, once

Jamie does these by hand, before the first pull request with a migration.

1. Neon: with UAT, two projects, production's and UAT's. Without UAT, one project.
2. Vercel → Storage: the Neon integration connected to Production only, with preview branching
   off. Or not connected: then set Production's `DATABASE_URL` and `DATABASE_URL_UNPOOLED` by hand.
3. Vercel → Settings → Environment Variables: `DATABASE_URL` and `DATABASE_URL_UNPOOLED` from
   the base on Preview, and with UAT on `uat` too. `MIGRATE_AT_BUILD=1` on `uat` with UAT, on
   Production without UAT. Never on Preview for all branches.
4. GitHub → Settings → Secrets and variables → Actions. Secrets: `NEON_API_KEY`,
   `VERCEL_TOKEN`. Variables: `NEON_PROJECT_ID` (the base's project), `VERCEL_TEAM`, and
   `VERCEL_PROJECT` when the Vercel project's name differs from the repository's.
5. `package.json`: `db:migrate`, `db:verify`, and `vercel-build` as the migration rule says.

| Name | Holds | Where |
|---|---|---|
| `DATABASE_URL` | the pooled connection string of the environment's database | Vercel |
| `DATABASE_URL_UNPOOLED` | the direct connection string of the same database | Vercel |
| `MIGRATE_AT_BUILD` | `1` where the deployment owns its database | Vercel |
| `NEON_API_KEY` | a Neon API key for the organisation | Actions secret · the shell |
| `NEON_PROJECT_ID` | the id of the project that holds the base | Actions variable · the shell |
| `VERCEL_TOKEN`, `VERCEL_TEAM`, `VERCEL_PROJECT` | as in `.env.example` | Actions · the shell |
