---
name: setup
description: >-
  Adopt this repo, or keep it honest — one idempotent command for the whole ritual: the
  register and its intent, the pipeline report and its config questions, the lens analysis and
  the ticket cut. Use for /setup, and for "setup", "adopt this repo", "set up the pipeline", "is
  the repo complete", "what is missing from .icm", "fill project.json", "what are we building",
  "what's the next ticket", "re-plan this repo". Intent first: no config question is asked
  before the project's intent is stated. Never needs icm-board in view.
---

# /setup — what this repo is for, whether it is set up for it, and what to build next

**One ritual, every stage of a repo's life** (decision D45). The first run adopts the repo:
it establishes intent, fills the project-owned files, and cuts the first tickets. Every run
after asks whether the intent still holds, closes the report's new gaps, and reconciles the
tickets to the answer. There is no separate onboarding, discovery, configuration or
sprint-planning command — this is all of them, and running it twice in a row is harmless. A
re-run that changed nothing is a valid outcome and says so.

**Intent before configuration.** The config questions are the report's, and they are only
asked once the project's intent has been stated or confirmed this session (step 4 before
step 5). A config answer given with no intent behind it is the failure this ordering exists
to prevent: an `editor` persona or a `production_url` recorded an hour before the
interrogation overturned them.

It does not contain the checks — `.icm/scripts/setup.sh` does, deterministically — and it
does not invent the config questions: the report says what is open. Everything it reads is in
this repo: the register's shape (`.icm/_shared/register.md`), the lens roster
(`.icm/_shared/lenses.md`), the ticket formats (`.icm/intake/CONTEXT.md`, the `ticket-craft`
skill), the commit rules (the `pr-conventions` skill), and the two read-only agents it fans
out (`.claude/agents/project-lens.md`, `.claude/agents/ticket-scout.md`). It runs in any
harness: where subagents cannot be spawned, run each agent's brief yourself, one at a time,
keeping each lens's findings apart until step 7.

The argument is: `$ARGUMENTS` — optional; `--template <path|url>` names a template source for
seeding a bare repo (there is **no default source**: a repo the dashboard created already carries
the baseline, and nothing here reaches for `../../_system`). On the operator's machine the source
is icm-board's checkout (`~/Apps/_system/template`); `ICM_TEMPLATE` in the shell names it too.

**What it writes, and where.** The project-owned files and the register
(`.icm/project.md`) — on a `claude/` branch PR the operator merges. The ticket cut
(`.icm/intake/`) — one direct commit to `main` (`pr-conventions` → Ticket commits). Never a
code file, except the one code change step 5 may agree (Husky), which rides the same
`claude/` PR. Never a `T` file. The agents write nothing at all.

## Procedure

0. **Guards — never error, always land somewhere.** Every one of these is a normal state:

   | Found | Do |
   |---|---|
   | Not a git repo, or no GitHub remote (`git remote get-url origin`) | **Stop.** The admin dashboard creates client repos (`createClientRepo`); say so and end |
   | No `.icm/scripts/setup.sh` | Seed first: from the repo root, `bash <template>/icm-pipeline/scripts/setup.sh --fix --template <template>` (a local checkout — fetch a URL source first); report what it seeded. No source in hand → **stop** and name that command |
   | No `.icm/project.md`, or the unfilled stub (`> Last run: never`) | First run — 1a |
   | `.icm/project.md` established | Re-run — 1b |
   | No tickets, no git history, no docs | Fine. Thin repo, thin first pass, more questions |
   | Uncommitted changes | Leave them strictly alone; never `git add -A` |

1. **Register and posture.**

   **1a · First run — adopt what exists.** Read before asking anything: `.icm/docs/` (client
   requests, proposals, discovery reports — a repo born from a kickoff arrives with the
   deal's documents already there), `.icm/processed/`, `AGENTS.md` / `CLAUDE.md`,
   `README.md`, any requirements doc. **Adopt, never fabricate.** Existing scope docs and
   decision registers are *folded in* with provenance cited — those decisions are made and
   are not re-asked. Only genuine gaps become questions.

   **1b · Re-run — reconcile before asking.** Read `.icm/project.md`; from its Run log take
   the last commit and get what happened since (`git log <sha>..HEAD --oneline` plus the
   changed paths). Then state the **posture** out loud so the operator can correct it:
   *launch* (no v1; unshipped essentials) · *maintenance* (v1 shipped; defects, health,
   drift) · *expansion* (stable; new features). Posture decides where the interrogation and
   the lenses aim. Never guess it silently.

2. **Run the report — read it, ask nothing yet.**

   ```bash
   .icm/scripts/setup.sh --report [--template <path|url>]
   ```

   Read the whole thing. Eleven sections: baseline · formatter exposure · project.json ·
   environment · tickets · raw · runs · knowledge · reporting · workflows · support. The last
   line is `RESULT: OK` or `RESULT: GAPS n`; the `[FAIL]` lines are the gaps, each with the fix
   or the question beside it. Quote the `RESULT:` line in the run.

   **Seed what is missing, never overwrite.** For an under-seeded repo, with a template
   source in hand:

   ```bash
   .icm/scripts/setup.sh --fix --template <path|url>
   ```

   `--fix` creates only what is absent (D7 — the same discipline as `icm-check.sh --fix`) and
   writes `.icm/template-version`. A template-owned file that has **diverged** is reported with
   the `icm-sync.sh --apply` command to run from icm-board; never edit a `T` file here — a change
   one is owed is a template change request (`.icm/_shared/template-change.md`: a prompt for
   icm-board, parked as a `found-by: template-change` triage stub, never an edit). Without a
   source the report says `SKIP template (no source)` and every in-repo check still runs.

   Then sort the report's open lines into two piles, and **ask neither yet**: the *config
   questions* (`project.json`, `project-rules.md` — held for step 5), and the *gaps that shape
   the ticket set* (an unfilled `deploy`, a `micro` repo, no reporting decision, a merged run
   still in `.icm/runs/` whose `close-out.sh` is owed — carried into step 7).

3. **Scan — cheap, structural, no fan-out.** Enough to ask good questions: the stack, the
   routes and entry points, the ticket state (every scope's stubs, `_done/` and build order;
   the `triage/` backlog; any legacy flat tickets still unmigrated), what shipped since the
   last run, whether the register's Features table still matches reality. **Reconcile the
   board first** — a stub whose work visibly merged is marked for its scope's `_done/` (the
   move is in step 8's plan and rides step 10's ticket commit); tell the commit that
   *created* a stub from the one that *did the work*, and where it is ambiguous, ask. Spawn
   `ticket-scout` when the repo has real git history.

4. **Interrogate — intent first: features and business logic.** The phase that decides
   ticket quality, and the one every config question waits on. Aim at what the project must
   *do* and the rules that govern it — a question that changes the feature set beats one that
   changes an implementation detail. `AskUserQuestion`, rounds of **at most 4**,
   highest-leverage first; stop when the remaining questions no longer change the ticket set,
   and say what you left unasked.
   - *First run:* who it is for · the one job · what done looks like · the business rules in
     the domain's own words · what is explicitly out, and why · the constraints (technical,
     the accessibility bar, legal/data, commercial) — asked once, recorded, inherited by
     every ticket, never derived.
   - *Re-run:* lead with the register — "Last run you decided X, Y, Z. Still true?" Nothing
     changed and the report is `OK` → say so and skip to 9.
   - *Every question carries an escape hatch:* "don't know yet" becomes an Open question, or
     a decision stub if it blocks. A question only the client can answer is recorded as an
     Open question with `who: client` (and a decision stub when it blocks) — never sent
     anywhere, never given an invented recipient.

5. **Configure — the report's questions, now with intent in hand.** Ask what step 2 held
   back, and only that, in the same rounds of ≤ 4. Two rules make the ordering pay:
   - **Intent answers first.** A config value the register or this session's interrogation
     already settles — the personas the Intent names, whether a site is launched and where —
     is not asked; write it and say where it came from.
   - **Intent checks every answer.** An answer that contradicts the stated intent (a persona
     the Intent never mentions, a production URL for something Intent says has not shipped) is
     raised back to the operator, never recorded as given.

   The questions are the report's `[FAIL]`/`[WARN]` lines for `project.json` and
   `project-rules.md` — plus what `project-rules.md` must say about who authors requests and
   where they arrive, the persona vocabulary, and which identities may push to `main` — in the
   operator's words, e.g.:
   - "`complexity`: is this a `micro` repo (a one-page site, a script) or `standard`?"
   - "No Slack or email is configured; `github-release` is on for `announce`. Add one? Which
     variables carry it?" (names only — never ask for a value)
   - "`deploy`: which Vercel project(s) does this repo deploy as, on which team, under which
     token *name*? Is `web` the product project and `docs` quiet?"
   - "`health_endpoint`: which URL answers `200` when production is up — one for the repo, or
     one per deploy project when they differ (`https://<production_url>/api/health`, or the
     fail-safe page itself)? `health-check.sh` reads it once after every merge; until it is set
     the read is `SKIP` and nobody is told production is down." Ask it whenever the report
     carries the `health_endpoint empty` line — it is a `[WARN]` for as long as the repo
     deploys somewhere and has no endpoint, so a repo that skipped it is asked again next run.
   - "`required_checks`: empty by default — the deploy status is the verdict and the quality job
     is advisory (`_shared/ci.md` → the cost floor); which check-run names, if any, must this
     repo still wait for, and why?" · "`personas`?"
   - "`migrations`: where do they live, are they reversible, which tool applies them (flyway /
     prisma / drizzle / mongodb / sql), and does that tool accept out-of-order stamps? New ones
     are named `V<17 digits>__<name>.sql` (`stamp: millis`) unless you keep the legacy `seconds`
     form — or, on a MongoDB runner such as ts-migrate-mongoose, `<13 digits>-<name>.ts`
     (`stamp: epoch`, `extension: ts`)."
   - "`database`: does this repo have a database, and where does it live? For a **Neon** project
     (`provider: neon`): the project id (Neon Console → Settings; a Vercel-managed database says
     it under Storage → Open in Neon — an id like `nameless-sea-98952497`, not a secret), the
     NAME of the variable that holds a Neon API key (`NEON_API_KEY` unless you keep another), the
     production branch (`main` unless renamed), and `previews: vercel` when the Vercel
     integration should create a database per preview deployment. With a UAT environment
     declared, also the UAT database — on Neon the project id of the **second Marketplace
     database** (`neon.nonprod_project_id`: Vercel → Storage → Create Database → Neon,
     `uat-<repo>`, then Open in Neon; never production's — D41) and `neon.reset_command`, the
     repo's own command that empties it and re-migrates and re-seeds it (`npx prisma migrate
     reset --force`, or the repo's script; empty is allowed), or on MongoDB `mongodb.uat_name`
     (`_shared/promotion.md` → The UAT database). Never write `neon.uat_branch` — the
     named-branch shape is retired and `setup.sh` fails it. For a **MongoDB** cluster
     (`provider: mongodb`, decision D35) — names only, never a URI: the NAME of the variable
     holding the cluster URI (`url_env`, `MONGODB_URI` unless you keep another), the variable the
     app reads its database name from (`mongodb.name_env`, `MONGODB_DATABASE_NAME`), the names of
     the production and the shared preview databases (`production_name`, `preview_name` — never
     dropped or reset), the repo's own seed and migrate commands (`seed_command`,
     `migrate_command`; the migrate command takes `up [<name>] [--single]` and `down <name>
     [--single]`), the runner's
     collection if not `migrations`, the cluster's caps (`limits` — 100 databases / 500
     collections on a shared Atlas tier, 0 for uncapped; `name_bytes` 38 there, 63 on a
     dedicated M10+ cluster), and `previews: branch` when each
     preview should read its own `preview_<branch>` (the app derives it; one flag on the Preview
     target switches it on). Isolation for a run: `neon` (one Neon branch per run — curl and the
     key, no psql or docker), `database` (one MongoDB database per run, `run_<slug>`, on the
     repo's cluster — node and its installed driver), `schema` (one Postgres schema per run on
     the variable `url_env` names), `container` (one local Postgres per run), or `none` for a
     repo without a database. The ids and names go in `project.json`; the key's and the URI's
     values never do."
   - "`security.audit_command`: an npm/pnpm/yarn lockfile is audited automatically — another
     ecosystem needs its command (pip-audit, cargo audit), or leave it empty."
   - "`support`: `none`, `basic` or `retainer`? Where is the fail-safe page? Which variable
     carries the Sentry DSN?"
   - "`uat`: does this project need a **UAT environment** the client signs batches off on before
     anything reaches production? If yes: the slug of the Vercel **custom environment** it will
     be (`uat` by convention — Pro only, one per project) and the one fixed address they will
     open (the domain attached to that environment) — never a per-batch preview. Production then
     stops following `main`: every merge is Staged and promoted when you publish the Release
     `promote.sh approve` drafts. If no, leave it undeclared: every merge ships, as before."
     Both `target` and `url`, or neither. **Refuse the declaration** when `setup.sh` says the team
     allows no custom environment ("UAT requires a Pro team") — UAT then stays undeclared. There
     is no UAT branch: never write `uat.branch`.
   - "Pre-commit formatting in cloud sessions: `.claude/hooks/install-deps.sh` installs
     dependencies at session start so Husky's pre-commit exists in a fresh clone (D44). It acts
     only where the root `package.json` has a `prepare` script naming husky. This repo formats
     with prettier but has no Husky — add it (`husky` + `lint-staged`, `"prepare": "husky"`, a
     `.husky/pre-commit` running `lint-staged`) so cloud commits come out formatted?" Not a
     report line — check it yourself: ask when `package.json` names `prettier` or `lint-staged`
     and `jq -e '(.scripts.prepare // "") | test("husky")' package.json` fails; say so too when
     `.claude/settings.json` never names `install-deps.sh` (the hook is then inert —
     `icm-check.sh --fix` in icm-board registers it). Adding Husky is a code change: it goes on
     the `claude/` branch step 10 opens, never as a project-owned file.
   - "`alert` maps to no channel — the red CI job is the alert. Keep that, and record it?"
   Every question has an escape hatch: "don't know" leaves the stub value and the report line.

6. **Analyse — lenses, scoped by what step 4 established.** Fan out `project-lens` agents per
   `.icm/_shared/lenses.md`, **in a single message** so they run concurrently. Each prompt
   carries: the repo path, its one lens, the intent and business logic, the constraints, the
   posture, and the open stub titles. Scope the fan-out — first run: every lens with
   substance (say which were dropped and why) · intent changed: the lenses intent touches plus
   the diff's domains · intent unchanged: only what the diff touches. A lens with nothing to
   say costs one line; a lens run on a question nobody asked buries the findings that
   mattered.

7. **Reconcile — intent in, tickets out.** Synthesis is **yours**, never an agent's. Dedupe
   (merge, keep the strongest evidence) · drop what open stubs or shipped work already cover ·
   rank by what moves the project (blocks launch or revenue · harms users now · explicitly
   asked · the rest — if a third is P0, none of it is) · reconcile against the Features table
   (every finding maps to a *wanted* feature or a breached constraint; one matching nothing is
   a new feature row or noise — say which). Step 2's ticket-shaping gaps join the pile. Then
   each existing stub against intent: still fits → untouched · wrong priority or scope → amend
   in place, saying why · no longer fits → `git mv` to its scope's `_done/` with
   `> Dropped: <reason, date>` · missing → cut. **Never reuse a slug within a scope.** A repo
   still carrying legacy flat `PREFIX-NNN` tickets is migrated here: re-cut the survivors into
   scopes or triage from the evidence (drop bias: the bar is "obviously required now"), and
   `git mv` the old files to `intake/_done/` with a `> Recut as <scope>/<slug>` (or
   `> Dropped:`) line.

8. **Show the plan, then write.** Nothing is written before the operator has seen, in one
   message: the posture · the register changes (decisions added or superseded, feature rows,
   open questions) · the config answers, file by file · the proposed cut — scopes with their
   build orders (sequence · slug · title · priority · size · lens), triage stubs, amendments,
   drops with reasons. Their yes gates this step; their corrections re-enter at the step they
   touch. After the write, `breakdown.md` is the review surface: editing it and asking for a
   re-cut steers the cut.

   **8a · The project-owned files**, from the step-5 answers — `.icm/project.json` (valid JSON;
   `jq -e .` before saving; the health endpoint goes to top-level `health_endpoint` — a string,
   or an array — or to `deploy.projects[].health_endpoint` when each project has its own, and
   `project-rules.md` → The factory names it), `_shared/project-rules.md` (every section a sentence or "none" — `## Learned rules` stays as
   seeded; `retrospective.sh` fills it at Release),
   `_shared/knowledge-map.md` where the repo has a docs tree, `scripts/format.sh` / `lint.sh` on
   the repo's own tools or left as `SKIP` stubs, `runs/README.md`. Nothing else: `T` files are
   the template's, code is the pipeline's. **When a UAT environment was declared**, also run
   `.icm/scripts/promote.sh init`: it prints the acts only the operator can perform — the custom
   environment and its domain, Auto-assign Custom Production Domains off, the UAT database and
   its variables, the environment deploying `main` — and seed the reference
   `.github/workflows/release.yaml` (it is the promotion) and, where production is migrated from
   CI, the reference `db-migrate.yml` shape (`workflow_call`; `uat-deploy.yaml` only where
   Vercel refuses branch tracking). Record who signs off and how under
   `_shared/project-rules.md` → People and gates, and the acts still owed there. Never touch
   Vercel from here (`.icm/_shared/promotion.md`). **When a Neon project was declared**, also run
   `.icm/scripts/db-env.sh init`: it prints the database's one-time acts — the API key and where
   it lives (the shell, and this repository's Actions secrets through `env.sh add … --ci --github
   secret`), the integration's Preview-branching toggle, the migrate step in the build, protecting
   the production branch, and on a UAT repo the second Marketplace database's acts (its
   connection on the UAT environment + Preview, production's on Production only, Neon Auth to
   match production's) — and, with `previews: vercel`, `setup.sh --fix --template <path>` seeds
   the reference `.github/workflows/neon-cleanup.yaml`. Record the topology and the acts still
   owed under `_shared/project-rules.md` → The factory → The environments' databases. Never
   create a Neon branch, flip the toggle or set a build command from here: `db-env.sh` reads and
   lists, and its two writes (`reset-uat`, `prune`) run only on `--apply` from the operator.
   **When a MongoDB cluster was declared**, run `.icm/scripts/db-env.sh init` the same way: it
   lists the database user's rights, the caps, and — with `previews: branch` — Vercel's system
   variables, the app's one connection line (`.icm/scripts/lib/db-name.mjs`), the preview-migrate
   workflow and the smoke check waiting on it, the reference `mongodb-cleanup.yaml`
   (`setup.sh --fix --template <path>` seeds it), and last the flag
   `MONGODB_PREVIEW_PER_BRANCH=1` on the Preview target. The app change is a chore run in the
   repo, not an edit from here; the flag is the operator's to set, and unsetting it is the revert.

   **8b · The register** — `.icm/project.md`, per `.icm/_shared/register.md`: the header's
   `Last run` line set to today and `HEAD`; decisions appended with stable IDs (supersede,
   never edit away); the Features table brought current, rows pointing at intake paths; open
   questions carried forward; a Run log row with the date, `HEAD` and what changed. Sections
   nobody has established stay `— not yet established`.

   **8c · The cut** — per `.icm/intake/CONTEXT.md` → Formats and the `ticket-craft` skill:
   related work becomes a scope, `intake/<scope-slug>/` with a `breakdown.md` (what was
   understood + the build order) and one stub per unit of work, sequenced `1..m` in
   dependency order; one-offs become `triage/` stubs with their lane and `- found-by: setup ·
   <date>`. Every stub carries a `- sources:` line citing its evidence — the client's own words
   where they exist. `## Prompt` is optional: a stub is its own brief. Where the repo carries
   `.icm/scripts/validate-intake.sh`, it passes over every scope touched.

9. **Re-run `setup.sh` until `RESULT: OK`** or until every remaining line is a named decision
   the operator took (recorded in `project-rules.md`). `setup.sh --report` must print the same
   bytes twice in a row before you stop.

10. **Land it — two operations, one run.** Each half keeps its own convention:
    - **The cut** — one direct commit to `main` per `pr-conventions` → Ticket commits: a
      worktree off `origin/main`, only `.icm/intake/**` staged, `Plan: /setup — <one line>`,
      `git push origin HEAD:main`. Nothing cut or moved → no commit.
    - **The project-owned files and the register** — a `claude/` branch: stage paths
      explicitly (never `git add -A`), push, open the PR with `create_pull_request`
      (`base: main`, ready — nothing to preview), body: the report's last `RESULT:` line, the
      posture, and the decisions taken. A bare repo's first run is one PR; a run that changed
      neither opens nothing and says so. Never merge; never subscribe to the PR
      (`.icm/_shared/github.md` → PR events).

    Report per `.icm/_shared/output.md` — `setup <RESULT line> · CI <verdict> · <PR URL>` (no
    PR → `no changes`), then the closing summary: posture · intent changed? · scopes and stubs
    cut, by priority · the stubs you would pick next · what is still unanswered and what it
    blocks. Then `Operator:`: merge the PR, and every act still owed that `project-rules.md`
    records (the `promote.sh init` / `db-env.sh init` lines above, a Vercel toggle, a token) —
    one item each, actionable from the line alone.

## Audit — before the run reports

- The report's `RESULT:` line is quoted, not assumed; no config question was asked before
  step 4 stated or confirmed intent.
- The register and the board agree with each other and with the code — no feature row
  without its scope or stub, no stub contradicting a decision, no config value contradicting
  the Intent.
- Every scope's bookkeeping holds: sequences contiguous, `depends-on` ordered, the build
  order agreeing with the stubs.
- Nothing was asked that a document or the register already answered; nothing written that
  no one stated.
- The ticket commit touched only `.icm/intake/**`; the PR touched no `T` file.

## What this replaces, and what it does not touch

D23 split adoption in two: this command filled the project-owned files, and icm-board's
`/project` held intent, analysis and tickets, with nothing to stop the config being answered
first. D45 fuses them here. icm-board's `/project` stays only as the fallback for a repo not
yet carrying this version, and retires once every repo does. The estate walk (`/icm-check` in
icm-board) still runs each repo's `setup.sh --report` where the script exists — one
implementation, two callers. The formatter guard (section 2) is reported with the exact lines
to add and never written by a script (D17/D19). `setup.sh` itself is unchanged: this skill
asks and orchestrates; the script checks.
