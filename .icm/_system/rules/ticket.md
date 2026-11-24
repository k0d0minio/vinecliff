# Ticket rules

Linear is the source of the tickets. The business scopes the work in Linear.

## Rules
1. **No ticket, no run.** A request with no ticket key starts nothing. Ask for the key.
2. **One ticket, one run, one branch, one pull request.** A follow-up needs a new ticket.
3. **The ticket is the requirement.** Do not change its scope. If only the business can
   close a gap, write the question in the stop report and stop. Post it on the ticket
   too (rule 5).
4. **The session reads the ticket. The scripts do not.** Read it with the BAXTER tool:
   `~/baxter_live/system/bin/baxter_tool run linear get_issue '{"org":"kodominio","key":"<KEY>"}'`
   (its `branch` is `gitBranchName`). Do not use a Linear MCP tool (rule 9 of the router).
   If the BAXTER read fails, stop and give its error. Do not work from memory.
   Give the title, the branch and the URL to a script as flags.
   A session that BAXTER started uses the command of its first message.
5. **The session makes its own ticket acts in Linear.** It uses the
   BAXTER Linear tool, with no yes for each write: a comment on the run's ticket, a new
   issue in Triage, a relation. Read `.icm/_system/features/linear-writes.md` before the
   first write. Each act has its entry in `findings.md`.
6. **No bulk sync.** A ticket enters this repo only when the operator starts it.

## One key, three spellings
| Form | Example | Where |
|---|---|---|
| Key | `JAM-123` | Pull request title, `run.md`, prose |
| Run id | `jam-123` | The run folder `.icm/runs/jam-123/` |
| Branch | Linear's `gitBranchName` | Read it from the ticket. Do not make it |

A key from another team is refused. The team key is `linear.team_key` in `.icm/project.json`.

## The intake folder
- Before the spec approval: nothing is in `.icm/intake/` for the ticket.
- At the spec approval: Build writes the stub `.icm/intake/tickets/<KEY>.md` with
  `resolve-run.sh <KEY> --write-stub`. A lane writes it when the run starts.
- At the close-out: the stub moves to `.icm/intake/_done/<KEY>.md`.

The stub is a pointer: key, title, URL, branch, run. Linear holds the requirement.

