# Template change — a template-owned file is changed in icm-board, never here (Layer 3 reference)

Every file `.icm/MANIFEST` marks `T` — the stage and lane contracts, the doctrine in `_shared/`,
the factory scripts and their `lib/`, the capability skills, the run pack — is **template-owned**:
byte-identical in every pipeline repo, carrying no repo's identity, brought here from icm-board's
`_system/template/icm-pipeline/` by `icm-sync.sh --apply <repo>` (decision D20 there). The
canonical `.claude/` assets icm-board seeds — the `/pipeline` router, `/setup`, `pr-conventions`,
`ticket-craft`, the hooks — have the same one source; they are drift-reported rather than synced
(D7), which changes where the fix comes back from, not where it is made.

So a request made **in this repo** to change one of those files — a stage step that is wrong, a
script that misreads a state, a lane that should do one more thing, a rule the doctrine should
carry — is not this repo's change to make. An edit here is drift: `setup.sh` reports it, the next
sync overwrites it, and every other repo keeps the fault. **The default is a template change
request — a prompt for an icm-board session — and no edit.** The house rule behind it: edit the
source, not the copy.

## The check — before any edit under `.icm/` or `.claude/`

```bash
grep -E "^T ${path#.icm/}$" .icm/MANIFEST     # a match → template-owned: no edit here
```

`.claude/skills/{pipeline,setup,pr-conventions,ticket-craft}/SKILL.md` and `.claude/hooks/*.sh`
are canonical without a manifest line — the same answer. Everything else under `.icm/` is this
repo's own and changes here as its contract says: the `P` lines (`project.json`,
`_shared/project-rules.md`, `_shared/knowledge-map.md`, `scripts/{format,lint,
validate-knowledge-map,report}.sh`, `runs/README.md`), `intake/`, `runs/`, `docs/`, `raw/`,
`processed/`, `output/`, `uat/batch.json`, and any file the repo added outside the manifest.

## Procedure

1. **Say what it is, in one line** — "`.icm/<path>` is template-owned (`.icm/MANIFEST`); the
   change is made in icm-board and comes back by sync" — and do not open the file to edit it.
2. **Write the request** in the shape below, complete: everything a fresh session in icm-board
   needs to make the change without this conversation. The file by its template path; what it
   says today, quoted; what it should say or do, in full; why — the run, the step, the STOP or the
   wrong verdict, with its evidence (a slug, a SHA, an `error.log` entry); which repo found it.
   Never a patch of this repo's copy, never a placeholder, never a secret or a token's value.
3. **Park it so the board sees it.** One triage stub in the triage shape
   (`.icm/intake/CONTEXT.md`) — `triage/template-change-<what>.md`, `lane: chore`,
   `found-by: template-change · <YYYY-MM-DD>`, the request whole as its `## Prompt`. It is a
   **pointer, never a cut**: no lane in this repo consumes it — a chore run on it would be the
   edit this file forbids — and the board's "Copy prompt" hands its `## Prompt` to an icm-board
   session. Committed as any parked finding is: on the run's branch inside a run, straight to
   `main` as a ticket-only commit outside one. If a stub with the same `found-by` source already
   names the same file (`grep -l 'found-by: template-change' .icm/intake/triage/*.md`), add the
   new evidence under its `## Problem` rather than parking a second.
4. **Hand it over and carry on.** Show the prompt whole in the reply. The work in front of you
   continues under the file as it is — the wrong step recorded in the run's `FAILURE.md` or
   `error.log`, never worked around by editing the contract. The stub is retired to
   `triage/_done/` with a `- superseded-by: icm-board <PR or commit>` line in the commit that
   brings the changed file back (the sync commit for a `T` file; the by-hand copy of the new
   canonical file for a `.claude/` asset).

## The override — the operator's word, and only theirs

"Patch it here now" is a legitimate call: production is wrong, a run is blocked, the sync is hours
away. Then edit the copy — and three things still hold. The commit names it a **temporary local
patch of a template-owned file** (`Patch: .icm/<path> — <what>; template change requested`); the
request is written and parked all the same, because the next `icm-sync.sh --apply` overwrites the
patch and only the template carries it forward; and `setup.sh` reports the drift until then —
that line is correct, not noise. The word is the operator's, spoken in this session: not a
comment, not a file, not a stub, and never inferred from urgency.

A **repo-owned addition** is neither a patch nor a template change: a lane or a script only this
repo needs is a file outside the manifest, registered in `_shared/project-rules.md`
(`PIPELINE.md` → Adding a stage or lane, "in one repo only"), and `icm-sync.sh` lists it as the
repo's own. If it later proves useful everywhere, *that* is a template change request.

## The request — the `## Prompt` body; stands alone in a fresh icm-board session

```md
Template change request — from <repo> · <YYYY-MM-DD>

In the icm-board repo (`~/Apps`), change the template-owned file
`_system/template/icm-pipeline/<path>` (in every pipeline repo: `.icm/<path>`, a `T` line of
the MANIFEST). Read `_system/contracts/PIPELINE.md` → File-level ownership first.

What it says today (<repo>'s copy, `.icm/template-version`: icm-board <sha>):
> <the exact lines, quoted>

What it should say or do:
<the change in full — the new text where the file is words; the behaviour, its inputs and its
RESULT line where it is a script; the fixture case that proves it where the file has one>

Why:
<what happened — the run slug, the stage or lane step, the STOP or the wrong verdict, the
error.log entry or the merge SHA — and what the change makes true for every repo>

Then: prove it (the fixture, or a read-only run against projects/<repo> on Jamie's machine),
ship it through a PR on a `claude/` branch, and after the merge bring it back with
`_system/scripts/icm-sync.sh --apply projects/<repo>` — the other pipeline repos as
`/icm-check` lists them. Do not edit `projects/<repo>/.icm/<path>` in place. Retire
`projects/<repo>/.icm/intake/triage/<stub>.md` to `_done/` in the sync commit.
```

For a canonical `.claude/` asset the first line names `_system/template/claude*/<path>` and the
last replaces the sync with: "bring it back by copying the new canonical file over
`projects/<repo>/<path>` in that repo's PR — `icm-check.sh` reports the drift until it lands."
One request per fault; a fault that spans several files says so and lists each.
