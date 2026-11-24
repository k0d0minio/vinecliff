#!/usr/bin/env bash
# guards.sh — register the three repo guards in .claude/settings.json. Only Copier runs
# this, at a render and at an update, in the folder that it renders.
#
# The blueprint owns .claude/hooks/block-local-checks.sh, confirm-git-writes.sh and
# guard-plaintext-secrets.sh (1.0.0-rc18, JAM-439): a render and an update write them.
# .claude/settings.json belongs to the repo, and Copier writes it one time. A first render
# has the registrations from the template. A repo of an earlier version gets them here.
#
# The script adds an entry to hooks.PreToolUse only when the repo has no registration of
# that guard for that tool. A repo that registered a guard by hand keeps its line: no guard
# runs two times. The script removes nothing and changes no other key.
#   block-local-checks.sh, confirm-git-writes.sh   the tool Bash
#   guard-plaintext-secrets.sh                     the tools Bash, Write, Edit and MultiEdit
# Exit 1: the file is absent or is not JSON, or jq is absent and a registration is missing.
set -euo pipefail
settings=".claude/settings.json"
guards="block-local-checks.sh confirm-git-writes.sh guard-plaintext-secrets.sh"
[ -f "$settings" ] || { echo "icm: $settings is missing: the guards are not registered" >&2; exit 1; }
if ! command -v jq >/dev/null 2>&1; then
  for g in $guards; do
    grep -qF ".claude/hooks/$g" "$settings" \
      || { echo "icm: jq is not installed, and $settings does not register $g" >&2; exit 1; }
  done
  exit 0
fi

# registered(g; t): an entry whose matcher has the tool t (or all tools) calls the guard g.
# add(g; tools): one entry for the tools that have no registration of g. It goes into the
# entry that has exactly that matcher, else into a new entry.
program='
def command($g): "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/" + $g + "\"";
def covers($t): (.matcher // "") as $m
  | ($m == "" or $m == "*" or $m == ".*" or (($m | split("|") | index($t)) != null));
def registered($g; $t): any(.hooks.PreToolUse[]?;
  covers($t) and any(.hooks[]?; (.command // "") | contains(".claude/hooks/" + $g)));
def add($g; $tools):
  ([$tools[] as $t | select(registered($g; $t) | not) | $t] | join("|")) as $m
  | if $m == "" then . else
      {type: "command", command: command($g)} as $hook
      | (.hooks.PreToolUse // []) as $list
      | ($list | map(.matcher == $m) | index(true)) as $i
      | .hooks.PreToolUse = (if $i == null then $list + [{matcher: $m, hooks: [$hook]}]
          else ($list | .[$i].hooks += [$hook]) end)
    end;
add("block-local-checks.sh"; ["Bash"])
| add("confirm-git-writes.sh"; ["Bash"])
| add("guard-plaintext-secrets.sh"; ["Bash"])
| add("guard-plaintext-secrets.sh"; ["Write", "Edit", "MultiEdit"])
'
new="$(jq "$program" "$settings")" \
  || { echo "icm: $settings is not JSON: the guards are not registered" >&2; exit 1; }
[ "$(jq -c . "$settings")" != "$(jq -c . <<<"$new")" ] || exit 0
printf '%s\n' "$new" > "$settings"
echo "icm: registered the repo guards in $settings. Commit the file."
