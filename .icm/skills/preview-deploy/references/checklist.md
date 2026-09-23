# The flip and the read — checklist

## Ready flip (Build)

- [ ] `env.sh audit --changed` → `RESULT: OK`
- [ ] `ci-status.sh <slug>` → `RESULT: GREEN` on the draft head (cheap tier)
- [ ] `origin/main` merged in; no conflict inside `.icm/runs/<slug>/` (one there is a STOP)
- [ ] `check-migrations.sh` → `OK` or `SKIP` (only when the branch carries a migration)
- [ ] `security-check.sh <slug> --branch` → `OK`
- [ ] PR flipped to open, **then** a push (empty commit if nothing pending)
- [ ] `ci-status.sh <slug>` → `RESULT: GREEN` on the post-flip head (full tier), preview URLs listed
- [ ] `notes.md` names the preview URLs; `status.md` says `ci: GREEN`; `handoff.md` says "smoke, tick Ready to merge, then release"

## Production read (Release, after the merge)

- [ ] `deploy-status.sh <slug>` → `RESULT: READY` (one call; `PENDING` re-read once)
- [ ] `- production:` line in the `## Release` record — the deployment id and the previous READY id
- [ ] `report.sh announce …` called, or `deferred to CI` recorded (`reporting.announce_from`)

## Stop reasons — say them, do not route around them

| seen | it means | do |
|---|---|---|
| `ci-status.sh` → `RED` after the flip | the full gate failed on this head | fix on the branch, push, re-read; if not yours, say which check in Notes for Release |
| `ci-status.sh` → `PENDING` that will not settle | CI did not start or hung | re-run the call once; then stop and say so — never "not red yet" as green |
| a preview row `Skipped - Not affected` | nothing built for that project | it hosts no smoke; not evidence of green |
| `deploy-status.sh` → `ERROR <project>` | production deploy failed | stop; the recovery is `rollback.sh` + the `hotfix` lane, human-invoked |
| `env.sh audit --changed` → `GAPS` | a key is missing from a surface | declare it, tell the operator where the value goes; never invent one |
| `env.sh audit --changed` → `UNKNOWN` | a surface could not be read (rate limit, or a project the token cannot see) | re-run once; if it holds, `env-check.sh` names the project — not OK, and not a gap to "fix" |
