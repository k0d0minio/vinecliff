# Where the build runs

| Environment | Address | Vercel project | Database | Moves on |
|---|---|---|---|---|
| Production | <the production domain> | <the Vercel project> | the default branch of the Neon project `vinecliff-vineyard` | `promote.sh run --tag <tag>`, on Jamie's word |
| UAT | <https://uat.the production domain> | <the Vercel project> | the default branch of the Neon project `uat-vinecliff-vineyard` | every merge to `main` |
| Preview | the pull request's Vercel preview | <the Vercel project> | the Neon branch `preview/<branch>` in `uat-vinecliff-vineyard`, made by the Neon integration | every push to the branch |

This table is the one home of where the build runs. The blueprint's files read it and never
repeat it. The blueprint owns this file: `copier update` merges a new tag into it three ways,
so a cell that a person filled stays filled.
Each setup stub in `.icm/intake/setup/` names the cells that it fills.
A person fills each `<…>` cell that no setup stub fills, when the project or the domain exists.
The UAT contract: `.icm/uat/CONTEXT.md`.
The database contract: `.icm/database/CONTEXT.md`.
