---
name: preview-deploy
description: Earn a preview on the ready flip, read production once after the merge, and recover with a prepared rollback — never a hand deploy.
triggers:
  - ready flip, draft to open
  - preview, Vercel, deployment, production
  - ci-status.sh, deploy-status.sh, rollback.sh
  - env.sh audit --changed
  - hotfix
---

# Preview and deploy — the factory builds, the session reads

Nobody in a session runs a deploy. Vercel builds per push, CI is the verdict, and four
template-owned scripts are the only reads: `.icm/scripts/ci-status.sh` (the settled verdict),
`.icm/scripts/env.sh audit --changed` (the environment this branch changed), `.icm/scripts/
deploy-status.sh` (production, once, after the merge) and `.icm/scripts/rollback.sh` (a
recovery, prepared, never executed). `_shared/ci.md` says what green means. This skill is the
order.

## Before the flip (Build steps 9–12)

1. `env.sh audit --changed` → `OK`. `GAPS n` is a key this branch added that is missing from a
   surface it is scoped to — `env.sh doc <KEY>` prints the `.env.example` block; the value is the
   operator's (`env.sh add <KEY>` reads it on stdin), never the session's. A gap left here stops
   the merge as Release stop class 3.
2. `ci-status.sh <slug>` → `GREEN` on the **draft** head (the cheap tier, no previews — blind
   until ready is the operator's decision, not a defect).
3. `git fetch origin main && git merge --no-edit origin/main`; a code change re-earns step 2.
4. Flip ready (`update_pull_request`, `draft: false`), **then push** — an empty commit when
   nothing is pending. Previews build per push: the post-flip push is what makes the full tier
   and the product-app previews exist on a fresh head.
5. `ci-status.sh <slug>` again → the **full gate**, with the preview URLs. RED is Build's to fix.

## Reading a preview

- The URL comes from `ci-status.sh`'s output, never from a deployment event or the bot's comment
  table (`pr-conventions` → the agent economy).
- `Skipped - Not affected` is not a preview: nothing built, nothing to smoke.
- The operator smokes the preview and ticks **Ready to merge**; the session never ticks it and
  never re-asks what the tick attests.

## After the merge (Release step 9)

- `deploy-status.sh <slug>` **once** → `READY` and the `- production:` line for the `## Release`
  record. `PENDING` is re-read once after the bounded wait; `ERROR <project>` is a stop-and-say,
  not a retry loop. `SKIP` means no `deploy` block in `.icm/project.json` — say so.
- Nothing watches production afterwards: a fault is `report.sh alert` (the red CI job where no
  channel is mapped) and the recovery is the human-invoked `hotfix` lane.

## Recovery

- `rollback.sh <slug>` prepares: a `claude/hotfix-revert-<slug>` branch and PR (`--revert`),
  and/or the previous READY deployment with the exact rollback call printed (`--vercel`). It
  executes neither. It warns when the merge carried a migration and `migrations.reversible` is
  false — a fix-forward may be the only safe path (`database-migration` skill).

## References

- `references/checklist.md` — the flip and the read as a checklist, with the stop reasons.
- `bash .icm/skills/preview-deploy/scripts/status.sh <slug>` — env audit + CI verdict in one
  call (Level 3).
