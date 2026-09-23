# Capability skills — three tiers, loaded on demand

`.icm/skills/<name>/SKILL.md` is a **capability skill**: a procedure a stage or lane follows
for one repeatable kind of work — a security audit, a database migration, a preview deploy.
The stage contracts under `stages/` and `lanes/` say *when* work happens; a skill says *how*
one kind of it is done, once, so no contract restates it and no session improvises it.

Each skill is written in three tiers, and the tiers are the point — the system prompt stays
lean and the detail arrives only when it is needed:

| Level | Where | What | When it is in context |
|---|---|---|---|
| **1 — Metadata** | the YAML front matter of `SKILL.md`: `name`, `description`, `triggers` | thirty to fifty tokens saying what the skill is for and the words that summon it | always — `.icm/scripts/list-skills.sh` prints every skill's Level 1 as one line, and the session-start hook injects that registry |
| **2 — Instructions** | the body of `SKILL.md` | the step-by-step procedure: which script, in which order, what its verdict means, what to write where | only when a trigger matches the work in front of the stage — the stage loads that one file |
| **3 — Execution assets** | `references/` and `scripts/` beside `SKILL.md` | checklists, pattern lists, tool notes, a runnable that wraps the template's scripts | on demand, from inside the body — never loaded speculatively |

## How a stage uses one

1. Read the registry — the session-start hook already printed it, or
   `.icm/scripts/list-skills.sh --bare`.
2. If one line's triggers match what the contract step is doing (a migration in `touches:`,
   a `security-critical` review pass, a ready flip), load that `SKILL.md` and follow its body.
3. Follow its body's pointers into `references/` only where the body says to.
4. Do not load a skill on the chance it helps: the contract's Inputs are the budget.

`_shared/project-rules.md` → Capability skills names any repo-specific skill the stages may
call beyond these; the harness-level skills under `.claude/skills/` (the `/pipeline` router,
`/setup`, `ticket-craft`, `pr-conventions`) are a different thing — they route and enforce,
they are not capability procedures.

## Writing one

- The folder name is the `name`. Keep Level 1 under 80 tokens (`list-skills.sh --check` says).
- `triggers` is a list (or a comma-separated line) of the words a stage will actually have in
  front of it — file paths, contract vocabulary, script names — not synonyms for the title.
- The body names the template's scripts by path and quotes their `RESULT:` vocabulary; it
  never restates a contract's steps, it slots into them.
- Level 3 runnables are invoked as `bash .icm/skills/<name>/scripts/<file>.sh` and wrap the
  template's own scripts — they carry no logic of their own that a script under
  `.icm/scripts/` does not already have.
- The three seeded skills are template-owned (`MANIFEST` → `T`): byte-identical everywhere,
  carrying no repo's identity, reading what is repo-specific from `.icm/project.json`. A
  repo's own skill is its own addition — say so in `_shared/project-rules.md`.
