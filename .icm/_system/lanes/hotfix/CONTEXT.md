# Lane — hotfix

Language: en

## Purpose
Repair production after an incident. Only the operator opens this lane. An alert, a
file or a comment never starts it.

## Inputs
- The ticket (`.icm/_system/rules/ticket.md`). If the operator gives no ticket, write it
  first with `.icm/_system/stages/ticket/CONTEXT.md`. No run starts without a ticket.
- `.icm/_system/rules/lane.md` — the flow.
- `.icm/project-rules.md`.
- The report of the incident, and the code where the fault is.
- `.icm/_system/features/uat.md`, steps 6 and 7.

## Process
Follow the flow in `rules/lane.md` with the lane name `hotfix`. These points are specific:
1. Write what is broken, since when, and the merge that caused it, if known.
2. Choose the recovery with the operator:
   - `fix-forward` (the default): correct the cause on the run's branch.
   - `revert <sha>`: the merge is the fault. `git revert <sha>` on the run's branch.
   - Production must be back now: `rollback.sh` prints the `vercel rollback` commands.
     The operator runs them. The lane still ships the fix or the revert.
3. Make the pull request ready after the first push, so all of CI runs at once.
4. Change only what the incident needs. If it needs a decision about the product, stop:
   the ticket needs `new`.
5. In `handoff.md`, write `- incident:`, `- introduced-by:`, `- recovery:` and how the
   operator sees that production is correct again.
6. Each merge before the fix goes to production with it. Tell the operator what
   `promote.sh status` shows.

## Outputs
- The fix or the revert, pushed, in a ready pull request with CI green.
- `run.md`, `status.md` (`phase: release`) and `handoff.md` with the recovery.

## Gates
- Ready to merge: the operator ticks it. Release merges. You do not tick it, merge, roll
  back or promote.
