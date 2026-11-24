# The lane flow

A lane is a fast path for a small ticket. Each folder of `.icm/_system/lanes/` is one
lane. A lane run has no spec and no Spec approved gate. It is one session, from the
ticket to a green pull request. Each lane contract names what differs from this flow.

## Flow
1. `resolve-run.sh <ticket>`. Continue only on `RESULT: NONE`. On `RESULT: OK` the run
   exists: read `handoff.md` and continue from it. On `conflict: yes`, do its line "Do this first" first
   (`rules/github.md`, Runs in parallel).
2. Read the ticket (`rules/ticket.md`). If the work is larger than the lane permits,
   stop and say that the ticket needs `new`.
3. If the ticket has questions, or you have one that changes the result: write them in
   `.icm/runs/<id>/questions.md` (`rules/questions.md`). Do not ask them in the chat.
4. Start the run: `new-run.sh <ticket> --lane <lane>`, with the flags that
   `rules/ticket.md` asks for. It makes the branch, the run folder and the draft pull
   request. If a question waits: follow the flow of `rules/questions.md` and stop. When
   the operator says the lane command again, run `questions.sh` and continue.
5. Make the change on the run's branch. Read `.icm/project-rules.md` first.
6. Commit and push. Change the pull request to ready (`rules/github.md`).
7. `ci-status.sh <number> --watch`, one time. On RED, correct the cause and push again.
8. Set `status.md` to `phase: release`. Write `handoff.md`, with the section How to test:
   1 to 3 short sentences that can be said aloud. Commit and push.
9. Show the gate card (`rules/gates.md`).
10. Stop with the stop report (`rules/output.md`). The operator's acts: test the change,
    tick **Ready to merge** on GitHub or on the HUD card, then press "Merge now" on the
    card or say `release <ticket>`.

Release closes the run and merges it. A lane does not merge.
