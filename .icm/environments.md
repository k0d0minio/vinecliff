# Where the build runs

| Environment | Address | Vercel project | Database | Moves on |
|---|---|---|---|---|
| Production | https://www.vinecliffvineyard.com | `vinecliff` | the default branch of the Neon project `vinecliff` | `promote.sh run --tag <tag>`, on Jamie's word |
| UAT | <no custom environment `uat` on the Vercel project on 2026-10-29> | `vinecliff` | <no Neon project `uat-vinecliff` on 2026-10-29> | every merge to `main` |
| Preview | the pull request's Vercel preview | `vinecliff` | <Preview and Production share one `DATABASE_URL` on 2026-10-29: Preview reads production. Triage stub `env-cleanup-vinecliff`> | every push to the branch |

This table is the one home of where the build runs. The blueprint's files read it and never
repeat it. The blueprint owns this file: `copier update` merges a new tag into it three ways,
so a cell that a person filled stays filled.
Each setup stub in `.icm/intake/setup/` names the cells that it fills.
A person fills each `<…>` cell that no setup stub fills, when the project or the domain exists.
The UAT contract: `.icm/uat/CONTEXT.md`.
The database contract: `.icm/database/CONTEXT.md`.
