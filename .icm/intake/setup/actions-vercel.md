# Setup: the Vercel token and team in GitHub Actions

- setup-slug: actions-vercel
- needs: uat
- where: GitHub → the repository → Settings → Secrets and variables → Actions

## Why

`promote.yml` and the UAT scripts read Vercel with these two names. Without them, no promotion
runs.

## Steps

1. In Vercel, make a token for the team. Give it the smallest scope that reads and promotes
   deployments.
2. In GitHub, add the repository secret `VERCEL_TOKEN` with the token.
3. Add the repository variable `VERCEL_TEAM` with the team's slug.
4. Add no variable that names a project. The scripts find the projects.

## Done when

- [ ] The repository has the secret `VERCEL_TOKEN`.
- [ ] The repository has the variable `VERCEL_TEAM`.
- [ ] `.icm/scripts/promote.sh status` lists each UAT project.
