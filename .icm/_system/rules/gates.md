# Gates

A gate is a checkbox in the body of the run's pull request. Only the operator ticks a gate.
An agent reads a gate. An agent never ticks, edits or removes a gate box.

The operator ticks a gate in one of two ways:
- in the pull request on GitHub, or
- with its button ("Spec approved, tick it", "Ready to merge") on the gate card of the
  BAXTER HUD. The HUD then ticks that one box. The press is the operator's act.

To show the gate card, run `~/baxter_live/system/bin/baxter_gate.py card <number>`, if that file
exists. For a page change, start the agent `review-shots` first: it takes the pictures
from the local dev server (`dev-server.sh`), else from the preview. The card shows the
summary, How to test of `handoff.md`, the checks and the preview.

After the tick, the card has the button "Merge now". It runs the Release stage
(`release.sh`) for that pull request. The tick does not merge. Release merges.

## The two gates
| Gate | Anchor in the pull request body | Meaning of the tick |
|---|---|---|
| Spec approved | `<!-- gate:spec-approved -->` | Build can start |
| Ready to merge | `<!-- gate:ready-to-merge -->` | The operator tested the change. The merge is authorised |

The gate is the first checkbox line below its anchor.

- A spine run (Define, Build, Release) has both gates.
- Each lane run (a folder of `lanes/`) has only Ready to merge.
- A missing anchor means "not required". It does not mean "not ticked".

## How to read a gate
Run `.icm/_system/scripts/resolve-run.sh <ticket>`. It prints `spec_approved:` and
`ready_to_merge:` with the value `yes`, `no` or `none`. Do not read a gate from memory or
from chat. If the operator says "approved" and the box is not ticked, say that the box is
not ticked and give the pull request link.

## What enforces a gate
- Build stops when `spec_approved` is not `yes`.
- `release.sh` and `merge.sh` refuse when `ready_to_merge` is not `yes`.
- The check `icm-gate` shows "Waits for the operator" (action required) while Ready to
  merge is not ticked. A ruleset that requires it makes GitHub refuse the merge too.

That wait is not a failure. `ci-status.sh` does not count `icm-gate`: a pull request that
waits only for the tick is GREEN. A review or a status report says "waits for the
operator's tick", never "icm-gate failed".