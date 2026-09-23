# Stub: Previews read and write the production database

- lane: chore
- found-by: pipeline template sync (k0d0minio/vinecliff#17) · 2026-09-23
- priority: P1
- sources: Neon project `broad-lake-67509282` branch list (only `main`); `.icm/_shared/project-rules.md` → The environments' databases

## Problem

The Neon project `broad-lake-67509282` has one branch, `main`, and it is not protected. The
Vercel ↔ Neon integration's Preview-branching toggle is off, so every Vercel preview deployment
reads the Preview environment's `DATABASE_URL` — which can only point at production. A preview
build that migrates, or a tester who books on a preview, touches **real bookings**.
`.icm/project.json` records this as `database.neon.previews: none`.

## Proposed change

1. Protect the Neon `main` branch (Neon console → the branch → Protect). Operator act.
2. Turn on Preview branching in the integration (Vercel → Storage → the database → Connect
   Project → Deployments configuration → Preview, plus "Resource must be active before
   deployment"). Operator act.
3. Make migrations reach previews at build — a `vercel-build` script or the Vercel build
   command running `npm run db:migrate && next build`; `db-migrate.yml` keeps production's.
4. Seed `.github/workflows/neon-cleanup.yaml` from the template (deletes a PR's `preview/*` and
   `run/*` branches on close; needs `NEON_API_KEY` as an Actions secret).
5. Set `database.neon.previews: vercel` in `.icm/project.json` and update project-rules.md.

## Prompt

In the vinecliff repo, stop Vercel previews from sharing the production Neon database. Read
`.icm/intake/triage/previews-share-the-production-database.md` for the full problem and the
five steps, and `.icm/_shared/project-rules.md` → The run's database / The environments'
databases. Steps 1–2 are Jamie's acts in the Neon and Vercel consoles — ask for them, never do
them; confirm with the Neon branch list that `preview/*` branches appear after a preview deploy.
Real bookings live in production: never run a migration or seed against it.
