#!/bin/bash
# Build hushpen, install it as ~/Applications/hushpen.app, download the speech
# model if needed and start the login service. Safe to run again after changes.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$HOME/Applications/hushpen.app"
BIN="$APP/Contents/MacOS/hushpen"

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
    echo "hushpen needs a Mac with Apple silicon (M1 or newer)."
    exit 1
fi
if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 14 ]; then
    echo "hushpen needs macOS 14 or newer."
    exit 1
fi
if ! xcrun swift --version >/dev/null 2>&1; then
    echo "Swift is missing. Install Xcode or the Command Line Tools (xcode-select --install) and run this again."
    exit 1
fi
SWIFT_VERSION=$(xcrun swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -1)
if ! awk -v v="$SWIFT_VERSION" 'BEGIN { split(v, p, "."); exit !(p[1] > 6 || (p[1] == 6 && p[2] >= 2)) }'; then
    echo "Swift $SWIFT_VERSION is too old; 6.2 or newer is needed. Update Xcode or the Command Line Tools."
    exit 1
fi

echo "==> Building"
./scripts/build.sh >/dev/null
if ! ./scripts/audit-sdk-network.sh >/dev/null; then
    ./scripts/audit-sdk-network.sh
    exit 1
fi

echo "==> Installing $APP"
./scripts/make-app.sh >/dev/null

if "$BIN" --verify | grep -q "(matches)"; then
    echo "==> Model already installed"
else
    echo "==> Downloading the speech model"
    "$BIN" --download-model
fi

echo "==> Starting the service"
"$BIN" --install-agent >/dev/null
HOTKEY=$("$BIN" --verify | sed -nE 's/^Hotkey: +//p')
FN_NOTE=""
if [ "$HOTKEY" = "fn" ] && [ "$(defaults read com.apple.HIToolbox AppleFnUsageType 2>/dev/null || echo 1)" != "0" ]; then
    FN_NOTE="
Your Fn (🌐) key currently opens a macOS function. Set System Settings →
Keyboard → \"Press 🌐 key to\" → Do Nothing, or choose another shortcut below.
"
fi

cat <<EOF

hushpen is installed and running.

Two permissions are still needed, and macOS only lets you grant them yourself:
  1. Microphone: press your shortcut ($HOTKEY) once; macOS asks. Allow it.
  2. Pasting: System Settings → Privacy & Security → Accessibility → turn on hushpen.
     Then restart the service:
       launchctl kickstart -k gui/\$(id -u)/io.github.yerstev.hushpen.agent

Use: press $HOTKEY, speak, press it again. The text is pasted at your cursor.
$FN_NOTE
Change the shortcut with: $BIN --hotkey cmd+shift+d   (or f18, fn)
EOF
