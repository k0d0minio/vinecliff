# Where the build runs

| Environment | Address | Vercel project | Database | Moves on |
|---|---|---|---|---|
| Production | https://www.vinecliffvineyard.com | `vinecliff` | the default branch of the Neon project `vinecliff` | the promotion, on Jamie's word |
| UAT | <no custom environment `uat` on the Vercel project on 2026-10-29> | `vinecliff` | <no UAT database on 2026-10-29> | every merge to `main` |
| Preview | the pull request's Vercel preview | `vinecliff` | <Preview and Production share one `DATABASE_URL` on 2026-10-29: Preview reads production.> | every push to the branch |

This table is the one home of where the build runs. This file belongs to the repo. The
scripts find the Vercel project from the git link of the repo, not from this file.
A person fills each `<…>` cell when the project, the domain or the database exists. The setup
acts are in `.icm/setup/`.
The UAT contract: `.icm/_system/features/uat.md`.
The database rule: `.icm/local/database.md`.
