# Setup: the Neon integration on each Vercel project

- setup-slug: neon-vercel-integration
- needs: database neon
- where: Vercel → the team → Storage, and each project → Settings → Environment Variables

## Why

The integration makes each preview's database: a Neon branch `preview/<git branch>`, made
before the build, and deleted with the git branch. No script of this build does it.

## Steps

Do these steps on each Vercel project of the build that reads the database:

1. Open Storage. Connect the Neon project `uat-vinecliff-vineyard` to the project, for the
   environment Preview only.
2. Turn on a database branch for each preview deployment.
3. Turn on the deletion of the branch when its git branch is deleted.
4. Connect the Neon project `vinecliff-vineyard` to the project, for the environment Production
   only. Or set `DATABASE_URL` and `DATABASE_URL_UNPOOLED` of `vinecliff-vineyard` on Production by
   hand.
5. Open Settings → Environment Variables. Make sure that Preview has no `DATABASE_URL` and no
   `DATABASE_URL_UNPOOLED` for all branches.
6. Make sure that "Automatically expose System Environment Variables" is on.

## Done when

- [ ] A new pull request gets a Neon branch `preview/<git branch>` in `uat-vinecliff-vineyard`
      before its first build.
- [ ] Its preview build log shows `[vercel-build] VERCEL_TARGET_ENV=preview: migrate, verify,
      then build`.
- [ ] Preview has no `DATABASE_URL` for all branches.
- [ ] Production reads `vinecliff-vineyard`.
