# Stub: No CI runs on a pull request

- lane: chore
- found-by: pipeline template sync (k0d0minio/vinecliff#17) · 2026-09-23 — re-cut to D43 on 2026-09-26 (estate audit)
- priority: P2

## Problem

The only workflow is `.github/workflows/db-migrate.yml`, which runs on `main`. A PR is checked
by Vercel's build alone: `npm run lint`, a typecheck and `npm test` (the booking-domain suite in
`tests/booking.test.ts` — dates, pricing, availability) run nowhere. `required_checks` in
`.icm/project.json` is therefore empty, and `setup.sh --report` warns about it.

## Proposed change

The D43 shape, not a required check: seed the reference `quality.yaml` (icm-board
`_system/template/github-pipeline/workflows/quality.yaml` — one advisory job named
`Quality (advisory)`, `pull_request` on ready heads only, path-filtered, never on `push` to
`main`) with this repo's `npm ci`, `next lint`, `tsc --noEmit`, `npm test` as its three steps.
`required_checks` stays empty — the deploy status is the verdict — and `setup.sh` no longer warns
on it. Record the job under `.icm/_shared/project-rules.md` → The factory.

## Prompt

In the vinecliff repo, read `.icm/intake/triage/ci-on-pull-requests.md`. Copy the reference
`quality.yaml` from the icm-board template (or `/setup`, which seeds it once), fill its three
`run:` steps with this repo's own commands, never run them locally — push and read the result.
