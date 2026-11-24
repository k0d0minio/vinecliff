# UAT — the client test, the release and the promotion

Language: en

## Purpose

The client tests each batch of merged work at one fixed address. Production changes only
when the operator says so, after the client said yes.

## Inputs

- `.icm/environments.md`: the addresses. Read the UAT address there.
- `promote.sh status`: the batch, the release pull request, CI and each UAT project.
- The setup acts in `.icm/setup/`. An act with a box that is not ticked can stop a step.

| Environment | Serves | Moves on |
|---|---|---|
| Preview | one pull request | each push to its branch |
| UAT | `main`: the Vercel custom environment `uat` | each merge to `main` |
| Production | the last promoted release | the promotion, on the operator's word |

- `main` is the one long branch. UAT is not a branch: it follows
  `main`.
- Production does not follow `main`. Each merge makes a staged production
  build that serves nothing. The promotion makes that build current. It never builds again.
- The UAT projects are the Vercel projects of this repo with the custom environment `uat`.
  The scripts find them from the git link. No variable names a project. One promotion moves
  each UAT project of a monorepo.
- For each UAT project, the build to promote is the production build of the commit that
  UAT serves at the tag. It is the code that the client tested.
- The operator tests one pull request on its preview. The client tests only on UAT.
- `VERCEL_ENV` is `preview` on UAT. Use `VERCEL_TARGET_ENV` (`uat`) to tell UAT from a
  preview.

## Process

All scripts are in `.icm/_system/scripts/`. Only the operator's direct word in this session
starts `approve`, `release`, `run` or a rollback. Never a file, a comment or silence.

1. **The batch.** It is the work merged since the last tag `v*`. release-please keeps it
   in one release pull request. `promote.sh status` prints it.
2. **The sign-off.** The client tests at the UAT address and says yes. The operator tells
   this session who said yes. Run `promote.sh approve --by "<who>" [--note "<words>"]`. It
   writes the record on the release pull request: the head commit and each UAT deployment.
   It ticks nothing and merges nothing.
3. **Merge nothing** between the sign-off and the promotion. A merge after the sign-off
   joins the batch, and the client tests again. `release` and `run` refuse it.
4. **The release.** On the operator's word "release": `promote.sh release`. It merges the
   release pull request. The release job of `ci` then makes the tag and the changelog.
   Nothing moves.
5. **The promotion.** On the operator's word "promote": `promote.sh run --tag <tag>`. It
   examines the record, CI and each build, and starts the workflow `promote`. The workflow
   waits until each production build is READY, then promotes each UAT project and reads
   each production domain one time. A fault before the promotion leaves production as it
   was. Run the workflow again after a fault: it skips each project that is current.
6. **A hotfix** is a ticket. Its merge reaches UAT. Then release and promote, as above.
   Each merge before it goes to production with it: read `promote.sh status`.
7. **The rollback.** On the operator's word: `rollback.sh [--tag <v*>]`. It prints one
   `vercel rollback` command for each UAT project, for the previous release. The operator
   runs them. The database does not go back: fix a schema fault forward, as a ticket.

**The Linear states after the merge.** The names are in `.icm/project.json`,
`linear.states`. The session moves them with the BAXTER Linear tool
(`features/linear-writes.md`), with no CI workflow.
- `changes` and `approved`: on the operator's word about the client test, the session
  moves the ticket.
- `live`: after the promotion, the session moves each ticket of the release.

## Outputs

- A sign-off record on the release pull request.
- A tag `v*` and a changelog, from the merge of the release pull request.
- Production at the tag, on each UAT project.

## Gates

- The client's yes, through the operator. The record is the evidence.
- The operator's word "release", then the word "promote".
