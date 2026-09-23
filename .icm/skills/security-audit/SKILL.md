---
name: security-audit
description: Find and stop secrets or high-severity vulnerabilities before a commit, a push or a merge, and handle a finding without leaking it.
triggers:
  - security-check.sh
  - secret, token, credential, .env
  - gitleaks, npm audit, vulnerability
  - Release stop class 2
  - error.log
---

# Security audit — the zero-trust gate, and what to do when it fires

The gate is `.icm/scripts/security-check.sh` (template-owned; its header is the specification).
It reads exactly what is about to leave the machine, never trusts a file name or an author, and
redacts everything it prints. This skill is the procedure around it.

## When

- **Build, before every commit**: `security-check.sh <slug>` (staged scope — seconds, no network
  unless a manifest or lockfile changed). A repo that wires it as its git pre-commit hook
  (`_shared/project-rules.md` → The factory) runs the same call on every `git commit`.
- **Every lane, before its push**: `security-check.sh <slug> --branch`.
- **Release step 4, the security-critical pass**: `security-check.sh <slug> --branch --audit` is
  the deterministic input to stop class 2; the review reads its output before it reads the diff.
- **A scheduled or ad-hoc audit of the whole tree**: `security-check.sh --all --audit`.

## The verdicts

| line | meaning | do |
|---|---|---|
| `RESULT: OK` | nothing found | carry on; a `[WARN]` above it names a check that could not run — say so in `notes.md` |
| `RESULT: SKIP` | nothing in scope | carry on |
| `RESULT: BLOCKED <n>` | `<n>` findings, trace in `error.log` | **STOP the commit** — the procedure below |
| `RESULT: FAIL` | `--strict` and a check could not run | install what is missing (gitleaks), or run without `--strict` and record the gap |

## On BLOCKED — the procedure

1. **Read the redacted trace** — on stdout and appended to the run's
   `03_build/output/error.log` (a lane: `lane/output/error.log`). It names the rule, the file
   and the line. It never shows the secret; do not go looking for it in the diff to "check".
2. **Remove the secret from the change.** The value goes to the environment (`env.sh add <KEY>`
   reads it on stdin and never prints it; `env.sh doc <KEY>` prints the `.env.example` block).
   A `.env*` file in the change set is `git rm --cached` and added to `.gitignore`.
3. **Treat it as compromised.** A secret that reached a diff reached a transcript. Tell the
   operator in the stop message which provider issued it and that it must be **rotated**; the
   rotation is theirs (the provider's dashboard), never yours, and never something the session
   does through an MCP on its own initiative.
4. **Never `--no-verify`, never bypass the hook, never commit "for now".**
5. **Complete the `error.log` entry the gate wrote** — its `- resolved:` line (what was staged,
   why the gate caught it, what is true now) and a `- rule:` line only when the leak was a
   constraint of this repo (a key some script reads from a file it should not); `retrospective.sh`
   promotes it at Release. What no tool logged — the habit behind the paste — is `FAILURE.md`'s.
6. Re-run the gate → `OK`, then commit.

## Dependency findings

`dependency-audit` names the package manager and the count. Fix by upgrading the affected
package in this branch **only when the spec's `touches:` covers the dependency manifest**;
otherwise park it as a triage stub (`lane: chore`, `found-by: security-check · <date>`) and say
so in `## Notes for Release` — a dependency bump is not this ticket's diff. A finding
introduced by this branch's own dependency change is this branch's to fix.

## References

- `references/secret-patterns.md` — what the built-in fallback scans for when gitleaks is
  absent, and what it deliberately does not.
- `bash .icm/skills/security-audit/scripts/audit.sh <slug>` — the Release-pass invocation with
  the trace summarised (Level 3).
