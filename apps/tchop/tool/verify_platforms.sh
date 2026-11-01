#!/usr/bin/env bash
# verify_platforms.sh — verify (and optionally regenerate) the desktop/web
# platform folders for the Tchop Flutter app.
#
# Usage (from the app root ~/workspace/tchop/apps/tchop):
#   ./tool/verify_platforms.sh            # print what WOULD run, dry-run
#   ./tool/verify_platforms.sh --run      # actually regenerate + build
#
# Regeneration command (safe: only touches web/, windows/, macos/, linux/):
#   flutter create --platforms=web,windows,macos,linux --org cm.tchop --project-name tchop .
set -euo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_ROOT"

REGEN=(flutter create --platforms=web,windows,macos,linux --org cm.tchop --project-name tchop .)
BUILDS=(web windows macos linux)

if [ "${1:-}" != "--run" ]; then
  echo "Dry run. Would execute:"
  echo
  echo "  ${REGEN[*]}"
  for p in "${BUILDS[@]}"; do
    echo "  flutter build $p"
  done
  echo
  echo "Re-run with --run to execute."
  exit 0
fi

echo "==> ${REGEN[*]}"
"${REGEN[@]}"

for p in "${BUILDS[@]}"; do
  echo "==> flutter build $p"
  flutter build "$p"
done

echo "All platform builds succeeded."
