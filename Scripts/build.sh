#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
build_dir="${NOTCHAGENT_BUILD_DIR:-/private/tmp/NotchAgent-build-$UID}"
mkdir -p "$build_dir"
swift "$project_dir/Scripts/MakeIcon.swift" "$build_dir/AppIcon.iconset"
iconutil -c icns "$build_dir/AppIcon.iconset" -o "$project_dir/Resources/AppIcon.icns"
xcodebuild -project "$project_dir/NotchAgent.xcodeproj" -scheme NotchAgent \
  -configuration Release -derivedDataPath "$build_dir/DerivedData" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY=- build
printf '\nBuilt: %s\n' "$build_dir/DerivedData/Build/Products/Release/NotchAgent.app"
