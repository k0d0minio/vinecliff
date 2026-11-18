# Router — vinecliff

Language: en

Do not edit `.icm/_system/`: it belongs to the blueprint. Tell the operator about a fault
in it. All other files in `.icm/` belong to this repo.

## Commands
A command is a word and one ticket. A ticket is a Linear key: `JAM-123`.

| The operator says | Read and follow |
|---|---|
| `ticket` and what is wanted, or "write a ticket" | `.icm/_system/stages/ticket/CONTEXT.md` |
| A start word and a ticket | `.icm/_system/stages/define/CONTEXT.md` |
| A lane and a ticket | `.icm/_system/lanes/<lane>/CONTEXT.md` |
| `build` and a ticket | `.icm/_system/stages/build/CONTEXT.md` |
| `release` and a ticket | `.icm/_system/stages/release/CONTEXT.md` |
| `revise` and a ticket and a change | `.icm/_system/stages/define/CONTEXT.md`, section Revise |
| `status`, `approve`, `release` with no ticket, `promote`, `rollback` | `.icm/_system/features/uat.md` |

Start words: `new`, `pick up`, `start work on`, and the phrases in
`.icm/_system/rules/triggers.txt`. The intent decides. A question about a ticket is not a
command. If the
intent is unclear, ask one question.

When the hook `route-request` prints `[icm-router] Route:`, follow that line. If
`.icm/local/ROUTES.md` exists, read it for this repo's own routes.

## Rules for each stage and lane
1. Read the contract. Then read only the files that its Inputs name.
2. First act: `.icm/_system/scripts/resolve-run.sh <ticket>`. Obey its `RESULT:` line.
3. A run writes only in `.icm/runs/<id>/` and in the product code, on its own branch.
4. Never tick a gate box. Read `.icm/_system/rules/gates.md`.
5. Do not run a local build, test, lint or format command. CI is the source of truth.
   Read it with `.icm/_system/scripts/ci-status.sh`.
6. Write a finding that is not part of the ticket in `.icm/runs/<id>/findings.md`.
7. End each session with the stop report of `.icm/_system/rules/output.md`.
8. Write the documents of a run in the language at the top of this file.

## One home for each fact
| Fact | Home |
|---|---|
| Ticket rules and the intake folder | `.icm/_system/rules/ticket.md` |
| Gates | `.icm/_system/rules/gates.md` |
| Questions for the operator | `.icm/_system/rules/questions.md` |
| Git and GitHub | `.icm/_system/rules/github.md` |
| The run folder | `.icm/_system/rules/run.md` |
| What a session says in chat | `.icm/_system/rules/output.md` |
| Values and rules of this repo | `.icm/project.json`, `.icm/project-rules.md` |
| Addresses | `.icm/environments.md` |
