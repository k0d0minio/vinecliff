# The fallback patterns — what `security-check.sh` scans for without gitleaks

`gitleaks` is the scanner of record (`brew install gitleaks`); its rule set is far larger than
this. When it is absent the gate still runs these shapes over the added lines, and says so with
a `[WARN]`. They are chosen for **precision** — a hit is almost never a false positive — at the
cost of recall; a repo that handles secrets seriously installs gitleaks.

| rule | shape |
|---|---|
| aws-access-key | `AKIA…` / `ASIA…` and the other AWS key-id prefixes, 16 more characters |
| github-token / github-fine-grained-token | `ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`, `github_pat_` |
| slack-token / slack-webhook | `xox[baprs]-…`, `hooks.slack.com/services/T…/B…/…` |
| stripe-live-key | `sk_live_…`, `rk_live_…` (test keys are not flagged) |
| openai-key / anthropic-key | `sk-…`, `sk-proj-…`, `sk-ant-…` |
| resend-key / sendgrid-key / google-api-key | `re_…`, `SG.….…`, `AIza…` |
| private-key-block | `-----BEGIN … PRIVATE KEY` |
| database-url-with-password | `postgres://user:password@…` and the mysql / mongodb / redis / amqp forms |
| jwt | three base64url segments starting `eyJ` |
| generic-secret-assignment | `api_key`, `secret`, `token`, `password`, `client_secret` assigned a quoted value of 16+ characters (case-insensitive) |

A line containing `example`, `placeholder`, `xxxx`, `<your`, `changeme`, `dummy`,
`process.env`, `os.environ`, `${` or `env(` is skipped — those are the shapes of a manifest,
not of a leak. Lockfiles, minified bundles, source maps, images and the run's own `error.log`
are never scanned.

Not covered on purpose: high-entropy strings with no prefix (gitleaks' entropy rules), cloud
provider secrets without a fixed shape, and anything base64-wrapped. The fallback is a floor.

## The `.env` rule

Any file named `.env` or `.env.<anything>` in the change set is a finding on its own, whatever
it contains — except `.env.example`, `.env.sample`, `.env.template`, `.env.dist` and
`.env.local.example`, which are the manifest `env.sh audit` reads.
