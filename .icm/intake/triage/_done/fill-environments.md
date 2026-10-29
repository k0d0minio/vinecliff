# Stub: .icm/environments.md says where the build runs, read from Vercel and Neon

- lane: chore
- found-by: house stub `blueprint-environments/estate-environments-file` · 2026-10-29
- complexity: low
- priority: P2

## Problem

`copier update` to v1.3.0 gave `.icm/environments.md` with `<…>` cells for the addresses and the Vercel project.

## Proposed change

Fill each cell from Vercel and Neon, read on 2026-10-29. Mark a cell that a read cannot fill `<…>`, with the reason. Jamie confirms each marked cell.

## Acceptance criteria

- [ ] `.icm/environments.md` has the five columns, and each cell is filled from Vercel and Neon or marked `<…>`.
- [ ] The `Vercel project` cells and the projects linked to the repository are one set.
- [ ] `check-client` is green.
