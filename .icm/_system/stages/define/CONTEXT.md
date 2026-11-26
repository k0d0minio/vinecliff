# Stage — Define

Language: en

## Purpose
Turn one ticket into a spec that the operator can approve, and open the run's one pull
request. Define writes no product code.

## Inputs
- The ticket. Read it as `.icm/_system/rules/ticket.md` says.
- The operator's message, for what the ticket leaves open.
- `.icm/_system/templates/spec.md`.
- The client requests that the ticket names, and `.icm/_system/features/requests.md`.
- `.icm/project-rules.md`, only to name real paths in `touches:`.

Do not read the wider codebase. A few searches to confirm a path are permitted.

## Process
1. `.icm/_system/scripts/resolve-run.sh <ticket>`. Continue only on `RESULT: NONE`. On
   another result, obey it and stop.
2. Read the ticket. Stop if it is done, cancelled or blocked.
3. Find the gaps that the ticket leaves to the developer: behaviour at the edges, error
   and empty states, the paths in `touches:`. Each gap that changes what gets built is a
   question. Write the questions in `.icm/runs/<id>/questions.md`
   (`.icm/_system/rules/questions.md`). Do not ask them in the chat. If only the business
   can close a gap, stop and say so.
4. Write `.icm/runs/<id>/spec.md` from the template, with your default for each question.
   Each acceptance criterion is a result that a person can see and check. It ends with
   who verifies it: `(verify: CI)`, `(verify: agent)` or `(verify: operator)`. Put each thing that you will not do in Out of scope.
   Cite the client requests in `- requests:` and keep their AC lines as they are. A
   convention against a request: write `conflicts:` and ask, as `features/requests.md`
   says. Do not change the request. Set its status to `specified`.
5. `.icm/_system/scripts/validate-spec.sh <ticket>`. Correct each line that it lists.
6. `.icm/_system/scripts/new-run.sh <ticket>` with the flags that `rules/ticket.md` asks
   for, and `--summary "<one sentence: what a user can do after this change>"`. It makes
   the branch, `run.md`, `status.md`, `handoff.md` and the draft pull request.
7. If a question waits: follow the flow of `rules/questions.md` (show the question card,
   set `blocked`, stop). When the operator says `new <ticket>` again: run `questions.sh`,
   put the answers in `spec.md`, commit, push, and run `new-run.sh <ticket> --refresh-body`.
8. Write `handoff.md`: the operator ticks Spec approved, then says `build <ticket>`.
   Commit and push.
9. Stop with the stop report of `.icm/_system/rules/output.md`. Name each choice in the
   spec that the operator must check before the approval.

### Revise
The command `revise <ticket> "<change>"` changes a spec that exists.
1. `resolve-run.sh <ticket>`. Continue only on `RESULT: OK`.
2. If the change alters the requirement and not its implementation, stop. That is a
   question for the ticket.
3. Edit `spec.md`. Run `validate-spec.sh <ticket>`. Commit and push.
4. `new-run.sh <ticket> --refresh-body`. All boxes are then not ticked.
5. Stop. Tell the operator to tick Spec approved again.

## Outputs
- `.icm/runs/<id>/spec.md`, `run.md`, `status.md` (`phase: define`), `handoff.md`.
- One draft pull request with both gate boxes not ticked.
- All of it committed and pushed on the run's branch.

## Gates
- Spec approved: the operator ticks the box in the pull request. Build does not start
  before the tick. You do not tick it.
