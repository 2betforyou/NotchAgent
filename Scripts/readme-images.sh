#!/bin/bash
# Regenerates the README screenshots in docs/images from the real views with sample data.
# Uses a scratch settings store and support folder, so your own settings are never touched.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
export TEST_RUNNER_NOTCHAGENT_README_DIR="$project_dir/docs/images"
export TEST_RUNNER_NOTCHAGENT_SUPPORT_DIR="$scratch/support"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
build_dir="${NOTCHAGENT_BUILD_DIR:-/private/tmp/NotchAgent-build-$UID}"
xcodebuild -project "$project_dir/NotchAgent.xcodeproj" -scheme NotchAgent -configuration Debug \
  -derivedDataPath "$build_dir/DerivedData" -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY=- \
  -only-testing:NotchAgentTests/ReadmeImagesTests test | grep -E "passed|failed|error:" || true
ls -l "$project_dir/docs/images"/*
