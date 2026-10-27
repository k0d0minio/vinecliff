# Stub: The owner tests each batch at the UAT address

- feature-slug: uat-environment
- epic: go-live
- sequence: 1 of 9
- depends-on: none
- complexity: medium
- priority: P0

## Problem

Every Vercel preview reads and writes the production database, which holds real bookings. There is no place where the owner tests a batch before it reaches production.

## Proposed change

The UAT shape of the blueprint, set up for this repo: a Vercel custom environment `uat` at `uat.vinecliffvineyard.com`, deployed from `main` on every merge, with its own database. Production moves only when Jamie promotes a release after the owner's yes.

## Acceptance criteria

- [ ] `.icm/uat/CONTEXT.md` exists, rendered by the blueprint, and its setup acts are done.
- [ ] The Neon project `broad-lake-67509282` has a branch `uat` for the UAT environment. Its `main` branch is protected.
- [ ] A preview deployment never reads the production database.
- [ ] `uat.vinecliffvineyard.com` serves the latest `main`. Production does not follow `main`.
- [ ] `db-migrate.yml` no longer migrates production on each push to `main`. `promote.yml` migrates production on Jamie's dispatch.
- [ ] `CLAUDE.md` and `README.md` say where the owner tests and how a release reaches production.

## Out of scope

- The `copier update` itself (conformance).

## Notes

The DNS record for `uat.vinecliffvineyard.com` is at GoDaddy. Jamie has delegate access. The Neon and Vercel console acts are Jamie's. A session asks for them and never does them.
