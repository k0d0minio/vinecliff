# Ticket rules

Linear is the source of the tickets. The business scopes the work in Linear.

## Rules
1. **No ticket, no run.** A request with no ticket key starts nothing. Ask for the key.
2. **One ticket, one run, one branch, one pull request.** A follow-up needs a new ticket.
3. **The ticket is the requirement.** Do not change its scope. If only the business can
   close a gap, write the question in the stop report and stop. The operator asks in
   Linear.
4. **The session reads Linear. The scripts do not.** Read the ticket with the Linear MCP
   tool `get_issue`: title, description, labels, state, `gitBranchName`, URL. Give these
   values to a script as flags. If the MCP is not connected, stop. Do not work from memory.
   A session that BAXTER started uses the command of its first message, not the MCP tool.
5. **This pipeline does not write to Linear.** Put each draft comment or new issue in
   `findings.md`. The operator files them.
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

