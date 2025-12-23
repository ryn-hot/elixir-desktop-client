#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR=${1:-build}
APP_PATH=${2:-"${ROOT_DIR}/${BUILD_DIR}/elixir-client.app"}

if [[ ! -d "$APP_PATH" ]]; then
  FOUND=$(find "${ROOT_DIR}/${BUILD_DIR}" -maxdepth 2 -name "*.app" -type d | head -n 1 || true)
  if [[ -n "$FOUND" ]]; then
    APP_PATH="$FOUND"
  fi
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found. Build first, or pass the .app path." >&2
  echo "Example: ./scripts/package_macos.sh build /path/to/elixir-client.app" >&2
  exit 1
fi

QT_PREFIX="$(brew --prefix qt@6 2>/dev/null || true)"
if [[ -n "$QT_PREFIX" && -x "$QT_PREFIX/bin/macdeployqt" ]]; then
  MACDEPLOYQT="$QT_PREFIX/bin/macdeployqt"
elif command -v macdeployqt >/dev/null 2>&1; then
  MACDEPLOYQT="$(command -v macdeployqt)"
else
  echo "macdeployqt not found. Install Qt 6 and ensure macdeployqt is on PATH." >&2
  exit 1
fi

"$MACDEPLOYQT" "$APP_PATH" -qmldir="${ROOT_DIR}/src/qml" -verbose=2

echo "Packaged: $APP_PATH"
