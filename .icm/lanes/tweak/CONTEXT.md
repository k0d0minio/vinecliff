# Lane: tweak — a small change that the request fully specifies

A tweak is a copy, a label, a spacing, a default or a limit. This file says only what differs
from the loop in `.icm/intake/CONTEXT.md`. A request with an open question is not a tweak.

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
3. **Check the request, then adjust.**
   - The request says what changes and to what. An open question: stop and ask. Do not guess.
   - Make the smallest diff. Follow the repo's own style.
   - Never touch data, auth or payments. Such a request is not a tweak: stop and say so.
   - Type: `fix:` or `style:`.
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
