#!/bin/bash
# Build hushpen, install it as ~/Applications/hushpen.app, download the speech
# model if needed and start the login service. Safe to run again after changes.
# HUSHPEN_CLEANUP=1 also sets up the optional text cleanup (5.2 GB model).
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

if [ "${HUSHPEN_CLEANUP:-0}" = "1" ]; then
    MEMORY_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
    FREE_GB=$(df -g "$HOME" | awk 'NR==2 { print $4 }')
    if [ "$MEMORY_GB" -lt 16 ]; then
        echo "==> Skipping text cleanup: it needs 16 GB of memory, this Mac has $MEMORY_GB GB."
    elif "$BIN" --verify | grep -q "^Cleanup model: *not registered"; then
        if [ "$FREE_GB" -lt 8 ]; then
            echo "==> Skipping text cleanup: the model needs 5.2 GB, only $FREE_GB GB are free."
        else
            echo "==> Downloading the cleanup model (5.2 GB)"
            "$BIN" --cleanup-model download
            "$BIN" --cleanup on >/dev/null
        fi
    else
        echo "==> Cleanup model already installed"
        "$BIN" --cleanup on >/dev/null
    fi
fi

echo "==> Starting the service"
"$BIN" --install-agent >/dev/null
# A running service picks up new settings only after a restart.
launchctl kickstart -k "gui/$(id -u)/io.github.yerstev.hushpen.agent" >/dev/null 2>&1 || true
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
