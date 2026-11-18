# Lane — handover

Language: en

## Purpose
Write `HANDOVER.md` at the root of the repo: what the client needs to run the repo with
no operator. The operator starts it when the build is complete.

## Inputs
- The ticket (`.icm/_system/rules/ticket.md`).
- `.icm/_system/rules/lane.md` — the flow.
- `.icm/project-rules.md`, `.icm/project.json`, `.icm/environments.md`.
- The README, the CI workflows, the config files, and the code that reads the environment.

## Process
Follow the flow in `rules/lane.md` with the lane name `handover`. These points are specific:
1. Change no product code. A gap is an entry in `findings.md`: a fix is its own ticket.
2. Write `HANDOVER.md` with four sections:
   - Accounts: each service of the repo, in whose name, the transfer that is owed, and
     its owner.
   - Environment: each key that the code reads, and where it is set.
   - Run and deploy: the commands, and what moves each environment.
   - Open points: each gap, with its owner.
3. Never write a value, a password or a key. If you find a plaintext credential, say it
   in full at the stop.
4. Send nothing. Create, move and invoice nothing. Each transfer, invoice and message is
   an `Operator:` act of the stop report. Add the money line that the ticket names:
   final invoice, retainer or support.
5. In `handoff.md`, How to test: read `HANDOVER.md` on the pull request.

## Outputs
- `HANDOVER.md`, pushed, in a ready pull request with CI green.
- `run.md`, `status.md` (`phase: release`) and `handoff.md`.

## Gates
- Ready to merge: the operator ticks it. Release merges. You do not tick it.
