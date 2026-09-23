# Stub: No CI runs on a pull request

- lane: chore
- found-by: pipeline template sync (k0d0minio/vinecliff#17) · 2026-09-23
- priority: P2

## Problem

The only workflow is `.github/workflows/db-migrate.yml`, which runs on `main`. A PR is checked
by Vercel's build alone: `npm run lint`, a typecheck and `npm test` (the booking-domain suite in
`tests/booking.test.ts` — dates, pricing, availability) run nowhere. `required_checks` in
`.icm/project.json` is therefore empty, and `setup.sh --report` warns about it.

## Proposed change

Add `.github/workflows/ci.yml` on `pull_request` (and `push` to `main`): `npm ci`, `next lint`,
`tsc --noEmit`, `npm test`, one job whose name becomes the required check. Then set
`required_checks` in `.icm/project.json` to that check-run name and update
`.icm/_shared/project-rules.md` → Required CI checks.

## Prompt

In the vinecliff repo, add a CI workflow that runs lint, typecheck and the unit tests on every
pull request. Read `.icm/intake/triage/ci-on-pull-requests.md` for context. Never run the
checks locally — push and read the result from CI. Record the check-run name in
`.icm/project.json` → `required_checks` and in `.icm/_shared/project-rules.md`.
