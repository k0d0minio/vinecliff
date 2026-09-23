#!/usr/bin/env bash
# report.sh — the project's reporting hook: one message kind in, the repo's own channels out.
#
# PROJECT-OWNED (seeded once, never synced) — but the template's copy is complete, not a stub:
# every channel below works from the first merge with no edit, and a repo changes WHAT it
# reports where by editing `.icm/project.json` → reporting, never this file. Release step 9 and
# every lane's last step call `report.sh announce`; a CI workflow that finds a fault calls
# `report.sh alert`; nothing else in the pipeline ever names a channel.
#
# Kinds and channels:
#   announce   what shipped — github-release (ON BY DEFAULT), slack, email
#   alert      something broke after a merge — slack, email. Mapped to NO channel (the seeded
#              default) it means: the CI job that found the fault fails, and GitHub's own
#              notification to the repository owner is the alert; Vercel's deployment-failed
#              email is the second free channel. Recorded in _shared/project-rules.md → Reporting.
#   economics  a cost roll-up — mapped to no channel by default; icm-board's run-economics.sh
#              writes the number into the deal folder instead.
#
# The channels, all implemented here:
#   github-release  POST /repos/{o}/{r}/releases through lib/gh.sh — tag `<tag_prefix><YYYY-MM-DD>-<slug>`
#                   on the merge SHA (HEAD unless --sha), name = the summary, body = --body's file
#                   or the summary plus the PR link, prerelease false. IDEMPOTENT BY TAG: a tag
#                   that already exists is SKIPPED, never re-cut. `--audience internal` gets no
#                   Release (mirroring a changelog index that lists public entries only) and is
#                   announced on the other channels only.
#   slack           chat.postMessage with the bot token named by channels.slack.token_env, to the
#                   channel id named by announce_channel_env (announce) or alert_channel_env
#                   (alert, economics).
#   email           POST https://api.resend.com/emails with the key named by api_key_env; sender
#                   and recipients from from_env / to_env — variable NAMES in the repo, values in
#                   the environment, never a literal address in git.
#
# A configured channel whose variable is unset prints `SKIPPED <channel>: <VAR> unset` and names
# the `env.sh add <VAR> --ci` that fixes it. Nothing here is a gate: EXIT 0 ALWAYS.
# `--dry-run` prints every payload it would send and sends nothing — no token is needed for it.
#
# Runtime dependencies: none outside the repo. It reads .icm/project.json (lib/project.sh), the
# GitHub route (lib/gh.sh — the repo's own token or gh login), and whatever channel variables the
# repo declares. It never reads a registry, a deal folder, or anything under ~/Apps.
#
# Usage:
#   .icm/scripts/report.sh <announce|alert|economics> "<one-line summary>" \
#       [--slug <slug>] [--sha <merge-sha>] [--url <link>] [--body <file>] \
#       [--audience public|internal] [--dry-run]
#
# Verdict (stdout, last line):
#   RESULT: SENT <channels>              exit 0  — at least one channel took the message
#   RESULT: SKIPPED (no channel for <kind>)   exit 0  — the kind maps to nothing (a decision)
#   RESULT: SKIPPED (<reasons>)          exit 0  — every mapped channel was skipped, and why
#   RESULT: DRY-RUN <channels>           exit 0  — payloads printed, nothing sent
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# A reporting hook never exits non-zero — but a usage error is still said plainly.
usage() { echo "usage: report.sh <announce|alert|economics> \"<summary>\" [--slug s] [--sha sha] [--url u] [--body file] [--audience public|internal] [--dry-run]" >&2; echo "RESULT: SKIPPED (usage)"; exit 0; }
die()   { echo "error: $*" >&2; echo "RESULT: SKIPPED ($*)"; exit 0; }

command -v jq >/dev/null 2>&1 || die "jq not found"

kind=""; summary=""; slug=""; sha=""; url=""; body_file=""; audience="public"; dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --slug)     slug="${2:-}"; shift 2 ;;
    --sha)      sha="${2:-}"; shift 2 ;;
    --url)      url="${2:-}"; shift 2 ;;
    --body)     body_file="${2:-}"; shift 2 ;;
    --audience) audience="${2:-public}"; shift 2 ;;
    --dry-run)  dry=1; shift ;;
    --*)        usage ;;
    *) if [ -z "$kind" ]; then kind="$1"; elif [ -z "$summary" ]; then summary="$1"; else usage; fi; shift ;;
  esac
done
case "$kind" in announce|alert|economics) : ;; *) usage ;; esac
[ -n "$summary" ] || usage
case "$audience" in public|internal) : ;; *) die "--audience must be public|internal" ;; esac

# shellcheck source=lib/project.sh
source "$here/lib/project.sh"

mapfile -t channels < <(reporting_channels "$kind")
if [ "${#channels[@]}" -eq 0 ]; then
  echo "reporting.$kind maps to no channel in .icm/project.json — nothing to send (for alert: the red CI job and Vercel's own email are the alert; _shared/project-rules.md → Reporting)"
  echo "RESULT: SKIPPED (no channel for $kind)"; exit 0
fi

# The slug names the Release tag; default to the current branch without its claude/ prefix, or
# the short SHA when even that is main.
[ -n "$sha" ] || sha="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)"
if [ -z "$slug" ]; then
  slug="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  slug="${slug#claude/}"
  case "$slug" in ""|main|master|HEAD) slug="${sha:0:7}" ;; esac
fi
today="$(date -u +%F)"
body_text="$summary"
[ -z "$url" ] || body_text="$summary"$'\n\n'"$url"
if [ -n "$body_file" ]; then
  [ -f "$body_file" ] || die "--body file not found: $body_file"
  body_text="$(cat "$body_file")"
  [ -z "$url" ] || body_text="$body_text"$'\n\n'"$url"
fi

sent=(); skipped=()
skip() { echo "SKIPPED $1: $2"; skipped+=("$1: $2"); }

# --- github-release ------------------------------------------------------------------------------------

send_github_release() {
  local prefix tag payload resp http
  if [ "$kind" != "announce" ]; then skip github-release "a Release announces a merge; the $kind kind does not cut one"; return; fi
  if [ "$audience" = "internal" ]; then skip github-release "audience internal — announced on the other channels only, no public Release"; return; fi
  prefix="$(reporting_channel_field github-release tag_prefix 'release/')"
  tag="${prefix}${today}-${slug}"
  payload="$(jq -n --arg tag "$tag" --arg sha "$sha" --arg name "$summary" --arg body "$body_text" \
    '{tag_name: $tag, target_commitish: $sha, name: $name, body: $body, draft: false, prerelease: false}')"
  if [ "$dry" -eq 1 ]; then
    echo "--- github-release (dry run) POST /repos/<origin>/releases"; printf '%s\n' "$payload"; sent+=("github-release"); return
  fi
  # shellcheck source=lib/gh.sh
  source "$here/lib/gh.sh" || { skip github-release "lib/gh.sh could not initialise (no origin remote?)"; return; }
  if [ -z "${gh_token:-}" ] && ! (command -v gh >/dev/null 2>&1 && env -u GITHUB_TOKEN -u GH_TOKEN gh auth status >/dev/null 2>&1); then
    skip github-release "GH_TOKEN unset and no gh login — fix: export GH_TOKEN (contents: write on $repo), or .icm/scripts/env.sh add GH_TOKEN --ci"; return
  fi
  resp="$(gh_api GET "/repos/${repo}/releases/tags/${tag}")" || { skip github-release "GitHub unreachable"; return; }
  http="$(printf '%s' "$resp" | tail -n1)"
  if [ "$http" = "200" ]; then
    echo "github-release: tag $tag already exists — idempotent, nothing re-cut"; sent+=("github-release (existing)"); return
  fi
  resp="$(gh_api POST "/repos/${repo}/releases" "$payload")" || { skip github-release "GitHub unreachable"; return; }
  http="$(printf '%s' "$resp" | tail -n1)"
  if [ "$http" = "201" ]; then
    echo "github-release: $(printf '%s' "$resp" | sed '$d' | jq -r '.html_url // $tag' --arg tag "$tag")"; sent+=("github-release")
  else
    skip github-release "HTTP $http — $(printf '%s' "$resp" | sed '$d' | jq -r '.errors[0].message // .message // "no message"' 2>/dev/null) (a fine-grained token needs Contents: read and write; in Actions, permissions: contents: write)"
  fi
}

# --- slack ------------------------------------------------------------------------------------------------

send_slack() {
  local token_var chan_var token chan text payload resp
  token_var="$(reporting_channel_field slack token_env SLACK_BOT_TOKEN)"
  if [ "$kind" = "announce" ]; then chan_var="$(reporting_channel_field slack announce_channel_env SLACK_ANNOUNCE_CHANNEL_ID)"
  else chan_var="$(reporting_channel_field slack alert_channel_env SLACK_ALERTS_CHANNEL_ID)"; fi
  token="${!token_var:-}"; chan="${!chan_var:-}"
  case "$kind" in
    announce)  text=":rocket: *${summary}*" ;;
    alert)     text=":rotating_light: ${summary}" ;;
    economics) text=":abacus: ${summary}" ;;
  esac
  [ -z "$url" ] || text="$text"$'\n'"$url"
  payload="$(jq -n --arg c "${chan:-<$chan_var>}" --arg t "$text" '{channel: $c, text: $t, unfurl_links: false, unfurl_media: false}')"
  if [ "$dry" -eq 1 ]; then echo "--- slack (dry run) POST chat.postMessage"; printf '%s\n' "$payload"; sent+=("slack"); return; fi
  [ -n "$token" ] || { skip slack "$token_var unset — fix: printf '%s' \"\$VALUE\" | .icm/scripts/env.sh add $token_var --ci --github secret"; return; }
  [ -n "$chan" ]  || { skip slack "$chan_var unset — fix: .icm/scripts/env.sh add $chan_var --ci --github variable"; return; }
  resp="$(printf 'url = "https://slack.com/api/chat.postMessage"\nheader = "Authorization: Bearer %s"\nheader = "Content-Type: application/json; charset=utf-8"\ndata = @-\nsilent\nmax-time = 20\n' "$token" \
    | curl --config - --data-binary "$payload" 2>/dev/null)" || { skip slack "Slack unreachable"; return; }
  if [ "$(printf '%s' "$resp" | jq -r '.ok // false' 2>/dev/null)" = "true" ]; then echo "slack: posted to $chan_var"; sent+=("slack")
  else skip slack "Slack rejected the post: $(printf '%s' "$resp" | jq -r '.error // "unknown"' 2>/dev/null)"; fi
}

# --- email (Resend) ------------------------------------------------------------------------------------

send_email() {
  local key_var from_var to_var key from to subject payload resp
  key_var="$(reporting_channel_field email api_key_env RESEND_API_KEY)"
  from_var="$(reporting_channel_field email from_env REPORT_EMAIL_FROM)"
  to_var="$(reporting_channel_field email to_env REPORT_EMAIL_TO)"
  key="${!key_var:-}"; from="${!from_var:-}"; to="${!to_var:-}"
  subject="$summary"; [ "$kind" = "alert" ] && subject="[alert] $summary"
  payload="$(jq -n --arg f "${from:-<$from_var>}" --arg t "${to:-<$to_var>}" --arg s "$subject" --arg b "$body_text" \
    '{from: $f, to: ($t | split(",") | map(gsub("^\\s+|\\s+$"; ""))), subject: $s, text: $b}')"
  if [ "$dry" -eq 1 ]; then echo "--- email (dry run) POST https://api.resend.com/emails"; printf '%s\n' "$payload"; sent+=("email"); return; fi
  [ -n "$key" ]  || { skip email "$key_var unset — fix: printf '%s' \"\$VALUE\" | .icm/scripts/env.sh add $key_var --ci --github secret"; return; }
  [ -n "$from" ] || { skip email "$from_var unset — fix: .icm/scripts/env.sh add $from_var --ci --github variable"; return; }
  [ -n "$to" ]   || { skip email "$to_var unset — fix: .icm/scripts/env.sh add $to_var --ci --github variable"; return; }
  resp="$(printf 'url = "https://api.resend.com/emails"\nheader = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\ndata = @-\nsilent\nmax-time = 20\n' "$key" \
    | curl --config - --data-binary "$payload" 2>/dev/null)" || { skip email "Resend unreachable"; return; }
  if printf '%s' "$resp" | jq -e '.id' >/dev/null 2>&1; then echo "email: sent (id $(printf '%s' "$resp" | jq -r .id))"; sent+=("email")
  else skip email "Resend rejected it: $(printf '%s' "$resp" | jq -r '.message // .error // "unknown"' 2>/dev/null)"; fi
}

for ch in "${channels[@]}"; do
  case "$ch" in
    github-release) send_github_release ;;
    slack)          send_slack ;;
    email)          send_email ;;
    *)              skip "$ch" "unknown channel in reporting.$kind — the implemented channels are github-release, slack, email" ;;
  esac
done

if [ "$dry" -eq 1 ]; then
  echo "RESULT: DRY-RUN $(printf '%s ' "${sent[@]}" | sed 's/ $//')"
elif [ "${#sent[@]}" -gt 0 ]; then
  echo "RESULT: SENT $(printf '%s ' "${sent[@]}" | sed 's/ $//')"
else
  echo "RESULT: SKIPPED ($(printf '%s; ' "${skipped[@]}" | sed 's/; $//'))"
fi
exit 0
