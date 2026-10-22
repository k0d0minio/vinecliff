# Stub: Declare NODE_ENV in .env.example

- lane: chore
- found-by: pipeline template sync (k0d0minio/vinecliff#17) · 2026-09-23
- priority: P2

## Problem

The old env audit found one gap: the code reads `process.env.NODE_ENV` and
no `.env.example` declares it. It is also the one WARN in `setup.sh --report` step 4.

## Proposed change

Add the line by hand so `.env.example` documents it
as set by the runtime, never by hand.

## Prompt

In the vinecliff repo, declare `NODE_ENV` in `.env.example`. Read
`.icm/intake/triage/declare-node-env-in-env-example.md`, then add the `NODE_ENV` line to `.env.example` by hand. Names only — never a value.
