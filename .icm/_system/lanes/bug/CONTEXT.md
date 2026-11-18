# Lane — bug

Language: en

## Purpose
Correct one fault: the product does not do what it did, or what its spec says.

## Inputs
- The ticket (`.icm/_system/rules/ticket.md`).
- `.icm/_system/rules/lane.md` — the flow.
- `.icm/project-rules.md`.
- The code where the fault is, and what that code calls.

## Process
Follow the flow in `rules/lane.md` with the lane name `bug`. These points are specific:
1. Before you change code, find the cause. Write the cause in one sentence in
   `handoff.md`. If you cannot find it, stop and say what you checked.
2. Correct the cause, not the symptom.
3. Change only what the fault needs. If the correction needs a new behaviour or a
   decision about the product, stop: the ticket needs `new`.
4. In `handoff.md`, write how the operator can see that the fault is gone.

## Outputs
- The correction, pushed, in a ready pull request with CI green.
- `run.md`, `status.md` (`phase: release`) and `handoff.md` with the cause.

## Gates
- Ready to merge: the operator ticks it. Release merges. You do not tick it.
