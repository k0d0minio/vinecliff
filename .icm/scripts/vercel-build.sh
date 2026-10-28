#!/usr/bin/env bash
# vercel-build.sh
# The build's vercel-build. It migrates the database when this deployment owns it, then runs the
# build command. package.json names it once and its line never changes:
#   "vercel-build": "bash .icm/scripts/vercel-build.sh next build"
# (from a package below the root: "bash ../.icm/scripts/vercel-build.sh next build").
# The rule is .icm/database/CONTEXT.md § The migration rule. The blueprint owns this file:
# copier update changes it.
set -euo pipefail

[ "$#" -gt 0 ] || { echo "vercel-build.sh: give the build command, for example: next build" >&2; exit 2; }

owner="uat"
target="${VERCEL_TARGET_ENV:-}"
case "${npm_config_user_agent:-}" in
  pnpm/*) run=(pnpm run) ;;
  yarn/*) run=(yarn run) ;;
  bun/*)  run=(bun run) ;;
  *)      run=(npm run) ;;
esac

if [ "$target" = "$owner" ] || [ "${MIGRATE_AT_BUILD:-}" = 1 ]; then
  : "${DATABASE_URL:?vercel-build.sh: DATABASE_URL is not set, so nothing can migrate}"
  echo "[vercel-build] VERCEL_TARGET_ENV=${target:-unset} MIGRATE_AT_BUILD=${MIGRATE_AT_BUILD:-unset}: migrate, verify, then build"
  DATABASE_URL="${DATABASE_URL_UNPOOLED:-$DATABASE_URL}" "${run[@]}" db:migrate
  DATABASE_URL="${DATABASE_URL_UNPOOLED:-$DATABASE_URL}" "${run[@]}" db:verify
else
  echo "[vercel-build] VERCEL_TARGET_ENV=${target:-unset}: this deployment does not own the base, so it only builds"
fi

exec "$@"
