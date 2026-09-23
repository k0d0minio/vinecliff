# Stub: Declare NODE_ENV in .env.example

- lane: chore
- found-by: pipeline template sync (k0d0minio/vinecliff#17) · 2026-09-23
- priority: P2

## Problem

`.icm/scripts/env.sh audit` reports `RESULT: GAPS 1`: the code reads `process.env.NODE_ENV` and
no `.env.example` declares it. It is also the one WARN in `setup.sh --report` step 4.

## Proposed change

Run `.icm/scripts/env.sh doc NODE_ENV` (or add the line by hand) so `.env.example` documents it
as set by the runtime, never by hand; re-run `env.sh audit` until it reads no GAP.

## Prompt

In the vinecliff repo, close the `env.sh audit` gap for `NODE_ENV`. Read
`.icm/intake/triage/declare-node-env-in-env-example.md`, then use `.icm/scripts/env.sh doc
NODE_ENV` and confirm `.icm/scripts/env.sh audit` shows no GAP. Names only — never a value.
