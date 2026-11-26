#!/bin/bash
# The public API of the SDK on each platform it supports, as Swift sees its Objective-C headers, written by Apple's
# swift-api-digester to api/<platform>/<module>.json. Countly is the module SwiftPM builds from include/;
# CountlyNotificationService is the header apps add to their notification service extension, or take from the
# Countly/NotificationService pod. The headers declare some API for some platforms only, so every platform has its own
# files.
#   bash .github/scripts/public-api.sh check    fails when the headers no longer match the api/ files
#   bash .github/scripts/public-api.sh update   rewrites the api/ files after a deliberate change; add a CHANGELOG.md line
# The files depend on the Xcode version, so write them with the Xcode the Public API workflow selects, or take the files
# that workflow uploads when the check fails. In check mode, PUBLIC_API_OUT names a folder for the files this Xcode
# wrote, and on GitHub the job summary lists what changed.
set -euo pipefail
cd "$(dirname "$0")/../.."
mode=${1:-check}
case "$mode" in
    check|update) ;;
    *)
        echo "usage: bash $0 check|update" >&2
        exit 2
        ;;
esac
modules="Countly CountlyNotificationService"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcode=$(xcodebuild -version | sed -n 1p)
status=0

cat > "$work/module.modulemap" <<EOF
module Countly {
    umbrella header "$PWD/include/Countly.h"
    export *
}

module CountlyNotificationService {
    header "$PWD/CountlyNotificationService.h"
    export *
}
EOF

# Prints what differs between a recorded API file and the API the headers declare now: the changes swift-api-digester
# finds breaking, then the declarations only the headers have. On GitHub the job summary gets the same lines.
#   $1 the platform's SDK
#   $2 the recorded file
#   $3 the file written from the headers
#   $4 the module and platform, for the summary's heading
report() {
    local breaking added text
    rm -f "$work/breaking.txt" "$work/reverse.txt"
    xcrun --sdk "$1" swift-api-digester -diagnose-sdk -input-paths "$2" -input-paths "$3" -o "$work/breaking.txt" >/dev/null 2>&1 || true
    xcrun --sdk "$1" swift-api-digester -diagnose-sdk -input-paths "$3" -input-paths "$2" -o "$work/reverse.txt" >/dev/null 2>&1 || true
    if [ ! -f "$work/breaking.txt" ] || [ ! -f "$work/reverse.txt" ]; then
        text="swift-api-digester could not compare the files; the difference below shows what changed."
    else
        breaking=$(grep -v -e '^/\*' -e '^$' "$work/breaking.txt" | sed 's/^/- /' || true)
        # Compared the other way round, a declaration only the headers have is one the digester calls removed.
        added=$(awk '/^\/\*/ { removed = ($0 == "/* Removed Decls */"); next } removed && NF { sub(/ has been removed$/, ""); print "+ " $0 }' "$work/reverse.txt")
        text="Breaks apps that use it (start the CHANGELOG.md line with \"! Minor breaking change !\"):
${breaking:-  nothing}
New declarations:
${added:-  none}"
    fi
    echo "$text"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        printf '### Public API changes: %s\n```\n%s\n```\n' "$4" "$text" >> "$GITHUB_STEP_SUMMARY"
    fi
}

# Writes api/<platform>/<module>.json for each module, or compares it with the public API the headers declare on that
# platform.
#   $1 the platform's folder in api/
#   $2 the platform's SDK
#   $3 the target, at the lowest version of the platform that Package.swift supports
platform() {
    local module file dumped
    mkdir -p "$work/$1"
    for module in $modules; do
        file="api/$1/$module.json"
        dumped="$work/$1/$module.json"
        xcrun --sdk "$2" swift-api-digester -dump-sdk -module "$module" -I "$work" -I include \
            -sdk "$(xcrun --sdk "$2" --show-sdk-path)" -target "$3" \
            -avoid-location -avoid-tool-args -abort-on-module-fail -o "$dumped"
        if [ "$mode" = update ]; then
            mkdir -p "api/$1"
            cp "$dumped" "$file"
            echo "public-api, wrote $file with $xcode"
            continue
        fi
        if [ -f "$file" ] && cmp -s "$file" "$dumped"; then
            echo "public-api, the public API of $module on $1 is the one $file records ($xcode)"
            continue
        fi
        status=1
        echo "::error file=$file::The public API of $module on $1 differs from $file. If the change is deliberate, run bash .github/scripts/public-api.sh update with $xcode, or take the files the Public API workflow uploads, and add a CHANGELOG.md line."
        if [ -f "$file" ]; then
            report "$2" "$file" "$dumped" "$module on $1"
            diff -u "$file" "$dumped" | head -200 || true
        fi
        if [ -n "${PUBLIC_API_OUT:-}" ]; then
            mkdir -p "$PUBLIC_API_OUT/$1"
            cp "$dumped" "$PUBLIC_API_OUT/$1/"
        fi
    done
}

platform ios iphonesimulator arm64-apple-ios15.0-simulator
platform macos macosx arm64-apple-macos12.0
platform tvos appletvsimulator arm64-apple-tvos15.0-simulator
platform watchos watchsimulator arm64-apple-watchos9.0-simulator
platform visionos xrsimulator arm64-apple-xros1.0-simulator
exit $status
