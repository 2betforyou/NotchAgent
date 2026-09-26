#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
build_dir="${NOTCHAGENT_BUILD_DIR:-/private/tmp/NotchAgent-build-$UID}"
xcodebuild -project "$project_dir/NotchAgent.xcodeproj" -scheme NotchAgent \
  -configuration Debug -derivedDataPath "$build_dir/DerivedData" \
  -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY=- test
