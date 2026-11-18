#!/usr/bin/env bash
# dispatch.sh — the one entry for all hooks. .claude/settings.json calls it with an event name.
# To add a hook, change this file in the blueprint. The pointer in settings.json stays the same.
# A hook must not break a session: an unknown event does nothing.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
  session-start) exec bash "$here/session-start.sh" ;;
  user-prompt) exec bash "$here/route-request.sh" ;;
  pre-tool-use) exec bash "$here/guard-system.sh" ;;
  stop) exec bash "$here/wrap-reminder.sh" ;;
esac
exit 0
