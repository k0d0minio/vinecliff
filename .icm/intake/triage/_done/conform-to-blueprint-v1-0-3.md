# Stub: The repo renders from the blueprint v1.0.3

- lane: chore
- found-by: the house drift report `desk/estate/drift-2026-10-28.md` · 2026-10-28
- complexity: medium
- priority: P2

## Problem

`.copier-answers.yml` names blueprint v1.0.2. The blueprint is at v1.0.3 (2026-10-28).

- v1.0.3: `.icm/scripts/vercel-build.sh` holds the migration rule of `.icm/database/CONTEXT.md`. `package.json` calls it with one line that never changes.

`package.json` has no `vercel-build` and no `db:verify`. `promote.yml` runs `db:verify` with `--if-present`, so it does not verify production now.

## Proposed change

Run `copier update` to v1.0.3 with the answers of record. Then make the repo's own files follow the database contract at v1.0.3, once. After this change, the rule reaches the repo only through `copier update`.

`package.json`: `"vercel-build": "bash .icm/scripts/vercel-build.sh next build"` and `"db:verify": "tsx scripts/verify-migrations.ts"`. The new `scripts/verify-migrations.ts` compares the hash of each journal file with `drizzle.__drizzle_migrations`. `db-migrate.yml` stays: `go-live/uat-environment` removes it when UAT is live.

## Acceptance criteria

- [ ] `.copier-answers.yml` names `v1.0.3`, and its other lines do not change.
- [ ] The repo's own files change only as the proposed change says.
- [ ] `ci` is green.
