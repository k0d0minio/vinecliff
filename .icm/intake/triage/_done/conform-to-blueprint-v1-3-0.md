# Stub: The repo renders from the blueprint v1.3.0

- lane: chore
- found-by: the house drift report `desk/estate/drift-2026-10-29.md` · 2026-10-29
- complexity: low
- priority: P2

## Problem

`.copier-answers.yml` names blueprint v1.0.3. The blueprint is at v1.3.0 (2026-10-29).

- v1.3.0: `new-run.sh` keeps the branch of a worktree, and `.icm/scripts/worktree-setup.sh` installs the dependencies of a new ticket worktree. The blueprint renders no `.emdash.json` and no `.goosehints`.
- v1.2.0 and v1.3.0: `.icm/environments.md` holds the environments table, and `AGENTS.md` points an agent at `CLAUDE.md`.

## Proposed change

Run `copier update` to v1.3.0 with the answers of record. Make no hand edit to a file that the blueprint renders.

## Acceptance criteria

- [ ] `.copier-answers.yml` names `v1.3.0`. Its other lines change only where the blueprint removed a question.
- [ ] The repo has `.icm/scripts/worktree-setup.sh` and the `new-run.sh` of v1.3.0, and no `.emdash.json` and no `.goosehints`.
- [ ] `check-client` is green.
