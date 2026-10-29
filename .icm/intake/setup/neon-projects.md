# Setup: the Neon projects

- setup-slug: neon-projects
- needs: database neon
- where: the Neon console → the organisation

## Why

Production's data lives in `vinecliff-vineyard`. Every other deployment reads `uat-vinecliff-vineyard`, so
production's data never reaches a preview.

## Steps

1. In the Neon console, open the client's organisation.
2. Make the project `vinecliff-vineyard` for production, in the region nearest to the Vercel functions.
3. Make the project `uat-vinecliff-vineyard` for UAT, in the same region.
4. Put test data only in `uat-vinecliff-vineyard`. Never copy production's rows into it.
5. Compare the project names with the column `Database` of `.icm/environments.md`.
   If a name is different, correct the column.

## Done when

- [ ] The project `vinecliff-vineyard` exists.
- [ ] The project `uat-vinecliff-vineyard` exists, with test data only.
- [ ] The column `Database` of `.icm/environments.md` names `vinecliff-vineyard` and `uat-vinecliff-vineyard`.
