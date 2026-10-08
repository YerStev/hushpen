#!/bin/bash
# A local ad-hoc signature can require permissions again after a rebuild.
# Set HUSHPEN_SIGN_IDENTITY to your own certificate to use a stable signing identity.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
echo "Building ($CONFIG) …"
swift build -c "$CONFIG"

BINARY=".build/$CONFIG/hushpen"
echo "Signing $BINARY …"
IDENTITY="${HUSHPEN_SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --identifier io.github.yerstev.hushpen "$BINARY"
codesign -dv --verbose=2 "$BINARY" 2>&1 | grep -E "Identifier|Signature|flags"

echo
echo "Ready: $BINARY"
if [ -f "$HOME/Library/LaunchAgents/io.github.yerstev.hushpen.agent.plist" ]; then
    echo "Restart the login service:"
    echo "  launchctl kickstart -k gui/$(id -u)/io.github.yerstev.hushpen.agent"
    echo "Check system permissions afterwards; a rebuild can invalidate them."
fi
