# Setup: the UAT database on the UAT environment

- setup-slug: uat-database
- needs: uat, database neon
- where: Vercel → each UAT project → Settings → Environment Variables

## Why

The integration serves Preview and Production. The `uat` environment reads the default branch
of `uat-vinecliff-vineyard` from two variables that a person sets.

## Steps

Do these steps on each UAT project:

1. In the Neon console, copy the pooled and the direct connection strings of the default
   branch of `uat-vinecliff-vineyard`.
2. Add `DATABASE_URL` with the pooled string to the environment `uat` only.
3. Add `DATABASE_URL_UNPOOLED` with the direct string to the environment `uat` only.

## Done when

- [ ] Each UAT project has `DATABASE_URL` and `DATABASE_URL_UNPOOLED` on `uat`, from
      `uat-vinecliff-vineyard`.
- [ ] The UAT build log shows `[vercel-build] VERCEL_TARGET_ENV=uat: migrate, verify, then
      build`.
