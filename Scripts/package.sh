#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
export NOTCHAGENT_BUILD_DIR="${NOTCHAGENT_BUILD_DIR:-/private/tmp/NotchAgent-build-$UID}"
bash "$project_dir/Scripts/build.sh"
app="$NOTCHAGENT_BUILD_DIR/DerivedData/Build/Products/Release/NotchAgent.app"
codesign --verify --deep --strict "$app"
mkdir -p "$project_dir/Dist"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
archive="$project_dir/Dist/NotchAgent-$version-macOS.zip"
if [ -e "$archive" ]; then
  printf '%s already exists. Move it aside before packaging a new build.\n' "$archive" >&2
  exit 1
fi
# Archive the clean build product, not the iCloud-backed live app in Dist/.
ditto -c -k --norsrc --noextattr --keepParent "$app" "$archive"
shasum -a 256 "$archive" > "$archive.sha256"
printf '\nPackaged %s (local ad-hoc signature, not notarized).\n' "$archive"
