# Lane — chore

Language: en

## Purpose
Do one piece of upkeep that no user can see: a dependency, a config value, a rename, a
dead file, a document.

## Inputs
- The ticket (`.icm/_system/rules/ticket.md`).
- `.icm/_system/rules/lane.md` — the flow.
- `.icm/project-rules.md`.
- The files that the chore names.

## Process
Follow the flow in `rules/lane.md` with the lane name `chore`. These points are specific:
1. The product must behave the same before and after. If a user can see a difference,
   stop: the ticket is a `tweak` or needs `new`.
2. Do one chore in one run. Do not add a second chore that you see on the way. Write it
   in `findings.md`.
3. In `handoff.md`, write what changed and why no user sees it.

## Outputs
- The change, pushed, in a ready pull request with CI green.
- `run.md`, `status.md` (`phase: release`) and `handoff.md`.

## Gates
- Ready to merge: the operator ticks it. Release merges. You do not tick it.
