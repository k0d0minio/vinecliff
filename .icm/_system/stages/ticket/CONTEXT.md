# Stage — Ticket

Language: en

## Purpose
Turn the operator's words into one ticket that a run can start from. This stage writes
no product code, makes no branch and opens no pull request. It does not start the work.

## Inputs
- The operator's message: what is wrong or what is wanted.
- `.icm/_system/rules/ticket.md`.
- `.icm/project-rules.md`, only for the names of things.

Do not read the product code. One search to confirm a name or a path is permitted.

## Process
1. Find the one unit of work. If the message holds more than one, list the units and
   ask which one to write first. One ticket is one pull request.
2. Choose the lane, and say why in one sentence:
   - `bug`: the product does not do what it did, or what was agreed.
   - `tweak`: a small change that a user sees, with no new behaviour.
   - `chore`: upkeep that no user sees.
   - `hotfix`: production is broken now. Only when the operator says so.
   - `handover`: the record that the client needs to run the repo alone.
   - `knowledge`: one page of the project docs.
   - `spine`: all other work. It needs a spec and the Spec approved gate.
3. Find the questions: only what changes the ticket, three at most. Do not ask them in
   the chat. Write them in the format of `.icm/_system/rules/questions.md`, each with a
   default. The operator answers them on the HUD when the run starts. If the message is
   sufficient, write no question.
4. Write the acceptance criteria. Each one is a result that a person can see and check.
   Two to five criteria. Do not write how to build it.
5. Write the draft in the chat: a title, the lane as a label, the problem, the
   acceptance criteria, the questions. Write nothing in this repo. This stage does not write to Linear.
6. Stop with the stop report of `.icm/_system/rules/output.md`. The operator's acts: file
   the ticket in Linear, then say a start word with its key.

## Outputs
- One ticket draft in the chat. No file.
- No branch, no run folder, no pull request.

## Gates
- None. The start command is the operator's approval of the ticket.
