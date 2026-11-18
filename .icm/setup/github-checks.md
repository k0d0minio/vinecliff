# Setup: the checks of the workflow ci

- where: the repo, and GitHub → the repo → Settings → Rules

## Steps

1. Delete each workflow that calls `legible-consulting/.github`, for example
   `.github/workflows/gate.yml`. The workflow `icm` has the gate. The workflow `ci` of the
   blueprint has the code checks.
2. In the ruleset of the default branch, require the checks `secrets`, `workflows`, `code`
   and `icm-check`.
3. If the repo has secrets in its history, remove them and rotate them. `secrets` reads
   the full history.

## Done when

- [ ] `grep -r legible-consulting .github` finds nothing.
- [ ] The ruleset requires the four checks.
