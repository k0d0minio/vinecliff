# Stage — Build

Language: en

## Purpose
Make the change that the approved spec describes, on the run's branch, until CI is green.

## Inputs
- `.icm/runs/<id>/spec.md`, `run.md`, `status.md`, `handoff.md`.
- `.icm/project-rules.md`.
- The code in the paths that the spec names in `touches:`, and what that code calls.
- `.icm/_system/rules/github.md` and `.icm/_system/rules/run.md`.

## Process
1. `.icm/_system/scripts/resolve-run.sh <ticket>`. Continue only on `RESULT: OK`. If it
   names another branch, switch to that branch and run it again. On `conflict: yes`, do its
   line "Do this first" first (`rules/github.md`, Runs in parallel).
2. Read `spec_approved` in its output. If the value is not `yes`, stop. Tell the operator
   to tick Spec approved, and give the pull request link.
3. `resolve-run.sh <ticket> --write-stub`. For a Linear ticket it writes the intake stub.
   Commit the stub.
4. Set `status.md` to `phase: build`.
5. Make the change. Do what the spec says and no more. If the spec is wrong or
   incomplete, stop and say `revise` is necessary. Do not decide a requirement here.
6. Commit small and push. Merge the default branch into the run's branch when it moved.
7. Change the pull request to ready (`rules/github.md`).
8. `.icm/_system/scripts/ci-status.sh <number> --watch`, one time. On RED, read the failed check,
   correct the cause, push and read again. On PENDING after the wait, stop and say so.
9. Check each acceptance criterion as its `verify:` says: `CI` by the green run and not
   by hand, `agent` on the preview. Write in `handoff.md` which criteria are met. Write
   the section How to test from the `operator` criteria: 1 to 3 short sentences that
   can be said aloud. Do not tick a box.
10. Set `status.md` to `phase: release`, and the status of each client request of the
    spec to `built` (`features/requests.md`). Commit and push.
11. Show the gate card (`rules/gates.md`).
12. Stop with the stop report. The operator's acts: test the change on the preview,
    tick **Ready to merge** on GitHub or on the HUD card, then say `release <ticket>`.

## Outputs
- The product change, committed and pushed on the run's branch.
- The pull request ready, with CI green.
- `status.md` (`phase: release`) and `handoff.md`, both current.
- For a Linear ticket: `.icm/intake/tickets/<KEY>.md`.

## Gates
- Spec approved must be ticked before step 3.
- Build ends at green CI. It does not merge.
