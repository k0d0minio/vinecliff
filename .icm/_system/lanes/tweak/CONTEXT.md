# Lane — tweak

Language: en

## Purpose
Make one small change that a user can see: a text, a style, a layout, a default value.
A tweak adds no new behaviour.

## Inputs
- The ticket (`.icm/_system/rules/ticket.md`).
- `.icm/_system/rules/lane.md` — the flow.
- `.icm/project-rules.md`.
- The files that show the thing to change.

## Process
Follow the flow in `rules/lane.md` with the lane name `tweak`. These points are specific:
1. Make the change that the ticket names, and no other change.
2. If the change needs new logic, new data or a decision about the product, stop: the
   ticket needs `new`.
3. In `handoff.md`, write the page or screen where the operator can see the change.

## Outputs
- The change, pushed, in a ready pull request with CI green.
- `run.md`, `status.md` (`phase: release`) and `handoff.md`.

## Gates
- Ready to merge: the operator ticks it. Release merges. You do not tick it.
