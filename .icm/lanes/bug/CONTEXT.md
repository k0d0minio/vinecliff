# Lane: bug — a fault, fixed at its cause

A bug is behaviour that differs from what the code or a ticket promised. This file says only
what differs from the loop in `.icm/intake/CONTEXT.md`. A fix that needs a product decision is
not a bug: step 3 says what to do.

## Inputs

- The triage stub `.icm/intake/triage/<slug>.md`, or the report in the chat when there is no stub.
- `CLAUDE.md`.
- The files that the fault implicates. Nothing else.

## Process

1. **The stub.** A request that names an open triage stub: take that stub. A report with no
   stub: write the stub first, at `.icm/intake/triage/<slug>.md`, in the shape of
   `.icm/intake/CONTEXT.md` § The triage stub. Write `lane: <this lane>` and `found-by: <where> ·
   <YYYY-MM-DD>`. Do not commit it.
2. **Start.** Run `.icm/scripts/new-run.sh triage/<slug>`. The script drops the Spec approved
   gate for a triage stub. The hotfix lane adds `--ready`.
3. **Reproduce, then fix.**
   - Reproduce first. Write `Observed: <one line>` and `Expected: <one line>` as the first two
     lines of `What changes`.
   - No reproduction: stop with the stop report, and say what you tried. The draft stays open.
   - Fix the cause, not the symptom. Make the smallest diff. Do not refactor on the way.
   - Where the repo has a test runner, add a test that fails before the fix. CI runs it.
   - A fix that needs a product decision: stop, and cut an epic instead (§ A request with no
     stub, case 2).
   - Type: `fix:`.
4. **Build.** Do the loop's step 4. Commit with this lane's type from § Commit types. Push.
   Read CI once with `.icm/scripts/checks.sh <n> --watch`.
5. **Park.** Every finding that is not this ticket's becomes a triage stub in the same pull
   request, as the loop's step 5 says.
6. **Ready.** Fill the `preview:` line. Flip the pull request to ready, as the loop's step 6
   says. A hotfix is ready from the start. Stop with § The stop report.
7. **Merge.** Ready to merge stays. Jamie ticks it, and the session merges, as the loop's
   step 7 says.

A lane never edits a file the blueprint renders: every file under `.claude/`, `.icm/lanes/`,
`.icm/scripts/` and `.icm/uat/`, and `.icm/intake/CONTEXT.md`, `.github/pull_request_template.md`
and the workflows the blueprint renders. Such a request goes to the blueprint. Stop. Name the
file and the change under `Operator:` in the stop report. Open nothing in the blueprint: it is
public (why: every build shares the blueprint's copy, and a local edit conflicts on the next
`copier update` · 2026-10-27).

## Outputs

- The branch `triage/<slug>` and one pull request.
- The stub in `.icm/intake/triage/_done/<slug>.md`.
- Commits of this lane's type, and the parked triage stubs under `Parked`.
- The stop report in the chat.
- In `What changes`: the `Observed:` and `Expected:` lines. The test, where the repo has a test runner.
