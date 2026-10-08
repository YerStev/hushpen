#!/bin/bash
# Assemble and verify a local app before replacing a recognized existing bundle.
# Linked SDK code is included; model weights are not.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-$HOME/Applications/hushpen.app}"
BINARY=".build/release/hushpen"

if [ ! -x "$BINARY" ]; then
    echo "ERROR: $BINARY is missing. Run ./scripts/build.sh first."
    exit 1
fi

if [ "$(basename "$APP")" != "hushpen.app" ] || [ -L "$APP" ]; then
    echo "ERROR: The destination must be a non-symlink folder named hushpen.app."
    exit 1
fi
if [ -e "$APP" ] && ! /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null | grep -qx 'io.github.yerstev.hushpen'; then
    echo "ERROR: The destination is not a recognized hushpen app. It will not be replaced."
    exit 1
fi
DESTINATION="$APP"
mkdir -p "$(dirname "$DESTINATION")"
STAGING=$(mktemp -d "$(dirname "$DESTINATION")/.hushpen-build.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/hushpen.app"
echo "Creating $DESTINATION …"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>io.github.yerstev.hushpen</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleName</key>
    <string>hushpen</string>
    <key>CFBundleDisplayName</key>
    <string>hushpen</string>
    <key>CFBundleExecutable</key>
    <string>hushpen</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.0</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <!-- Background app; setup explicitly enables its window. -->
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>hushpen records only when you start a dictation and processes speech on this Mac.</string>
</dict>
</plist>
PLIST

cp -X "$BINARY" "$APP/Contents/MacOS/hushpen"

mkdir -p "$APP/Contents/Resources"

cp -X LICENSE "$APP/Contents/Resources/LICENSE-hushpen.txt"
cp -X .build/checkouts/desert-ant-core/LICENSE.md "$APP/Contents/Resources/LICENSE-desert-ant-core.md"
cp -X .build/checkouts/swift-numerics/LICENSE.txt "$APP/Contents/Resources/LICENSE-swift-numerics.txt"
cp -X docs/PRIVACY.md "$APP/Contents/Resources/PRIVACY.md"

codesign --force --deep --sign "${HUSHPEN_SIGN_IDENTITY:--}" --identifier io.github.yerstev.hushpen "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "^Identifier|^Signature|flags"

codesign --verify --deep --strict "$APP"
if [ -d "$DESTINATION" ]; then mv "$DESTINATION" "$STAGING/previous.app"; fi
if ! mv "$APP" "$DESTINATION"; then
    if [ -d "$STAGING/previous.app" ]; then mv "$STAGING/previous.app" "$DESTINATION"; fi
    exit 1
fi
APP="$DESTINATION"
echo
echo "Ready: $APP"
echo "Open the app in Finder. The assistant will guide you through setup."
