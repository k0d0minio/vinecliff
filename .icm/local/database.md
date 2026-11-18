# Database — the rule of today

Language: en

This file belongs to the repo. It is the database rule of this repo on 2026-11-18. It is the
rule of before the BAXTER blueprint, cut to what is true now.

## The database model of the blueprint is not adopted

The repo answered `database: none` to the blueprint (J, 2026-11-18). With `database: postgres`,
the job `code` of the workflow `ci` applies each migration on a plain Postgres service.
`scripts/migrate.ts` and `scripts/verify-migrations.ts` use only the Neon HTTP driver
(`@neondatabase/serverless`), and that driver cannot connect to a plain Postgres. A driver
for a plain Postgres is a product change, and it is not made. This file and
`.icm/local/vercel-build.sh` leave when the repo answers `database: postgres`.

## Inputs

- `.icm/environments.md`: which database each environment reads.
- `package.json`: `db:generate`, `db:migrate` (`scripts/migrate.ts`), `db:verify`
  (`scripts/verify-migrations.ts`), and the line
  `"vercel-build": "bash .icm/local/vercel-build.sh next build"`.

| Database | Reads it | Migrates on |
|---|---|---|
| The default branch of the Neon project `vinecliff` | Production | each push to `main`, in the workflow `db-migrate.yml` (the repo secret `DATABASE_URL`) |
| The database that `DATABASE_URL` names on Preview | each preview | each preview build, in `.icm/local/vercel-build.sh` |

On 2026-10-29, Preview and Production share one `DATABASE_URL`: a preview reads production,
and a preview build migrates production. The repo has no UAT database and no UAT environment.

## Process

**The migration rule.**

1. Write a migration with `npm run db:generate`, and commit the files of `drizzle/`. Do not
   edit a migration that is on `main`.
2. `db-migrate.yml` runs `db:migrate` on production at each push to `main`, and on
   `workflow_dispatch`. One run at a time. It does not run `db:verify`.
3. `.icm/local/vercel-build.sh` is the build command of Vercel. When `VERCEL_TARGET_ENV` is
   `production`, it only builds. For each other target it runs `db:migrate`, then `db:verify`,
   then the build. It gives the two scripts `DATABASE_URL_UNPOOLED` as `DATABASE_URL` when
   that name has a value. Without `VERCEL_TARGET_ENV` or without `DATABASE_URL`, it stops.
4. The workflow `promote` of the blueprint does not migrate (the answer `database: none`).
   The `promote.yml` of before had a job that ran `db:migrate` and `db:verify` on production
   before a promotion. That job left on 2026-11-18. It never ran: the repo has no release
   tag. Production is at the schema of `main` before a promotion, because `db-migrate.yml`
   runs at each push to `main`. Nothing runs `db:verify` on production now.
5. `db:migrate` holds no lock. Two runs on one database at the same time are possible.
6. A migration runs while the deployment of before still serves. A migration must work with
   the code that it replaces.
7. Do not run a migration on a computer against a shared database.

## Outputs

- Production at the schema of `main`, after the run of `db-migrate.yml`.
- A migrated database for each preview build, before the build.

## Gates

None.

| Name | Holds | Where |
|---|---|---|
| `DATABASE_URL` | the connection string of the database of the deployment | Vercel, each environment. The repo secret of the same name holds production's |
| `DATABASE_URL_UNPOOLED` | the direct connection string of the same database | Vercel, by the Neon integration |
| `VERCEL_TARGET_ENV` | the environment of the deployment | Vercel, a system variable |
