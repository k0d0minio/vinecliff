# Project rules

This file belongs to the repo. It has the rules that are true for this repo only. Build and
the lanes read it. A rule that is true for all repos belongs in the blueprint, not here.

## The stack

- One Next.js 15 app (App Router) with React 19 and TypeScript, at the root of the repo.
- Tailwind CSS v4. The tokens are in `app/globals.css`.
- Drizzle ORM on Neon Postgres. The schema is `lib/db/schema.ts`. The client is
  `lib/db/index.ts`. The only database driver is `@neondatabase/serverless`: do not add a
  different driver without a ticket (JAM-254).
- The package manager is npm. Commit `package-lock.json`.
- Email goes through the HTTP API of Resend (`lib/email.ts`).

## The conventions of the code

- The public site is `app/`. The admin is `app/admin/`, behind `middleware.ts`.
- The booking rules (dates, pricing, availability, tokens) are pure functions in
  `lib/booking/`. Their unit tests are `tests/*.test.ts` (`node:test` through `tsx`).
  A change of a booking rule comes with a test.
- A change of the schema comes with a migration: `npm run db:generate`, then commit the files
  of `drizzle/`. Do not edit a migration that is on `main`. `.icm/local/database.md` has the
  database rule.
- The text that a guest or the owner reads is `en-US`.
- The brand is `.icm/docs/brand.md`. Read it before a change of a color, a font or the logo.
- `.env.example` is the one list of the variable names. A value never enters git.
- On 2026-11-18 `package.json` has no `lint` script and no `typecheck` script (JAM-255). The
  job `code` of `ci` runs the tests only.

## The docs folder

The docs folder for the lane `knowledge` is `.icm/docs/`. A page is one markdown file in
simple English, with short sentences. `README.md` at the root is not in the docs folder: a
change of it is a `chore`.

## Where a change goes

- On 2026-11-18 the repo has no UAT environment (JAM-253). A merge to `main` deploys
  production, and `db-migrate.yml` migrates the production database.
- Preview and Production share one database (JAM-252). A preview build with a new migration
  migrates production. Do not push a migration that production must not get.
