#!/bin/bash
set -euo pipefail

echo "== Xcode Cloud: iOS pre-xcodebuild =="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_DIR/.." && pwd)"

cd "$REPO_ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found on PATH. Installing stable Flutter SDK..."
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi

if [ ! -f .env ]; then
  echo "Missing .env. ci_post_clone should create it from Xcode Cloud environment variables."
  exit 1
fi

flutter --version
flutter pub get

cd "$IOS_DIR"
pod install

echo "iOS pre-xcodebuild done."
