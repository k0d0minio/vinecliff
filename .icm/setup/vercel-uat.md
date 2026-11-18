# Setup: UAT on each Vercel project that the client tests

- where: Vercel → the project → Settings, and the domain registrar

## Steps

Do these steps on each Vercel project of an app that the client tests:

1. Make sure that the team is on the Pro plan. A custom environment needs it.
2. Make sure that the git link of the project is this repo.
3. Settings → Environments: add the custom environment `uat`. Set its branch tracking to
   `main`.
4. Attach the domain `uat.<the production domain>` to `uat`. Add its CNAME record.
5. Settings → Environments → Production: set "Auto-assign Custom Production Domains" to
   off. Each merge then makes a staged production build that serves nothing.
6. Set the variables of the app on `uat`. Use sandbox keys, never live keys.
7. In a monorepo: Settings → Build: remove each `ignoreCommand` (turbo-ignore) and turn on
   "Skip deployments when there are no changes to the root directory or its dependencies".
8. Write the project and the UAT address in `.icm/environments.md`.

A project that the client does not test gets no `uat`. It keeps Auto-assign on and follows
`main`.

## Done when

- [ ] `.icm/_system/scripts/promote.sh status` lists each project that the client tests.
- [ ] It prints no line `SETUP:`.
- [ ] The UAT address opens the newest build of `main`.
