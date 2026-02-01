#!/bin/bash
set -euo pipefail

echo "== Xcode Cloud: post-clone =="
echo "Working directory: $(pwd)"

# Ensure Flutter is available (Xcode Cloud images may not have it preinstalled).
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found on PATH. Installing stable Flutter SDK..."
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi

flutter --version

echo "Running flutter pub get..."
flutter pub get

echo "Installing CocoaPods dependencies..."
cd ios
pod --version
pod install
cd ..

echo "Post-clone done."

