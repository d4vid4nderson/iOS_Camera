#!/usr/bin/env bash
# Pick the newest non-beta Xcode 26.x on the GitHub macOS runner.
# App Store Connect requires apps to be built with the iOS 26 SDK or later.
set -euo pipefail
XCODE=$(ls -d /Applications/Xcode_26*.app 2>/dev/null | grep -vi beta | sort -V | tail -1 || true)
if [ -z "$XCODE" ]; then
  echo "::error::No Xcode 26 found on this runner. Installed:"
  ls -d /Applications/Xcode*.app
  exit 1
fi
sudo xcode-select -s "$XCODE"
echo "Using $XCODE"
xcodebuild -version
