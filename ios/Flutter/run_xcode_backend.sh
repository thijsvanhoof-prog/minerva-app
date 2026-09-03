#!/bin/sh
# Resolve a local Flutter SDK when Generated.xcconfig still points at another Mac
# (Xcode Cloud regenerates that file; local Xcode does not).
set -e

export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/flutter/bin:${PATH}"

backend="${FLUTTER_ROOT:-}/packages/flutter_tools/bin/xcode_backend.sh"

if [ ! -f "$backend" ]; then
  echo "note: FLUTTER_ROOT is stale or missing (${FLUTTER_ROOT:-unset}); resolving local Flutter SDK." >&2

  if ! command -v flutter >/dev/null 2>&1; then
    echo "error: Flutter SDK not found. Install Flutter and run: flutter pub get" >&2
    exit 1
  fi

  flutter_bin="$(command -v flutter)"
  while [ -L "$flutter_bin" ]; do
    link="$(readlink "$flutter_bin")"
    case "$link" in
      /*) flutter_bin="$link" ;;
      *) flutter_bin="$(cd "$(dirname "$flutter_bin")" && pwd)/$link" ;;
    esac
  done

  FLUTTER_ROOT="$(cd "$(dirname "$flutter_bin")/.." && pwd)"
  export FLUTTER_ROOT
  export FLUTTER_APPLICATION_PATH="$(cd "${SRCROOT}/.." && pwd)"
  if [ -f "${FLUTTER_APPLICATION_PATH}/.dart_tool/package_config.json" ]; then
    export PACKAGE_CONFIG="${FLUTTER_APPLICATION_PATH}/.dart_tool/package_config.json"
  fi

  backend="${FLUTTER_ROOT}/packages/flutter_tools/bin/xcode_backend.sh"
  echo "note: using FLUTTER_ROOT=${FLUTTER_ROOT}" >&2
fi

if [ ! -f "$backend" ]; then
  echo "error: xcode_backend.sh not found at ${backend}" >&2
  exit 1
fi

exec /bin/sh "$backend" "$@"
