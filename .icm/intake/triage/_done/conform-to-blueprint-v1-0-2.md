# Stub: The repo renders from the blueprint v1.0.2

- lane: chore
- found-by: the house drift report `desk/estate/drift-2026-10-28.md` · 2026-10-28
- complexity: low
- priority: P2

## Problem

`.copier-answers.yml` names blueprint v1.0.0. The blueprint is at v1.0.2 (2026-10-28). In v1.0.2, each GitHub call in `.icm/scripts/` goes through the REST API, because a Claude Code cloud session gets HTTP 403 on GraphQL. The router finds the pull request of `merge <slug>` with a REST read, and `.claude/settings.json` allows `merge.sh` and `release.sh`.

## Proposed change

Run `copier update` to v1.0.2 with the answers of record. Keep the repo's own files as they are: `README.md`, `.icm/intake/README.md`, `CLAUDE.md` and `.gitignore`.

## Acceptance criteria

- [ ] `.copier-answers.yml` names `v1.0.2`, and its other lines do not change.
- [ ] No file of the repo's own changes.
- [ ] `ci` is green.
