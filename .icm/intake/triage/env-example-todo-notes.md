# Stub: .env.example carries 17 names with a TODO instead of a note

- lane: chore
- found-by: triage/declare-node-env-in-env-example · 2026-10-22
- complexity: low
- priority: P2

## Problem

`.env.example` lists 17 Neon and Postgres names under `# TODO: note  [production,preview]`,
from `DATABASE_URL_UNPOOLED` to `VITE_NEON_AUTH_URL`. No note says what each one is for. The
code reads none of them. The Vercel + Neon integration sets them.

## Proposed change

Drop the 17 names, or keep them under one note that says the integration sets them and the
code does not read them.

## Acceptance criteria

- [ ] `.env.example` has no `TODO` line.
- [ ] Every name in `.env.example` has a note, or is gone.
