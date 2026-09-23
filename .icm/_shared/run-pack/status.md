# Status: <slug>

Where the run is, in five lines. Updated at every stage start and stop, and whenever a flag
flips. A resuming session reads this first, then `handoff.md` (`_shared/stage-preamble.md`).

- phase: <scope | define | build | release | lane>
- step: <the contract step the stage is on, or "done">
- ci: <GREEN | RED | PENDING | none yet>
- blocked: <no | yes — why, and who unblocks it>
- updated: <YYYY-MM-DD>
