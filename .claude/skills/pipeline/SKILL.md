---
name: pipeline
description: >-
  The delivery pipeline (ICM). Use for /pipeline AND for the bare forms
  the operator types without a slash — "new" (next intake stub), "new <stub-name>",
  "build <slug>", "release <slug>", "revise <slug> \"<what to change>\"",
  "bug|tweak|chore <stub-or-slug>", "hotfix \"<what is wrong in production>\"",
  "handover", "scope <anything>",
  "triage report|batch|prune", "knowledge add|edit|remove \"<what>\"", "status",
  "promote status|approve \"<who>\"|init" — and whenever the
  [pipeline-router] hook injected a Route: line. Also use it to scope, define, revise, build or
  release work, to fix a bug, to report on, batch or prune the triage backlog, to change a
  project-knowledge page in the docs tree outside a Release, to recover production after a bad
  merge, to hand a finished build over, to compile the client's status report, or to read
  the UAT batch and record the client's sign-off as a draft Release. Subcommands: scope, new,
  revise, build, release, bug, tweak, chore, hotfix, handover, triage, knowledge, status, promote.
---

# /pipeline — the delivery pipeline router

The single entry point for the delivery pipeline. It does **not** contain the work — each stage or
lane contract lives under `.icm/stages/` / `.icm/lanes/`. Parse the subcommand, load the
right contract, follow it. This keeps the skills list to one pipeline entry no matter how many
stages exist.

Argument form: `<subcommand> [slug, stub name, or "request"]`. The argument is: `$ARGUMENTS`

**Natural-language routing — the operator never has to type `/pipeline`.** The bare forms
`new`, `new <stub-name>`, `build <slug>`, `release <slug>`, `revise <slug> "<what to change>"`,
`bug|tweak|chore <stub-name or "report">`, `hotfix "<incident>"`, `handover`, `scope <anything>`,
`triage report|batch <area|lane> "<epic-title>"|prune`, `knowledge add|edit|remove "<what>"`,
`status` and `promote status|approve "<who>"|init`
are this skill's subcommands without the slash; treat them exactly as
`/pipeline <the same words>`. `/pipeline <sub>` stays the explicit
override.

**Router hint:** a deterministic `UserPromptSubmit` router hook, where the repo ships one, may have
injected one `[pipeline-router]` line:

- `[pipeline-router] Route: /pipeline <sub> [<slug>] (<why>)` — **authoritative**. It is emitted
  only from facts it checked (a bare stage verb plus a slug that resolves to `.icm/runs/<slug>/`,
  the archive, or an intake stub; bare `new`; `scope <input>`; `triage` with one of its three
  verbs; `knowledge` with one of its three verbs and a request; or work-shaped new content that
  names nothing in `.icm/runs/` or `.icm/intake/`). Run that command — unless the user's own
  prompt overrides it (a different subcommand named, or "don't route this"); their word wins.
- `[pipeline-router] Suggest: …` — **advisory**. The bug / tweak / chore classifiers are
  heuristics: announce the suggested lane in one line, let the user override, and proceed.

A plain request that names no stub and no run is **new content → `scope`**; nothing new enters
the pipeline anywhere else.

## Routing table

| Subcommand                                | Contract to read & follow                |
| ----------------------------------------- | ---------------------------------------- |
| `scope <input>` (story, URL, doc, prompt) | `.icm/stages/01_scope/CONTEXT.md`        |
| `new` / `new <stub-name>` (see below)     | `.icm/stages/02_define/CONTEXT.md`       |
| `revise <slug> "<what to change>"` (see below) | `.icm/stages/02_define/CONTEXT.md` step 6 |
| `build <slug>`                            | `.icm/stages/03_build/CONTEXT.md`        |
| `release <slug>`                          | `.icm/stages/04_release/CONTEXT.md`      |
| `bug "<report>"` / `bug <stub-or-slug>`   | `.icm/lanes/bug/CONTEXT.md`              |
| `tweak "<change>"` / `tweak <stub-or-slug>` | `.icm/lanes/tweak/CONTEXT.md`          |
| `chore "<task>"` / `chore <stub-or-slug>` | `.icm/lanes/chore/CONTEXT.md`            |
| `hotfix "<what is wrong in production>"` (human-invoked, opens ready) | `.icm/lanes/hotfix/CONTEXT.md` |
| `handover` (the deal's last lane; needs the deal folder on disk to record) | `.icm/lanes/handover/CONTEXT.md` |
| `triage report` / `triage batch <area\|lane> "<epic-title>"` / `triage prune` (see below) | `.icm/intake/CONTEXT.md` → Managing the backlog |
| `knowledge add\|edit\|remove "<what>"` (see below) | `.icm/lanes/knowledge/CONTEXT.md`        |
| `status` (see below)                      | `.icm/scripts/client-status.sh` — the client's report |
| `promote status` / `promote approve "<who>"` / `promote init` (see below; UAT repos only) | `.icm/_shared/promotion.md` |
| _(empty / unclear)_                       | read `.icm/CONTEXT.md`, show the help    |

Stages are discovered by folder order: `ls .icm/stages/` → `NN_<name>/CONTEXT.md`; a subcommand
maps to the `<name>` part. Lanes likewise under `.icm/lanes/`. Scope has no substage: it records
the source, settles the scope in session and cuts the intake batch in one sitting. `status` and
`promote` are script verbs, not stages — a promotion is a published Release, not a lane or a PR.

## How to run a stage or lane

1. Read `.icm/CONTEXT.md` once this session if you haven't — the workspace map (Layer 1) — and
   `.icm/_shared/output.md`, the output doctrine for the **chat** every stage and lane holds: a
   short line per phase change or notable event (`CI red on lint — fixing`), no narration of tool
   calls or pasted file contents; **at every stop, the one report shape** its stop step names.
   It never shortens a file — the PR body, the spec and the records stay as full as their
   contracts ask, and every gate checkbox stays in the PR body.
2. Resolve the `<slug>` (kebab-case). Scope picks new slugs; every stub's `feature-slug` was
   fixed at the cut, so `new` never invents one. Scope takes no slug — a scope that came out
   wrong is deleted and Scope is run again from the source.
3. For the **adopting** stages — `revise`, `build`, `release` — run the shared preamble first:
   `.icm/_shared/stage-preamble.md` ("resolve the run or STOP", then read the run's `status.md`
   and `handoff.md` — the canonical file pack every run carries). Never recreate a missing run.
   Lanes never run it: a lane is one invocation that ends in a mergeable PR and is not resumed
   (see "Resolving a lane argument" below).
   **The pass and its model, in one line:** `.icm/scripts/select-model.sh <stub-or-spec>
   --stage <NN_stage|lane>` prints the tier the pass belongs to — Scope and Define are the
   *advisor* (frontier: `opus`, `fable` on research), Build, Release and every lane the
   *executor* (`sonnet`, `opus` only on a `complex` spec), a lint or format fix the *validator*
   (`haiku`). If this session is on a lower tier than it prints, say so once and carry on — the
   operator opens sessions, nothing here switches a model. A subagent a stage dispatches runs
   on the executor line.
   **Capability skills** (`.icm/skills/`, `list-skills.sh --bare` — the session-start hook
   already printed the registry) are loaded only when a trigger on one of their lines matches
   the step in front of you; the contract says where (`security-audit`, `database-migration`,
   `preview-deploy`).
4. **Read the matching contract in full and follow it exactly** — Inputs / Process / Outputs /
   Verify are the instructions. Load only the files its Inputs section names.
   **CI is read one way everywhere:** `.icm/scripts/ci-status.sh <slug>` → `GREEN | RED | PENDING`
   (`.icm/_shared/ci.md`). No stage hands off or merges on anything but a settled `GREEN`, and
   the script names the tier it settled: a draft owes CI nothing and builds **no previews**
   (blind-until-ready — the session's `format.sh` / `lint.sh` are the pre-flip check); Build
   flips ready **then pushes**, and the advisory quality job plus the affected product-app
   previews settle on that head.
   **Pipeline PRs are never subscribed to PR activity** (`.icm/_shared/github.md` → PR events) —
   the one blocking script call is the only CI read, so no Vercel event churn ever reaches the
   session.
5. **Respect gates — never auto-advance.** The three hard gates: the scope reviewed (Scope lands
   `scope.md` and the intake batch on `main` in one direct commit, and stops; the human reads them there and runs `new` when happy), **Spec approved** (PR checkbox, the operator ticks), **Ready to merge** (PR
   checkbox, the operator ticks — it attests their own smoke-testing of the preview, which is why
   Release re-asks for none of it). The business's involvement ends when the scope is settled at
   Scope. You only ever **read** the checkboxes (`.icm/_shared/github.md`) — never tick one, and
   never start the next stage on your own. Lane PRs carry no checkboxes: their gate is the merge
   button, which the operator presses in the GitHub UI after their smoke.
   After each stage or lane, report per `.icm/_shared/output.md` — the next `/pipeline <verb>`,
   when the human is ready, is an item on its `Operator:` list.
6. **A run ends at the merge, and the merge is what closes it out.** Release (and every lane)
   runs `retrospective.sh` — what the run fixed on the way, promoted into
   `_shared/project-rules.md` → Learned rules for the next run — and then `close-out.sh` on the
   branch as its last commit — the archive move rides in the run's own PR, so the squash
   publishes it. Release then merges, reads production once (`deploy-status.sh` for the
   platform's word, then `health-check.sh` for the application's — one bounded read each) and
   announces through the repo's reporting hook (`report.sh announce`, or `deferred to CI` —
   `_shared/project-rules.md` → Reporting); a lane **stops** after its last push and hands the
   PR to the operator to merge from GitHub. Nothing watches production afterwards: a fault is
   `report.sh alert` (a red CI job where no channel is mapped — `health-check.sh` makes that
   call itself when its read fails, and parks one bug-lane stub it never commits), and the
   recovery is the human-invoked `hotfix` lane, prepared by `rollback.sh`.
7. **Every stage and lane brackets itself with two usage lines** —
   `usage-snapshot.sh <slug> <stage> start` as the first act after the preamble and `… end` just
   before `close-out.sh` where the stage has one (Release, every lane — the archive commit carries
   the line; nothing written after the close-out reaches the PR), else as the last act before the
   stop. `SKIP` is a fine answer; the line is never a gate.
8. **Every stage leaves the run resumable.** `status.md` (phase · step · ci · blocked · updated)
   and `handoff.md` (next steps, blockers, do-nots) are rewritten at every stop, including a
   STOP mid-way; a RED or a blocked gate is an `error.log` entry (`retrospective.sh` reads it),
   and what no tool logged — a wrong assumption, a STOP — is a retrospective in `FAILURE.md`.
   `security-check.sh` runs before every commit in Build and before every lane push — a
   `BLOCKED` is never committed around.
9. **The pipeline itself is not edited from here.** A request that would change a file
   `.icm/MANIFEST` marks `T` — a stage or lane contract, a `_shared/` doctrine file, a factory
   script, a capability skill — or a canonical `.claude/` asset (this router, `/setup`,
   `pr-conventions`, `ticket-craft`, the hooks) is a **template change request**, not a lane
   and not an edit: `.icm/_shared/template-change.md`. Say the file is template-owned, write the
   prompt for icm-board in that file's shape, park it as one `found-by: template-change` triage
   stub (its `## Prompt` is the request; no lane here consumes it), show it whole, and carry on
   under the file as it is. Only the operator's explicit "patch it here now" overrides, and the
   request is written even then. The `P` lines (`project.json`, `_shared/project-rules.md`,
   `_shared/knowledge-map.md`, the local feedback scripts, `report.sh`, `runs/README.md`) and
   everything outside the manifest are this repo's own and change through the lanes as usual.

## Resolving `new` (one procedure, two selectors)

`new` takes a stub, never a request — every new piece of work enters through Scope, which cuts
the stubs. `new`'s argument decides how the stub is found; the candidate set is always the same:

**Candidate set = active scope stubs.** Glob `.icm/intake/*/*.md`, excluding every
`breakdown.md`, anything under `_done/`, and the whole `triage/` folder (triage stubs are lane
work — the lanes consume them, `new` never does):
`ls .icm/intake/*/*.md | grep -v '/breakdown.md$' | grep -v '/_done/' | grep -v '/triage/'`

- **`new <stub-name>`** (single token) — the user names a stub from memory:
  1. Exact filename match `<stub-name>.md` in the candidate set → use it.
  2. Else substring match: exactly one → use it and say which; several → `AskUserQuestion`
     (label = feature slug, description = scope folder). Never guess.
  3. No match → do **not** treat it as a fresh request; list the active stubs grouped by scope
     and ask. (If the name matches a `triage/` stub instead, say so and point at the matching
     `/pipeline bug|tweak|chore <name>`.)
- **anything with spaces or quotes** is not a `new` form — it is a request, and a request with
  no stub behind it goes to `scope`. Say so and route it there; do not hand it to Define.
- **`new`** (no argument) — walk the active batch in order:
  1. Group candidates by scope folder. One active scope → that's the batch; several →
     `AskUserQuestion` (label = scope-slug, description = "N stubs left"); none → say intake is
     empty and suggest `/pipeline scope "<topic>"`. Stop.
  2. Pick the lowest `sequence: n of m` (fallback: `## Build order` position, then filename).
     Dependency check — `_done/` means **spun out, not shipped**: if the pick's `depends-on`
     names a stub not yet in `_done/`, warn the batch is out of order. If the dependency _is_ in
     `_done/`, confirm its PR actually **merged** (`runs/<dep-slug>/run.md` → `pull_request_read`)
     before offering the pick — a dependent branched off `main` won't build until the dependency's
     code is on `main`. Unmerged → say so and recommend waiting; the user may still override.
  3. **Announce the pick and stop for confirmation** — opening a run + draft PR is a real side
     effect. On confirmation, hand the path to Define.

Either way, Define pre-seeds the spec from the stub and `new-run.sh --stub` marks it `_done/`.

## Resolving `revise` (one command changes a spec and its PR)

`revise <slug> "<what to change>"` is the only way an existing spec changes — the old `define`
verb is gone. The change may also be described in conversation (`revise <slug>` alone, then the
change in the next message, or `/pipeline revise <slug>` with it already discussed). The stage
preamble resolves the run (`resolve-run.sh <slug>` — a slug with no run or PR STOPs; a spec that
has no PR yet is `new`, not `revise`), then Define's step 6 applies the change to `spec.md` with
Define's own requirement-gathering discipline (ask when the change is ambiguous), validates, and
re-projects the PR body and labels from the file with `project-body.sh <slug> --apply` and
`project-labels.sh <slug> --stage define`. Never `new-run.sh` — one PR per run. If the **Spec
approved** box was ticked, say so plainly: the projection unticks it, the revision re-opens the
gate, and the operator must re-tick.

## Resolving a lane argument (a triage stub name, or a fresh report — never a resume)

A lane is **one invocation** that ends in a PR the operator merges from GitHub; there is no lane
run to pick back up, so `bug|tweak|chore <arg>` is never a resume-by-slug and never runs the stage
preamble. The argument is one of two things:

- **A single bare token** is a triage stub name: check `.icm/intake/triage/*.md` (excluding
  `_done/`) — exact filename `<token>.md`, then substring; exactly one → use it and say which;
  several → `AskUserQuestion`, never guess. The lane contract says how a stub pre-seeds the lane.
- **Anything with spaces or quotes** is a fresh report/request — hand it to the lane as is.
- **A bare token that matches no triage stub** → say so and ask whether it is a fresh report to
  run as `<lane> "<report>"`, or a mistyped stub name (list the `triage/` backlog with each
  stub's lane). If the token names a run in `.icm/runs/` or the archive, say that too: a lane PR
  that is open is the operator's to merge (smoke, then squash-merge from GitHub); an archived one
  has shipped. Do not re-open, re-run or "finish" it.
- **A request whose subject is a template-owned file** — a `T` line of `.icm/MANIFEST`, or a
  canonical `.claude/` asset — is not lane work (step 9 above): no run, no PR. Write the template
  change request (`.icm/_shared/template-change.md`), park it, and stop.

## Resolving `triage` (the backlog's three verbs — a read, a cut, a list; never a run)

`triage` manages `.icm/intake/triage/`, the parking lane every stage drops off-ticket findings
into. It opens no run and no PR; its contract is `.icm/intake/CONTEXT.md` → Managing the
backlog, which owns the cap (60 active stubs) and each verb's rules. The first word after
`triage` is the verb; anything else → show the three forms and stop.

- **`triage report`** — run `.icm/scripts/triage-report.sh` (not a repo check; the hook allows
  it) and show its output whole: the totals against the cap, the counts by lane / source / area
  / age, the near-duplicate list, `RESULT: OK — …` last. Suggest `triage batch <area|lane>
  "<epic-title>"` for the biggest area or lane when the folder is over its cap. Nothing is
  written.
- **`triage batch <area|lane> "<epic-title>"`** — the selector is one token (an area exactly as
  the report names it — `apps/<app>`, `packages/<pkg>`, `.icm`, `.github` — or `bug` / `tweak` /
  `chore`), the title is quoted. Run the report first, read every matching active stub, retire
  the duplicates into `_done/` with `superseded-by:` lines, cut the survivors into
  `.icm/intake/<epic-slug>/` (breakdown + sequenced feature stubs in the intake **Formats**), move
  the originals to `_done/` with `superseded-by:` lines, run `validate-intake.sh <epic-slug>` →
  `RESULT: OK`, commit on the current branch, and **stop**: the epic is the human's review
  surface, and `new` walks it when they are happy. A missing selector or title → ask; a selector
  the report does not list → say so and show the report's areas.
- **`triage prune`** — list the deletion candidates (older than 30 days, or superseded — the
  rules are in the intake contract) with the reason and the `git rm` for each, then **stop and
  ask**. Delete only what the human confirms, name by name, in one commit. Never delete on your
  own, never delete a stub the human did not name, never "tidy" while you are there.

## Resolving `knowledge` (one page in the docs tree changes, on its own docs-only PR — never a run)

`knowledge add|edit|remove "<what>"` is the **one sanctioned way to change project knowledge
outside a Release** — the pages under the docs tree (`docs_path` in `.icm/project.json`) that
every stage reads through `.icm/_shared/knowledge-map.md`. The first word after `knowledge` is the
verb (`add` a page that does not exist, `edit` one that does, `remove` one that should not); the
rest is the request — which page, what changes. Bare `knowledge`, or an unknown verb → show the
three forms and stop. The contract (`.icm/lanes/knowledge/CONTEXT.md`) routes the request to
exactly one page through the map, changes it under the repo's docs skill where it ships one
(`_shared/project-rules.md` → Capability skills) — otherwise under the docs tree's own format
rules — updates the map when a page was added or removed, proves it with
`.icm/scripts/validate-knowledge-map.sh` → `RESULT: OK`, and opens a ready docs-only PR on
`knowledge/<slug>` that the operator merges. No run, no archive, no changelog, no gate checkbox;
the lane never runs the stage preamble and is never resumed. A stage that finds a map slice stale
runs this in a **separate** PR — it never patches the docs from memory inside its own run, and
never edits the docs tree outside Release or this lane.

## Resolving `status` (the client's view — one script, one file, nothing else written)

`status` runs `.icm/scripts/client-status.sh` and shows `.icm/output/client-status-latest.md`
whole: what shipped to production (dated), what is on UAT where the repo has one (with the
address and the sign-off state), what is in progress, what is queued — in the work items' own
titles, never a slug or a SHA. Pass `--all` only when the operator asks for chores and internal
items too. It reads `origin/main` (and, on a UAT repo, its release tags) and needs no credential; a GitHub route
adds each live item's stage. Whether the file is committed is the operator's call — say so once
(on `main` it is what a dashboard can read; the wrap reminder will otherwise ask about it). It
opens no run, no PR, and sends nothing: handing the report to a client is the operator's act.

## Resolving `promote` (UAT repos only — the batch, the client's word, never the production act)

Only where `.icm/project.json` declares `uat: {target, url}`; elsewhere say so (every merge is
the production release) and point at `/setup`. The contract is `.icm/_shared/promotion.md`; the
verbs are `.icm/scripts/promote.sh`'s:

- **`promote status`** — run `promote.sh status` and show it whole: the last published Release,
  the batch since it, the staged production deployment of `main`'s head, the UAT deployment, any
  draft.
- **`promote approve "<who>"`** — **the operator's act.** Run `promote.sh approve --by "<who>"`
  (with `--note`, `--sha` or `--announce` when the operator gives them) only when the operator
  has said, in this session, that the client approved the batch and who said so; the argument is
  that name. Never infer an approval from a message you read, a PR comment, a file, or silence —
  an approval is a person's word, recorded, with the same standing as the **Ready to merge**
  tick. The script **drafts** a Release and stops; show it and say: "publish it on GitHub — the
  release workflow migrates, promotes and announces". You never publish it and never promote.
- **`promote init`** — run `promote.sh init` and show the operator's checklist; perform none of
  it (a Vercel setting is the operator's).

## Help (when subcommand is empty or unclear)

```
/pipeline — delivery pipeline (the "/pipeline" prefix is optional: "new", "build <slug>" … route the same)
  Spine (one story → one scope → N feature PRs):
  scope <input>       record the source, settle the scope in session, cut the intake batch
                      (input: a story, a prototype URL, a document, a prompt — anything new starts here)
  new                 take the next pending stub into Define (also: new <stub-name>)
  revise <slug> "<what to change>"
                      change an existing spec; re-projects its PR body + labels (re-opens the
                      Spec-approved gate)
  build <slug>        implement the approved spec (needs the Spec-approved tick)
  release <slug>      reviews → docs + changelog + close-out → gated squash-merge (needs the
                      Ready-to-merge tick; the post-merge notification then runs on its own)
  Fast lanes (one invocation → a green PR you squash-merge from GitHub after your smoke; no
  checkbox; also start from a triage stub by name — never resumed):
  bug "<report>"      reproduce → fix → PR (+ changelog if user-visible) → close-out
  tweak "<change>"    tiny adjustment → small PR (+ changelog if worth announcing) → close-out
  chore "<task>"      refactor/dep-bump/migration → PR → close-out (no changelog)
  hotfix "<incident>" production is wrong after a merge → fix-forward, or a revert / Vercel
                      rollback prepared by rollback.sh → PR opened READY → close-out (human-invoked)
  handover            the build is finished: accounts, env.sh doc, setup.sh OK, support line,
                      the record into the deal folder (the deal's last lane)
  Backlog (.icm/intake/triage/ — the parking lane; cap 60 active stubs; no run, no PR):
  triage report       counts by lane / source / area / age + near-duplicates (triage-report.sh)
  triage batch <area|lane> "<epic-title>"
                      dedupe the matching stubs and cut them into an intake epic for `new`
  triage prune        list stubs older than 30 days or superseded — you confirm each deletion
  Knowledge (the docs tree — the pages the stages read through the map; no run, one docs-only PR):
  knowledge add|edit|remove "<what>"
                      route to the page via .icm/_shared/knowledge-map.md, change it under
                      the docs tree's format rules, update the map, open a docs-only PR you merge
  Status (every repo — the client's view, compiled from the pipeline's own files):
  status              client-status.sh → .icm/output/client-status-latest.md, shown whole
  Promotion (only where .icm/project.json declares uat — the client's UAT environment):
  promote status      the batch since the last published Release, staged vs current, any draft
  promote approve "<who>"
                      the operator records the client's sign-off → a DRAFT Release (the operator
                      publishes it on GitHub; the release workflow promotes — you never do)
  promote init        the operator's one-time checklist (Vercel, database, workflows, secrets)
  The pipeline itself (a T line of .icm/MANIFEST, or a canonical .claude/ asset — never edited here):
  a request to change one → a template change request for icm-board: .icm/_shared/template-change.md
                      (the prompt, parked as a found-by: template-change triage stub; the sync brings it back)
```

When listing what's available (helping pick a stub, or no batch active), show the active intake
stubs grouped by scope folder — the candidate-set glob above — marking each scope's next stub
(lowest `sequence`), and the `triage/` backlog separately with each stub's lane.

## Adding a stage, substage or lane later

Add a numbered folder `.icm/stages/NN_<name>/CONTEXT.md` (or `.icm/lanes/<name>/`) and a
row to the routing table above. A **substage** — a step that belongs to a stage, carries no gate of
its own, and would otherwise force a renumber — nests instead:
`.icm/stages/NN_<parent>/<name>/CONTEXT.md`, plus its own routing row (none exists today). No new
skill is created — the pipeline grows in the folder tree, not the skills list. For every repo the
change is made in icm-board's template and synced (`PIPELINE.md` → Adding a stage or lane); asked
for in this repo, it is a template change request (`.icm/_shared/template-change.md`). Only a stage
or lane this repo alone needs is added here, outside the manifest, and registered in
`_shared/project-rules.md`.
