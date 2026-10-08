#!/bin/sh
# Wraps a built .xctest bundle into a signed <Name>-Runner.app, made from Xcode's XCTRunner
# template the way Xcode wraps UI test bundles, and zips it as an IPA the device farm agent
# can install and run on an iPhone without Xcode.
#
# Usage: scripts/package-xctest.sh <bundle.xctest> <out-dir> <signing-identity> <profile.mobileprovision>
#
# Frameworks built next to the .xctest (for example Countly.framework) are embedded in the
# bundle's own Frameworks folder, which it already searches through @loader_path/Frameworks.
# XCTest itself comes from the developer disk image on the phone.
set -eu

XCTEST=${1:?xctest bundle}
OUT=${2:?output directory}
IDENTITY=${3:?signing identity}
PROFILE=${4:?provisioning profile}

TEMPLATE="$(xcode-select -p)/Platforms/iPhoneOS.platform/Developer/Library/Xcode/Agents/XCTRunner.app"
NAME=$(basename "$XCTEST" .xctest)
TEST_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$XCTEST/Info.plist")
RUNNER_ID="$TEST_ID.xctrunner"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

security cms -D -i "$PROFILE" > "$WORK/profile.plist"
TEAM=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$WORK/profile.plist")

APP="$WORK/Payload/$NAME-Runner.app"
mkdir -p "$WORK/Payload"
cp -R "$TEMPLATE" "$APP"
rm -f "$APP/RunnerEntitlements.plist"
mv "$APP/XCTRunner" "$APP/$NAME-Runner"
# An arm64e runner process cannot load an arm64-only test bundle, so match the bundle.
TEST_BINARY="$XCTEST/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$XCTEST/Info.plist")"
case " $(lipo -archs "$TEST_BINARY") " in
  *" arm64e "*) ;;
  *) lipo "$APP/$NAME-Runner" -thin arm64 -output "$APP/$NAME-Runner" ;;
esac
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleExecutable $NAME-Runner" \
  -c "Set :CFBundleIdentifier $RUNNER_ID" \
  -c "Set :CFBundleName $NAME-Runner" \
  "$APP/Info.plist"
cp "$PROFILE" "$APP/embedded.mobileprovision"

mkdir -p "$APP/PlugIns"
cp -R "$XCTEST" "$APP/PlugIns/"
BUNDLE="$APP/PlugIns/$NAME.xctest"
mkdir -p "$BUNDLE/Frameworks"
for framework in "$(dirname "$XCTEST")"/*.framework; do
  [ -e "$framework" ] && cp -R "$framework" "$BUNDLE/Frameworks/"
done

cat > "$WORK/entitlements.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>application-identifier</key><string>$TEAM.$RUNNER_ID</string>
  <key>com.apple.developer.team-identifier</key><string>$TEAM</string>
  <key>get-task-allow</key><true/>
</dict>
</plist>
PLIST

find "$BUNDLE/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) \
  -exec codesign --force --timestamp=none --sign "$IDENTITY" {} \;
codesign --force --timestamp=none --sign "$IDENTITY" "$BUNDLE"
codesign --force --timestamp=none --sign "$IDENTITY" --entitlements "$WORK/entitlements.plist" "$APP"

mkdir -p "$OUT"
(cd "$WORK" && zip -qry "$NAME-Runner.ipa" Payload)
mv "$WORK/$NAME-Runner.ipa" "$OUT/"
echo "$OUT/$NAME-Runner.ipa ($RUNNER_ID)"
