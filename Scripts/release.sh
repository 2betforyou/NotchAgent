#!/bin/bash
# Public release: Developer ID signing, notarization, stapling, DMG, Gatekeeper checks.
#
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE=notchagent bash Scripts/release.sh
#
# One-time setup for NOTARY_PROFILE (stores an app-specific password in the keychain):
#   xcrun notarytool store-credentials notchagent --apple-id you@example.com --team-id TEAMID
#
# SKIP_NOTARIZE=1 runs every step except Apple's notary service (for rehearsing with any
# signing identity). Output goes to Release/ outside iCloud-synced metadata problems.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
build_dir="${NOTCHAGENT_BUILD_DIR:-/private/tmp/NotchAgent-build-$UID}/release"
out_dir="${NOTCHAGENT_RELEASE_DIR:-$build_dir/out}"
: "${DEVELOPER_ID:?Set DEVELOPER_ID to your 'Developer ID Application: …' identity}"
if [ "${SKIP_NOTARIZE:-0}" != 1 ]; then : "${NOTARY_PROFILE:?Set NOTARY_PROFILE (see header) or SKIP_NOTARIZE=1}"; fi
fail() { printf '\n✗ %s\n' "$1" >&2; exit 1; }
step() { printf '\n▸ %s\n' "$1"; }

security find-identity -v -p codesigning | grep -Fq "\"$DEVELOPER_ID\"" || fail "Signing identity not in keychain: $DEVELOPER_ID"
team="$(security find-certificate -c "$DEVELOPER_ID" -p | openssl x509 -noout -subject -nameopt multiline | sed -nE 's/^ *organizationalUnitName *= *([A-Z0-9]{10})$/\1/p' | head -1)"
[ -n "$team" ] || fail "Could not read the team ID from DEVELOPER_ID"
[[ "$DEVELOPER_ID" == "Developer ID Application:"* ]] || printf '⚠ %s is not a Developer ID identity; Gatekeeper will reject the result.\n' "$DEVELOPER_ID"

step "Test"
NOTCHAGENT_BUILD_DIR="${build_dir%/release}" bash "$project_dir/Scripts/test.sh" >/dev/null || fail "Tests failed"

step "Build Apple Silicon Release (Hardened Runtime, secure timestamp)"
rm -rf "$build_dir/DerivedData/Build/Products" "$out_dir"; mkdir -p "$out_dir"
xcodebuild -quiet -project "$project_dir/NotchAgent.xcodeproj" -scheme NotchAgent -configuration Release \
  -derivedDataPath "$build_dir/DerivedData" -destination 'generic/platform=macOS' \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID" DEVELOPMENT_TEAM="$team" \
  ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp" build
app="$build_dir/DerivedData/Build/Products/Release/NotchAgent.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"

step "Verify signature"
codesign --verify --deep --strict --verbose=2 "$app"
info="$(codesign -dvv "$app" 2>&1)"
grep -q "flags=.*runtime" <<<"$info" || fail "Hardened Runtime is off"
grep -q "Timestamp=" <<<"$info" || fail "No secure timestamp"
grep -q "TeamIdentifier=$team" <<<"$info" || fail "Unexpected team identifier"
if codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q "get-task-allow"; then fail "get-task-allow entitlement present (notarization would reject it)"; fi
[ "$(lipo -archs "$app/Contents/MacOS/NotchAgent")" = "arm64" ] || fail "Expected an Apple Silicon (arm64) only binary"

notarize() {
  step "Notarize $(basename "$1")"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m --output-format json > "$out_dir/notary-$(basename "$1").json" || true
  grep -q '"status" *: *"Accepted"' "$out_dir/notary-$(basename "$1").json" || {
    id="$(sed -nE 's/.*"id" *: *"([^"]+)".*/\1/p' "$out_dir/notary-$(basename "$1").json" | head -1)"
    [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" "$out_dir/notary-log.json" || true
    fail "Notarization rejected; see $out_dir/notary-log.json"
  }
}

zip="$out_dir/NotchAgent-$version-macOS.zip"
dmg="$out_dir/NotchAgent-$version.dmg"
if [ "${SKIP_NOTARIZE:-0}" != 1 ]; then
  ditto -c -k --norsrc --noextattr --keepParent "$app" "$build_dir/notarize.zip"
  notarize "$build_dir/notarize.zip"
  step "Staple app"; xcrun stapler staple "$app"; xcrun stapler validate "$app"
fi

step "Create DMG"
stage="$build_dir/dmg"; rm -rf "$stage"; mkdir -p "$stage"
ditto --norsrc --noextattr "$app" "$stage/NotchAgent.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "NotchAgent $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg"
codesign --sign "$DEVELOPER_ID" --timestamp "$dmg"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$zip"

if [ "${SKIP_NOTARIZE:-0}" != 1 ]; then
  notarize "$dmg"
  step "Staple DMG"; xcrun stapler staple "$dmg"; xcrun stapler validate "$dmg"
  step "Gatekeeper"
  spctl -a -vv -t exec "$app" 2>&1 | tee /dev/stderr | grep -q "source=Notarized Developer ID" || fail "Gatekeeper rejected the app"
  spctl -a -vv -t open --context context:primary-signature "$dmg" 2>&1 | tee /dev/stderr | grep -q "Notarized Developer ID" || fail "Gatekeeper rejected the DMG"
  # Simulate a browser download: quarantined copy must still pass.
  q="$build_dir/quarantine-check.dmg"; cp "$dmg" "$q"
  xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Safari;" "$q"
  spctl -a -vv -t open --context context:primary-signature "$q" >/dev/null 2>&1 || fail "Quarantined DMG rejected"
  rm -f "$q"
else
  printf '\n(SKIP_NOTARIZE=1: notarization, stapling and Gatekeeper acceptance were not checked)\n'
fi
( cd "$out_dir" && shasum -a 256 "$(basename "$dmg")" "$(basename "$zip")" > SHA256SUMS )
printf '\n✓ Release artifacts in %s\n' "$out_dir"; ls -l "$out_dir"
