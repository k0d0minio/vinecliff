# Vine Cliff Vineyards — app

The Vine Cliff Vineyards website and request-to-book platform, built by Legible Consulting.
The repo tracks `legible-consulting/blueprint` (tier `app`) through `.copier-answers.yml`.
This file is identity and routing only.

## Routing

| You are asked to | Go to |
|---|---|
| build the next ticket | `BUILD.md` |
| understand the app, its stack and its data | `README.md` |
| change what CI checks | `legible-consulting/.github` (`check-client.yml`). `ci.yml` here only calls it |
| change a file the blueprint renders | the blueprint, then `copier update` here |

## Rules

- Client-facing text in `en-US`. Code, commits and notes in English.
- CI is truth: never run build, lint, typecheck, test, format or dev locally. Push, then read
  the `ci` run.
- Secrets never in git: names only, values in GitHub or Vercel settings.
- `main` changes by PR. The merge is a human's.
