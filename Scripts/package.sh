#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
export NOTCHAGENT_BUILD_DIR="${NOTCHAGENT_BUILD_DIR:-/private/tmp/NotchAgent-build-$UID}"
bash "$project_dir/Scripts/build.sh"
app="$NOTCHAGENT_BUILD_DIR/DerivedData/Build/Products/Release/NotchAgent.app"
codesign --verify --deep --strict "$app"
mkdir -p "$project_dir/Dist"
if [ -e "$project_dir/Dist/NotchAgent.app" ]; then
  printf 'Dist/NotchAgent.app already exists. Move it aside before packaging a new build.\n' >&2
  exit 1
fi
ditto --norsrc --noextattr "$app" "$project_dir/Dist/NotchAgent.app"
# iCloud-backed Desktop may attach Finder metadata to new bundles.
# Strip only this display metadata from our generated app, never quarantine flags.
xattr -dr com.apple.FinderInfo "$project_dir/Dist/NotchAgent.app" 2>/dev/null || true
# iCloud can re-attach FinderInfo at any time, which only --strict rejects. The strict check
# ran on the build product above; here confirm the copy's code and resources are intact.
codesign --verify --deep "$project_dir/Dist/NotchAgent.app"
# Archive the clean build product, not the iCloud-backed copy.
ditto -c -k --norsrc --noextattr --keepParent "$app" "$project_dir/Dist/NotchAgent-0.1.0-macOS.zip"
printf '\nPackaged in %s/Dist (local ad-hoc signature, not notarized).\n' "$project_dir"
