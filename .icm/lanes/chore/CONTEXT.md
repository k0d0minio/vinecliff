# Lane: chore — work with no change in behaviour

A chore is a refactor, a dependency bump, a migration, a cleanup, or a change to CI or the
tooling. This file says only what differs from the loop in `.icm/intake/CONTEXT.md`. A change
that a user can see is not a chore.

## Inputs

- The triage stub `.icm/intake/triage/<slug>.md`, or the report in the chat when there is no stub.
- `CLAUDE.md`.
- The files that the request implicates. Nothing else.

## Process

1. **The stub.** A request that names an open triage stub: take that stub. A report with no
   stub: write the stub first, at `.icm/intake/triage/<slug>.md`, in the shape of
   `.icm/intake/CONTEXT.md` § The triage stub. Write `lane: <this lane>` and `found-by: <where> ·
   <YYYY-MM-DD>`. Do not commit it.
2. **Start.** Run `.icm/scripts/new-run.sh triage/<slug>`. The script drops the Spec approved
   gate for a triage stub. The hotfix lane adds `--ready`.
3. **State the invariant, then do the work.**
   - Write `Invariant: behaviour unchanged, only <X> differs.` as the first line of `What
     changes`.
   - One purpose per pull request. A second purpose is a second triage stub (step 5).
   - A dependency bump names the version delta: `<package> <from> → <to>`.
   - Migrations are forward-only. The reverted code tolerates the newer schema (the UAT
     contract's rule, 2026-10-23).
   - A change that a user can see: stop, and take the bug or the tweak lane.
   - Type: `chore:`, `refactor:`, `build:` or `ci:`.
4. **Build.** Do the loop's step 4. Commit with this lane's type from § Commit types. Push.
   Read CI once with `gh pr checks <n> --watch`.
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
- In `What changes`: the `Invariant:` line.
