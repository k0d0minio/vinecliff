# Vine Cliff Vineyards — app

The Vine Cliff Vineyards website and request-to-book platform, built by Legible Consulting.
The repo tracks `legible-consulting/blueprint` (tier `app`) through `.copier-answers.yml`.
This file is identity and routing only.

## Routing

| You are asked to | Go to |
|---|---|
| build the next ticket, or any ticket | `.icm/intake/CONTEXT.md` (the loop), then the stub |
| open, fill or finish a pull request | `.github/pull_request_template.md`. The gates sit at its top |
| plan new work | `.icm/intake/CONTEXT.md` (an epic with a breakdown), never a loose list |
| understand the app, its stack and its data | `README.md` |
| change what CI checks or how a release is cut | `legible-consulting/.github` (`check-client.yml`, `release.yml`). `ci.yml` here only calls them |
| change a file the blueprint renders | the blueprint, then `copier update` here |

## Rules

- Client-facing text in `en-US`. Code, commits and notes in English.
- Technical text (stubs, pull request bodies, commits, questions) in Simplified Technical
  English: short active sentences, one instruction each, no semicolons. A question for Jamie
  is numbered and carries a default answer.
- CI is truth: never run build, lint, typecheck, test, format or dev locally. Push, then read
  the `ci` run.
- Secrets never in git: names only, values in GitHub or Vercel settings.
- One ticket is one branch and one pull request. The pull request moves the stub to `_done/`.
  Gates are human checkboxes: read them, never tick them.
- `main` changes by PR. The merge is a human's.
