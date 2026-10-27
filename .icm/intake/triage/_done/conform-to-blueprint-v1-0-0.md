# Stub: The repo renders from the blueprint v1.0.0

- lane: chore
- found-by: the house conformance stub `conformance-v1-0-0.md` · 2026-10-27
- complexity: low
- priority: P1

## Problem

`.copier-answers.yml` names blueprint v0.6.0 and carries `tier: app`. The blueprint is at v1.0.0. The tiers are gone, and `monorepo`, `release`, `uat`, `database` and `migrations_path` are the questions now. The repo has no lanes, no UAT contract, no database contract and no gate workflow. The go-live stub `uat-environment.md` is blocked until the repo renders with `release: true` and `uat: true`.

## Proposed change

Run `copier update` to v1.0.0 with the answers of record. Keep the repo's own files: `README.md`, `.icm/intake/README.md`, `CLAUDE.md`, `.gitignore` and `.env.example`. Then bring the rows and rules of `CLAUDE.md` in line with the blueprint's `template/CLAUDE.md.jinja` at v1.0.0 for these answers.

## Acceptance criteria

- [ ] `.copier-answers.yml` names `v1.0.0` and has no `tier` line. Its answers are `workspace: false`, `monorepo: false`, `release: true`, `uat: true`, `database: neon` and `migrations_path: drizzle`. `slug`, `client_name` and `language` do not change.
- [ ] `ci.yml` keeps the `release` job.
- [ ] `.icm/uat/CONTEXT.md`, `.icm/scripts/promote.sh`, `.icm/scripts/rollback.sh` and `.github/workflows/promote.yml` exist.
- [ ] `CLAUDE.md` has the release-or-promote merge row, the release CI row, the `release.sh` rule and the UAT rule.
- [ ] `.env.example` lists the names of the v1.0.0 template: `MIGRATE_AT_BUILD`, `VERCEL_TOKEN`, `VERCEL_TEAM`, `VERCEL_PROJECT` and `NEON_API_KEY`.
- [ ] The go-live stub `uat-environment.md` is `sequence: 1 of 9` and `priority: P0`, and has no `blocked:` line.
- [ ] `ci` is green.

## Notes

Jamie confirmed `release: true` and `uat: true` on 2026-10-27. `.icm/CONTEXT.md` stays: a separate pull request removes the legacy files. The UAT setup acts (the Vercel `uat` environment, the Neon `uat` branch, the DNS record) are the go-live stub `uat-environment.md`. Jamie made that stub the first of the epic on 2026-10-27. The release job opens no release pull request yet because `main` has no `feat:` or `fix:` commit. It needs no change.
