# Setup: production's connection string for the migration in promote.yml

- setup-slug: actions-production-database
- needs: uat, a database
- where: GitHub → the repository → Settings → Secrets and variables → Actions

## Why

`promote.yml` migrates production before it promotes. Without this secret, a build whose
`package.json` names `db:migrate` stops the promotion before production moves.

## Steps

1. Copy production's direct (unpooled) connection string from the database's console.
2. In GitHub, add the repository secret `DATABASE_URL` with that string.
3. Put the string nowhere else in GitHub. No workflow but `promote.yml` reads it.

## Done when

- [ ] The repository has the secret `DATABASE_URL`, with production's direct connection
      string.
