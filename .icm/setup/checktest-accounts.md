# Setup: the test accounts of the checktest and the seed script

- where: this repo (the seed script), then the database of each environment

The BAXTER checktest tests UAT with test accounts (since 1.0.0-rc28, JAM-578). The
operator's rules:
- An account is `test+vinecliff-<role>@jamienisbet.com`, one for each role, or
  `test+vinecliff-<run>@jamienisbet.com` for a test of sign-up or of a one-time code.
  BAXTER reads the inbox for a code or a link. Use no other address.
- A test password stays in BAXTER's data, never in this repo.
- An admin role (or each role above a plain user) comes from the seed script of this repo.
  The checktest never runs it: the operator does, or a session on the operator's word, one
  time for each environment.

The contract of the seed script. This repo writes it; the blueprint does not.
- Name: the script `seed:test-roles` of `package.json` (a repo with no `package.json`:
  the executable file `scripts/seed-test-roles`).
- Input: `--email <address> --role <role> --target local|uat`. The database address comes
  from the environment of the target, never from the command line.
- It gives the role to an account that exists (the checktest signs the account up), and it
  can run again with no change. It refuses an address that is not
  `test+vinecliff-*@jamienisbet.com`, and it refuses the production database.
- Exit 0: the account has the role. Exit 1: refused or failed, with one line of reason.

## Steps

1. Write the seed script of the contract above, in this repo.
2. After the checktest signed up the admin account on UAT, run the seed one time for it:
   `pnpm seed:test-roles -- --email test+vinecliff-admin@jamienisbet.com --role admin --target uat`.

- [ ] The seed script exists, and the admin test account has its role on UAT.
