#!/usr/bin/env bash
# Build the app without the Control Center / Lock Screen camera control: drops the
# extension's embed phase and dependency from the app target, so archiving builds the
# app alone. Used when there's no PROVISIONING_PROFILE_CONTROLS secret yet, so TestFlight
# uploads keep working (without the control) until that profile is added.
set -euo pipefail
project="${1:-RetroCam.xcodeproj/project.pbxproj}"
perl -i -ne 'print unless m{^\s*AA0000000000000000000017 /\* Embed Foundation Extensions \*/,$} || m{^\s*AA000000000000000000001A /\* PBXTargetDependency \*/,$}' "$project"
if grep -qE '^\s*AA0000000000000000000017 /\* Embed Foundation Extensions \*/,$|^\s*AA000000000000000000001A /\* PBXTargetDependency \*/,$' "$project"; then
  echo "::error::Couldn't take the camera control out of the app target."; exit 1
fi
echo "Building without the camera control."
