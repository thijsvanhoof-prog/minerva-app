#!/bin/bash
set -euo pipefail

echo "== Xcode Cloud: pre-xcodebuild =="
echo "Working directory: $(pwd)"

# Ensure Flutter is available (in case post-clone didn't run for some reason).
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found on PATH. Installing stable Flutter SDK..."
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi

flutter --version

# Ensure Generated.xcconfig exists before Xcode reads ios/Flutter/*.xcconfig
echo "Ensuring iOS Flutter configs are generated..."
flutter pub get

# This generates ios/Flutter/Generated.xcconfig reliably.
flutter build ios --release --no-codesign

echo "Pre-xcodebuild done."

