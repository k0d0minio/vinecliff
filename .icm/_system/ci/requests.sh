#!/usr/bin/env bash
# requests.sh — a Copier task (1.0.0-rc27, JAM-577). It adds the key "requests" to
# .icm/project.json when the key is missing. An update does not write project.json again
# (_skip_if_exists), and features/requests.md reads the key. No other key changes.
set -euo pipefail
pj=".icm/project.json"
[ -f "$pj" ] || exit 0
command -v jq >/dev/null 2>&1 || { echo "icm: no jq. Add the key requests to $pj (features/requests.md)"; exit 0; }
! jq -e 'has("requests")' "$pj" >/dev/null || exit 0
if [ "$(jq -r '.ticket_source // "markdown"' "$pj")" = linear ]; then
  add='{store: "linear", linear_team: (.linear.team_key // ""), linear_label: "source/client", linear_project: ""}'
else
  add='{store: ".icm/requests"}'
fi
tmp="$(mktemp)"
jq --indent 2 ". + {requests: $add}" "$pj" > "$tmp" && mv "$tmp" "$pj"
echo "icm: added the key requests to $pj"
