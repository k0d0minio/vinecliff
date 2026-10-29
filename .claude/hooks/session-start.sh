#!/usr/bin/env bash
# session-start.sh — SessionStart hook, build only. It prints the board of .icm/intake/: each
# open epic with its count and its next stub (the lowest sequence with no blocked: line), the
# triage count by lane, the open setup acts of setup/ by slug, the ## Order list of README.md as
# it is, the started tickets, the total.
# A started ticket has a branch <slug> or triage/<slug> in refs/heads or refs/remotes/origin,
# and its stub is open in this tree, or in _done/ with its branch checked out. It reads files
# and git for-each-ref only, never the network. Silent with no open stub and no open setup act.
# Always exits 0.
set -u
root="${CLAUDE_PROJECT_DIR:-.}"
intake="$root/.icm/intake"
[ -d "$intake" ] || exit 0
refs="" here="" started="" total=0 epics="" t=0 lanes="" acts=""
if [ -e "$root/.git" ] && command -v git >/dev/null 2>&1; then
  refs="$(git -C "$root" for-each-ref --format='%(refname)' refs/heads refs/remotes/origin 2>/dev/null \
    | sed -e 's#^refs/heads/##' -e 's#^refs/remotes/origin/##')"
  here="$(git -C "$root" for-each-ref --format='%(HEAD)%(refname:short)' refs/heads 2>/dev/null | sed -n 's/^\*//p')"
fi
# started <ticket> <branch> <stub>: an open stub with a branch, or a done stub on its branch.
started() {
  case "$3" in
    */_done/*) [ "$2" = "$here" ] || return 0 ;;
    *) [ -n "$refs" ] && grep -qxF -- "$2" <<<"$refs" || return 0 ;;
  esac
  started+="  $1 on branch $2"$'\n'
}
for d in "$intake"/*/; do
  name="$(basename "$d")"
  case "$name" in triage | setup | _done) continue ;; esac
  n=0 next="" best=999999999
  for f in "$d"*.md "$d"_done/*.md; do
    slug="$(basename "$f" .md)"
    [ -e "$f" ] && [ "$slug" != breakdown ] || continue
    started "$name/$slug" "$slug" "$f"
    case "$f" in */_done/*) continue ;; esac
    n=$((n + 1))
    grep -qE '^- *blocked:' "$f" && continue
    s="$(grep -m1 -E '^- *sequence:' "$f" | grep -oE '[0-9]+' | head -n1)"
    [ "${s:-999999}" -lt "$best" ] && best="${s:-999999}" next="$slug"
  done
  [ "$n" -gt 0 ] || continue
  total=$((total + n))
  epics+="  epic $name: $n open, next: ${next:-none, each open stub is blocked}"$'\n'
done
for f in "$intake"/triage/*.md "$intake"/triage/_done/*.md; do
  [ -e "$f" ] || continue
  started "triage/$(basename "$f" .md)" "triage/$(basename "$f" .md)" "$f"
  case "$f" in */_done/*) continue ;; esac
  t=$((t + 1)) total=$((total + 1))
  l="$(grep -m1 -E '^- *lane:' "$f" | sed -E 's/^- *lane: *//; s/[[:space:]].*//')"
  lanes+="${l:-no-lane}"$'\n'
done
# A setup stub is a person's act, not a ticket: it counts apart from the total.
for f in "$intake"/setup/*.md; do
  [ -e "$f" ] || continue
  acts+="${acts:+, }$(basename "$f" .md)"
done
[ "$total" -gt 0 ] || [ -n "$acts" ] || exit 0
echo "The board of .icm/intake/ (read-only):"
printf '%s' "$epics"
[ "$t" -gt 0 ] && echo "  triage: $t open ($(printf '%s' "$lanes" | sort | uniq -c | awk '{printf "%s%s %s", s, $2, $1; s=", "}'))"
[ -n "$acts" ] && echo "  setup: open acts for a person: $acts (.icm/intake/setup/)"
[ -f "$intake/README.md" ] && awk '/^## /{p=($0=="## Order")} p && NF' "$intake/README.md"
[ -n "$started" ] && printf 'Started tickets:\n%s' "$started"
echo "$total open stubs in total. Planning lives in .icm/intake/, never in a loose TODO.md."
exit 0
