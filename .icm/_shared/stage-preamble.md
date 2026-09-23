# Stage preamble — resolve the run, or STOP (Layer 3 reference)

The single canonical procedure for **adopting** an existing run into the working tree. `revise`,
Build and Release run it before anything else. **The front never runs it** — Scope creates the
run folder and Define creates the branch + PR — and **the lanes never run it**: a lane is one
invocation that ends in a PR the operator merges from GitHub, so there is no lane run to resume.
The guard below applies only to the adopting stages.

## Procedure

1. **Resolve the run with one blocking call** — don't read `run.md`, search for the PR, or check out a
   branch by hand. `resolve-run.sh` does all of that deterministically (read `run.md` if it's already
   in the tree or the archive; otherwise find the PR by slug in the repository's own pulls listing —
   the slug line in an open PR's body first, then an open PR whose head branch is `claude/<slug>`
   or ends in `-<slug>`, then the recently closed PRs; never the search API — then fetch + check
   out the run's branch, logging which route resolved it) and spends no model
   tokens doing it:

   ```bash
   .icm/scripts/resolve-run.sh <slug>
   ```

   - Exit 0 / `RESULT: READY` → the run's branch is checked out and `.icm/runs/<slug>/run.md` is
     in the working tree. Go to step 2.
   - Non-zero / `RESULT: STOP` → no run resolved: Define has not run for this slug (or the slug is
     wrong). **STOP.** Do **not** create `runs/<slug>/`, a spec, a `run.md`, or a branch, and do not
     fall back to `git checkout -b`. Recreating the folder fabricates an unspecced run and orphans the
     real one. Tell the user to run `new` (the next intake stub, or `new <stub-name>`) — or to fix
     the slug — and stop. (The script itself never creates anything — it only reports `STOP`.)

2. **Read where the last session stopped** — `.icm/runs/<slug>/status.md` (five lines: phase,
   step, ci, blocked, updated), then `handoff.md` (next steps, blockers, do-nots). These are two
   of the seven canonical files every run carries (`.icm/scripts/run-pack.sh` — `project.md`,
   `plan.md`, `tasks.md`, `decisions.md`, `status.md`, `handoff.md`, `FAILURE.md`); a run
   missing them is seeded with `run-pack.sh <slug> --init`, never written from memory. A
   `blocked: yes` is a STOP until the named blocker is cleared.

3. Load the stage contract (`.icm/stages/NN_*/CONTEXT.md`) and follow it. Every stage leaves
   `status.md` and `handoff.md` true at its stop — the next session's first read.

## Run-scoped isolation — the rule every stage and lane holds

Several runs are in flight at once — different sessions, different machines, sometimes the same
afternoon. What keeps them from writing over each other is not a lock and not a scheduler; it is
that **a run only ever writes inside its own folder, on its own branch.** This is mandatory for
every stage and every lane, including the two that never run the procedure above:

1. **Working artifacts land in the run's own stage folder, and nowhere else.** Scope writes under
   `.icm/runs/<slug>/01_scope/`, Define under `.icm/runs/<slug>/02_define/`, Build under
   `.icm/runs/<slug>/03_build/` (Release appends its `## Release` record to Build's `notes.md` —
   it has no folder of its own), a lane under `.icm/runs/<slug>/lane/`. `<slug>` is the stub's
   slug: the stub, the run folder, the branch and the PR share the one name. A note, a draft, a
   scratch list, an intermediate result — if a stage produced it while working, it goes there.
   Never a shared file in `.icm/`, never the repo root, never another run's folder.
2. **One run, one branch, one PR.** A spine or lane run is bound to `claude/<slug>` — created by
   `new-run.sh` and by nothing else, which also accepts the branch a harness has already named
   for the session and records it in `run.md` (`_shared/github.md`). A stage never commits a
   run's work to another run's branch, and never to `main`.
3. **One working tree per run.** Two runs are never worked in the same checkout at the same time:
   a second run in flight gets its own clone, worktree or cloud session, on its own branch.
   Switching one checkout back and forth between two live runs is how a run's uncommitted
   artifacts end up in the other's commit.
4. **The front is the one writer on `main`, and it is still run-scoped.** Scope has no branch and
   no PR; it pushes to `main` exactly two folders that carry its slug —
   `.icm/runs/<slug>/01_scope/` (with `run.md`) and `.icm/intake/<slug>/` — and touches nothing
   else, so two fronts cannot collide unless they chose the same slug — which is why a slug
   whose `.icm/runs/<slug>/` or `.icm/intake/<slug>/` already exists, live or archived, is not
   free to pick.
5. **What a run may write outside its folder is what its contract names**, and only that: the
   code and docs the spec covers, the stub it consumes (`new-run.sh --stub`), a triage stub it
   parks (its own new file), the changelog page, the archive move (`close-out.sh`) and, in that
   same close-out commit, the learned rules it appends to `_shared/project-rules.md`
   (`run-pack.sh --sync-rules` — append-only, so two runs closing out never rewrite each
   other's lines). Each is a file this run alone creates, moves or appends to — never an edit to
   a line another live run is writing.
6. **No run edits the pipeline it runs in.** A file `.icm/MANIFEST` marks `T` — this preamble, a
   stage or lane contract, a `_shared/` doctrine file, a factory script, a capability skill — and
   the canonical `.claude/` assets are icm-board's: a change one is owed is a **template change
   request** (`_shared/template-change.md` — a prompt for icm-board, parked as a
   `found-by: template-change` triage stub), never an edit here. The run continues under the file
   as it is and records the fault in its `FAILURE.md` or `error.log`; only the operator's spoken
   "patch it here now" overrides, and the request is written even then.

A conflict inside `.icm/runs/<slug>/` when `main` is merged in therefore means someone broke this
rule, not that two runs legitimately met: **STOP** and ask, never pick a side
(`stages/04_release/CONTEXT.md` step 7).

The resolver reads a GitHub token (`GITHUB_TOKEN` or `GH_TOKEN`) from the environment for the PR
lookup — and, optionally, `GITHUB_REPO` / `GITHUB_API_URL`. Its header documents the full signature,
the lookup order and the verdict vocabulary.
