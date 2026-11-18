# Setup: the names that the workflows ci and promote read

- where: GitHub → the repo → Settings → Secrets and variables → Actions, and Settings → Actions

## Steps

1. In Vercel, make a token for the team. Add it as the repo secret `VERCEL_TOKEN`.
2. Add the repo variable `VERCEL_TEAM`: the slug of the Vercel team. No variable names a
   project: the scripts find the projects from the git link.
3. Settings → Actions → General: turn on "Allow GitHub Actions to create and approve pull
   requests". release-please opens the release pull request with it.
4. In Linear, if the repo answered `linear_states: true`: fill the keys `changes`,
   `approved` and `live` of `linear.states` in `.icm/project.json` with state names of the
   team.

## Done when

- [ ] A merge to `main` opens or updates the release pull request.
- [ ] `.icm/_system/scripts/promote.sh status` reads each UAT project.
