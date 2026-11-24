# The run folder

A run is the work on one ticket. Its record is the folder `.icm/runs/<id>/`, on the run's
branch. The run id is the lower-case ticket key (`sus-123`) or the stub slug.

## Files
| File | Holds | Written by |
|---|---|---|
| `run.md` | Ticket, title, link, branch, lane, pull request | `new-run.sh` |
| `spec.md` | The spec. Spine runs only | Define |
| `status.md` | `phase`, `blocked`, `updated` | Each stage, at each stop |
| `handoff.md` | Next action, blockers, what not to touch | Each stage, at each stop |
| `findings.md` | Findings that are not part of the ticket. Optional | Any stage |

The templates are in `.icm/_system/templates/`.

## Rules
1. **A session continues from the folder.** A later session reads `run.md`, `status.md`
   and `handoff.md`. It does not read an earlier chat. Thus write each fact that a
   later session needs in a file.
2. **Rewrite `handoff.md` at each stop.** It says what the next session does first.
3. **Keep `status.md` true.** `phase` is `define`, `build` or `release`. Set `blocked: yes
   — <reason>` when the run waits for a person.
4. **One run, one folder.** A run does not write in another run's folder, and it does
   not change `.icm/_system/`.
5. **A finding is not a task.** If you see a fault that the ticket does not cover, add
   one entry to `findings.md` and continue with the ticket. The session files it in
   Linear: rule 5 of `rules/ticket.md`.

## The end of a run
`close-out.sh <ticket>` runs on the run's branch, before the merge. It moves `run.md`,
`spec.md`, `handoff.md` and `findings.md` to `.icm/archive/<id>/`. It deletes
`status.md`. It moves the ticket stub to `_done/`. The merge publishes these moves.
Its commit changes only records: CI does not run the job `code` again when `code` is
green on an earlier commit of the branch (`ci/icm-only.sh`).

A run in `.icm/archive/` is a record. Do not read it as an instruction, and do not
start it again.
