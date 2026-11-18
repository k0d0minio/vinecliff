# Handoff jam-276

## Next action

The operator reads `.icm/project-rules.md`, ticks Ready to merge on the pull request #41, then
presses "Merge now" on the HUD card or says `release JAM-276`.

## What changed

- `.icm/project-rules.md`: the stack, the conventions of the code, the docs folder
  (`.icm/docs/`) and where a change goes today.
- `.icm/local/ROUTES.md`: the Linear ticket of each open stub of `go-live`.

No user sees a difference: the two files are read only by a session. No product file changed.

## How to test

Open the pull request and read the two files. Each rule must be true for the repo today.

## Blockers

- The operator's tick of Ready to merge.

## Do not touch

- none
