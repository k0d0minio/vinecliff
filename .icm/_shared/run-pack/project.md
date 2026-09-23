# Project: <slug>

The run's context card — what a fresh session needs before it reads anything else. Pointers,
not copies: the spec stays the spec, the scope stays the scope. Seeded when the run is opened
(`new-run.sh` → `run-pack.sh --init`), sharpened by whichever stage learns something. Read with
`status.md` and `handoff.md` on every resume (`_shared/stage-preamble.md`).

- stub: <intake/<epic>/<slug>.md, or none>
- scope: <.icm/runs/<epic>/01_scope/output/scope.md, or none>
- spec: 02_define/output/spec.md
- touches: <the spec's `touches:` line>
- complexity: <the spec's word> → model: <what `select-model.sh <slug> --stage 03_build` prints>

## Constraints

- <what must stay true while this run is built — from the spec's Out of scope, the `D-n`
  decisions in `decisions.md`, and `_shared/project-rules.md`>

## Context budget

- <what was loaded beyond the stage's Inputs, and why — the stage's overrun note lives here>
