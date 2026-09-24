# Stage 01 — Scope (contract)

Invoked via `/pipeline scope <input>` — the input is whatever the operator has (see Inputs). The
`/pipeline` router reads this file and follows it. Your job is **one thing**: understand what is
being asked — through the lens of the business _and_ the codebase — settle it with the operator in
session, write it down plainly as `scope.md`, and cut it into an intake batch that `/pipeline new`
walks into Define. No spec, no code, no feature branch, no feature PR.

This is the whole front: the settle and the cut happen here, in one sitting, and the stage ends
with the artifacts committed straight to `main` — the one home of ticket state, UAT or not
(D39 (8)) — for the human to review. **No revision path either** — a scope that came out wrong is deleted and Scope is run
again from the source.

## Inputs (read only these)

- **The source** — whatever the operator supplies as the argument or in conversation: a pasted user
  story, a prototype URL, a document, a prompt written after a call, a chat thread. Any medium.
  This is the stage's subject; everything else frames it.
- `.icm/_shared/knowledge-map.md` — the pages it names for Scope, the business pages first, for
  vocabulary: which persona(s) this serves, the initiative or objective behind it (the why-now),
  and the entities, journey steps, persona names and product seams the cut runs along.
- **The repository, as needed.** Scope may read the whole codebase — `apps/**`, `packages/**`,
  the docs tree, the repo's code rules (the file `_shared/conventions.md` points at), the
  `AGENTS.md` files. Read code for three reasons only: to check that a requirement is clear enough
  to build, to check that nothing here will break what already works, and to see that the feature
  integrates with what exists rather than being forced in. Reading code to _design the
  implementation_ is Define's and Build's job, not this stage's.
- `.icm/_shared/scope-template.md` — the shape of `scope.md`.
- The repo's voice/brand skill, where it ships one — the voice of anything the business will read.

Context budget: the Inputs above are the budget (see `.icm/CONTEXT.md` → Layers). Reading the
codebase is allowed, not free — load what the questions in front of you need, and record overruns
on a one-line `context-budget:` note in `run.md`.

## The one writing rule: simplicity

Everything this stage writes — `scope.md`, the breakdown, the stubs — reads plainly. Short
sentences. Plain words. The bigger picture is fine; Define goes into detail later. Technical facts
belong in the text **when they matter** to what is being decided ("today a lead has no vendor on
it, so the first stub adds one"); jargon for its own sake does not. Name a surface by what a
person must be able to decide or do there, not by the control they click. If a sentence needs a
glossary to follow, rewrite it.

## Process

1. **Pick the slug** — short kebab-case (e.g. `csv-export`). It names everything from here on: the
   run folder, the intake folder, every feature branch and PR cut from it. One string traces the
   work end to end. Then the first act of every stage:
   `.icm/scripts/usage-snapshot.sh <slug> scope start` — it creates `.icm/runs/<slug>/usage.md`
   (`SKIP` is fine, never a stop). Scope is the **advisor** pass — the model that settles a
   source is the frontier one: `.icm/scripts/select-model.sh --stage 01_scope` prints `opus`
   (`--complexity research` → `fable`, for a spike). If this session is on a lower tier, say so
   in one line; the operator decides, and nothing switches itself.

2. **Record the source.** Write `.icm/runs/<slug>/01_scope/_source/story.md` under a provenance
   header saying who it came from, when, and in what medium:

   ```md
   <!-- Source: <who — the author | a call with … | …>, <YYYY-MM-DD>, via <chat | email | call notes | prototype | document>.
        Recorded as received. Never edited — what was settled on top of it lives in scope.md. -->
   ```

   **A source that came through `.icm/raw/`** — an email, a chat export, a voice note, a PDF or a
   deck that `.icm/scripts/process-raw.sh` turned into `.icm/processed/<id>.txt`
   (`.icm/raw/README.md`) — is recorded from that extracted text, with the processed file and the
   archived original both named in the provenance header. Recording it **retires the pointer
   stub** the script parked: `git mv .icm/intake/triage/<id>.md .icm/intake/triage/_done/` with a
   `- superseded-by: runs/<slug>/01_scope/` line added under its `found-by:`, in the same commit.
   An extraction is a machine's reading — where the original is a recording or a scan, say so in
   the header, and check anything a decision rests on against the original.

   Text is recorded **verbatim** — no grammar fixes, no reordering into sections, no dropped
   asides. Several messages are concatenated in order, each under its own dated sub-heading.
   Anything that is not text — a prototype URL, a document, a design file — is recorded **by link
   plus a short description** of what it shows. The point of this file is that a reader three
   stages later can see exactly what was asked for, separately from what we made of it.

3. **Understand it — business and codebase together.** A source says what someone wants; a scope
   says how the business works when they have it, and how that lands in the product that exists.
   Go deep on the logic: who acts, what starts it, what happens in what order, what the rules and
   thresholds are, what state things are in and what moves them, who is told what and when, what
   money or time is involved, what happens when it goes wrong. Get concrete — real amounts, real
   durations, real counts.

   Then read the code the request touches, with the three questions from Inputs in mind: is each
   requirement clear enough to build; does anything here break current behaviour; does the feature
   fit what exists or fight it. What you find shapes the questions you ask next and the seams you
   cut along — it does not go into `scope.md` as implementation design.

4. **Interrogate the operator, in rounds.** Ask sharp questions with `AskUserQuestion` — several
   rounds if needed — until you have what you need. Where a rule is genuinely undetermined,
   **propose one and ask**: a proposal can be answered in one word. Every answer that settles
   something becomes a decision with a stable id (`D-1`, `D-2`, …) in `scope.md`; the id is the
   trace from decision to stub to spec, so never renumber one.

   There is no question sheet and no answering out of band: the operator answers here, now, with
   whatever they know from the conversation behind the request. **Anything the operator cannot
   settle is written down, never assumed** — as a line under `## Open for Define` in `scope.md`,
   and as a line in the relevant stub's `Notes for Define`. Define picks those up.

   **Out of scope** is worked out here too — what this round deliberately does not cover. It
   prevents more rework than anything else.

   For a spike or investigation, the same rounds land findings, a recommendation, and the decision
   the operator needs to make.

5. **Write `.icm/runs/<slug>/01_scope/output/scope.md`** — the settled scope, per
   `_shared/scope-template.md`: the pointer header, the source reproduced, then
   `## Assumptions` · `## Decisions` (the `D-n` table) · `## Out of scope` · `## Open for Define`.
   Re-read it once against the writing rule above.

6. **Cut the intake batch from `scope.md`.** The batch is `.icm/intake/<slug>/` — `breakdown.md`
   plus one stub per future feature PR, in a strict build order (formats: `.icm/intake/CONTEXT.md`).
   **Every scope gets an intake folder, however small** — a single-PR scope gets exactly one stub
   whose `feature-slug` is the scope slug itself.
   - **Cut along product seams.** Read `scope.md` for the distinct capabilities asked for, group
     each one's rules and personas into a stub, and treat anything the scope defers as a candidate
     for a later stub rather than padding for this batch. The entity and journey pages the map
     names give the natural boundaries; the code you read in step 3 says where the seams really
     are today. Each stub must map to **exactly one** future run / one PR —
     however many stubs that takes. If a candidate is too big to be one PR, **flag it** in the
     breakdown; never nest a scope inside a stub.
   - **Cut-level ambiguity is resolved from `scope.md`, not re-asked.** If the scope leaves a hole
     that affects the cut, go back to step 4 — don't guess.
   - **Strict build order.** Every stub gets a unique `sequence: n of m`, contiguous `1..m`; the
     order is a topological linearization of `depends-on` (a stub's number always exceeds every
     in-batch stub it depends on). Where the graph allows parallelism, still pick a deterministic
     tie-break (foundation first, then impact).
   - **`## Parallelizable` is derived from `touches:`, not asserted (D26).** Give every stub a
     `touches:` guess in its `Notes for Define`; a parallel set holds only stubs whose guesses do
     not overlap, and two stubs that share a surface are sequenced. **Shared-file stubs first**:
     the dependency manifest and lockfile, the schema and migrations journal, the app layouts,
     the message catalogues — the files that conflicted most in the estate's history — go at the
     head of the build order so every later stub merges over them
     (`.icm/intake/CONTEXT.md` → Formats). Build merges `origin/main` before its ready flip and
     `new-run.sh` warns on an overlap with a live run; the cut is where the overlap is avoided.
   - **Trace decisions.** Where a stub rests on a decision, name its `D-n` in `Notes for Define`;
     where it rests on an open point, copy that point into `Notes for Define` too.
   - **`breakdown.md` leads with What I understood**, so a misread is caught before the stubs:
     What I understood · Where it sits · Build order · Parallelizable · Out of scope.
   - **The bookkeeping is a script, not an eyeball:** `.icm/scripts/validate-intake.sh <slug>` →
     `RESULT: OK` before moving on. It owns the order invariants (`sequence` unique and contiguous,
     `of m` matching the stub count, every `depends-on` in-batch and sequenced first, `## Build
order` agreeing with the stubs). What it cannot judge, you still must: each stub is
     independently shippable, names a persona, carries the initiative/objective link, and sits on a
     real seam; re-cutting the same graph reproduces the same order.

7. **Write `.icm/runs/<slug>/run.md`** (Outputs below), seed the run's canonical file pack —
   `.icm/scripts/run-pack.sh <slug> --init` (`status.md` reads `phase: scope`; write `handoff.md`
   as "review scope.md and the batch on main, then `new`") — and **land it on `main` in one
   direct commit** (D39 (8)): from an up-to-date `main` (`git fetch origin && git checkout main
   && git merge --ff-only origin/main`), commit `story.md`, `scope.md`, `run.md`, the pack, and
   `.icm/intake/<slug>/**`, nothing else — commit message `Scope: <slug> — intake cut` — and
   push. **Verify the path guard first:** touch nothing outside `.icm/runs/<slug>/**` and
   `.icm/intake/<slug>/**` — plus the `triage/` pointer stub step 2 retires, where the source
   came through `.icm/raw/`; a diff that strays → STOP and do not push. A push rejected because
   `main` moved: `git pull --rebase origin main` once and push again. **A push refused by a
   ruleset** → STOP and report it as a setup gap (the operator's identity belongs on the
   ruleset's bypass list — `.claude/skills/pr-conventions/SKILL.md`) — never leave the artifacts
   local-only or on a side branch and carry on.

8. **Stop.** The usage line — `.icm/scripts/usage-snapshot.sh <slug> scope end` — is taken just
   before step 7's commit, so it rides that commit with the rest (it is inside the run folder
   the path guard allows).
   Report per `.icm/_shared/output.md`:

   ```
   **scope <slug> landed** — <n> stubs · CI n/a (direct commit to main) · <commit link>

   - <the stubs in build order, one line each>
   - <the ## Open for Define list, or "nothing open">

   Operator:
   1. review story.md, scope.md and breakdown.md on main: <the three main links>
   2. happy → run /pipeline new (walks the batch into Define); not happy → delete the run and intake folders and re-run Scope
   ```

   A scope they are not happy with is deleted (the run folder and the intake folder, in a direct
   commit of its own) and Scope is run again from the source — there is no revise path and
   nothing to patch in place.

On the push the source **freezes**: `_source/story.md` is never edited again, and the canonical
scope is `scope.md` until Define writes `spec.md`. Any later change to the substance is a visible
`spec.md` revision that re-opens the **Spec approved** tick. Scope never changes silently.

## Outputs

**Run-scoped, without exception** (`.icm/_shared/stage-preamble.md` → Run-scoped isolation): every working artifact of this stage lands under
`.icm/runs/<slug>/01_scope/` — nothing is drafted in a shared file or another run's folder — and
the only other paths a front writes are its own `run.md` and its own `.icm/intake/<slug>/`.

- `.icm/runs/<slug>/01_scope/_source/story.md` — the source, verbatim or by link. **Never edited.**
- `.icm/runs/<slug>/01_scope/output/scope.md` — the settled scope. **The canonical scope** until
  Define writes `spec.md`.
- `.icm/intake/<slug>/` — `breakdown.md` + one stub per future feature PR, `validate-intake.sh` →
  `RESULT: OK`.
- `.icm/runs/<slug>/usage.md` — the `scope start`/`end` usage lines (append-only; travels with the run).
- The canonical file pack at `.icm/runs/<slug>/` — `project.md`, `plan.md`, `tasks.md`,
  `decisions.md` (the `D-n` rows mirrored), `status.md`, `handoff.md`, `FAILURE.md`
  (`run-pack.sh`; the front fills `status.md` and `handoff.md`, the rest is Define's and Build's).
- `.icm/runs/<slug>/run.md` — the run's pointer index:

  ```md
  # Run: <slug>

  - lane: feature
  - story: 01_scope/\_source/story.md
  - author/source: <the author | call with … | prototype | …>
  - personas: <from the repo's persona vocabulary — `personas` in .icm/project.json>
  - scope-agreed: <YYYY-MM-DD — the day Scope settled it in session>
  - stubs: <n> (.icm/intake/<slug>/)
  ```

  `new-run.sh` appends `branch:` + `pr:` at Define — see the full template in `.icm/CONTEXT.md`.

All of it on `main`, in one direct commit. No spec, no code, no feature branch, no feature PR.

## Verify (before handing off)

- **The source is recorded as received** — text verbatim under the provenance header, anything
  else by link plus a description. Read it against what the operator supplied.
- **Nothing was assumed silently.** Every point the operator could not settle is under
  `## Open for Define` and in the relevant stub's `Notes for Define`; every settled point has a
  `D-n`.
- **Every stub maps to exactly one future PR** and `validate-intake.sh <slug>` printed
  `RESULT: OK`.
- **`scope.md` reads plainly** — short sentences, technical facts only where they matter, no jargon
  for its own sake; the operator could hand it to the business as-is.
- **The artifacts are on `main` and nothing was built** — one direct commit, pushed by this
  session after its path guard held; no spec, no code, no feature branch, no
  feature PR, and nothing touched outside `.icm/runs/<slug>/**` and `.icm/intake/<slug>/**`.
