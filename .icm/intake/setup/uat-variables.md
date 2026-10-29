# Setup: the application's variables on the UAT environment

- setup-slug: uat-variables
- needs: uat
- where: Vercel → each UAT project → Settings → Environment Variables

## Why

The `uat` environment has its own variables. A name that `uat` does not have is empty in the
UAT build, and the client tests a broken page.

## Steps

1. Read `.env.example`. Find each name whose suffix names `uat`, and each name the application
   reads.
2. On each UAT project, add each name to the environment `uat`.
3. Use sandbox keys and test accounts. Never use a live key on `uat`.

## Done when

- [ ] Each UAT project has each name of `.env.example` that `uat` needs.
- [ ] No variable on `uat` holds a live key.
