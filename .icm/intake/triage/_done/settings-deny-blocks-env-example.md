# Stub: The settings deny list blocks reading .env.example
> Done elsewhere — retired 2026-09-26 (estate audit): fixed by 7654127 — `.claude/settings.json:5-12` denies the secret env files by name and `.env.example` is readable.

- lane: chore
- found-by: pipeline template sync (k0d0minio/vinecliff#17) · 2026-09-23
- priority: P2

## Problem

`.claude/settings.json` denies `Read(./.env.*)` and `Read(./**/.env.*)`, which also covers
`.env.example` — the variable manifest the pipeline reads (`env.sh audit`, project-rules.md →
Environment surfaces). An agent cannot read the manifest it is asked to maintain. The estate
template (`_system/template/claude/settings.json` in icm-board) denies the real env files by
name (`.env`, `.env.local`, `.env.*.local`, `.env.development`, `.env.production`,
`.env.preview`, `.env.test`, `.env.vercel`) and leaves `.env.example` readable.

## Proposed change

Replace the deny list in `.claude/settings.json` with the template's, keeping the `hooks` block
as it is. No other change.

## Prompt

In the vinecliff repo, make `.env.example` readable to agents while keeping every real env file
denied. Read `.icm/intake/triage/settings-deny-blocks-env-example.md`: replace the `deny` list
in `.claude/settings.json` with the estate template's (listed in the stub), leave the hooks
untouched, and confirm no real `.env*` file becomes readable.
