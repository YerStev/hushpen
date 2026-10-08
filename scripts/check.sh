#!/bin/bash
# Build, policy and packaging checks. No microphone access, no changes to your setup.
set -euo pipefail
cd "$(dirname "$0")/.."
for script in scripts/*.sh Setup.command; do bash -n "$script"; done
# Policy: usage reporting stays on (model license), no network listener,
# English source text.
python3 - <<'CHECK_POLICY'
from pathlib import Path
import re
for file in Path("Sources/hushpen").glob("*.swift"):
    text = file.read_text()
    assert not re.search(r"(?:usageDisabled|DAL_USAGE_DISABLED)\s*=", text), file
    assert not re.search(r"\bsocket\(|\blisten\(", text), file
    assert not re.search(r"[äöüÄÖÜß]", text), file
assert "flushAndWait()" in Path("Sources/hushpen/Telemetry.swift").read_text()
CHECK_POLICY
swift build -c release
./scripts/audit-sdk-network.sh
BINARY="$PWD/.build/release/hushpen"
"$BINARY" --version | grep -q 'Powered by Desert Ant Labs'
"$BINARY" --help | grep -q -- '--download-model'
CHECK_TMP=$(mktemp -d "${TMPDIR:-/tmp}/hushpen-check.XXXXXX")
trap 'rm -rf "$CHECK_TMP"' EXIT
expect_code() {
    local expected="$1"
    shift
    local actual=0
    "$@" >"$CHECK_TMP/output.txt" 2>&1 || actual=$?
    if [ "$actual" -ne "$expected" ]; then
        echo "ERROR: Expected exit code $expected, got $actual: $*"
        cat "$CHECK_TMP/output.txt"
        exit 1
    fi
}
expect_code 2 "$BINARY" --unknown
expect_code 2 "$BINARY" --toggle
expect_code 2 "$BINARY" --transcribe-file
expect_code 2 "$BINARY" --setup unexpected
expect_code 3 "$BINARY" --set-model "$CHECK_TMP/missing"
mkdir "$CHECK_TMP/incomplete-model"
printf '{"unrelated":true}' > "$CHECK_TMP/incomplete-model/meta.json"
expect_code 3 "$BINARY" --set-model "$CHECK_TMP/incomplete-model"
grep -q 'vocab.json' "$CHECK_TMP/output.txt"
mkdir "$CHECK_TMP/keep-me"
touch "$CHECK_TMP/keep-me/sentinel"
expect_code 1 ./scripts/make-app.sh "$CHECK_TMP/keep-me"
test -f "$CHECK_TMP/keep-me/sentinel"
mkdir "$CHECK_TMP/hushpen.app"
touch "$CHECK_TMP/hushpen.app/sentinel"
expect_code 1 ./scripts/make-app.sh "$CHECK_TMP/hushpen.app"
test -f "$CHECK_TMP/hushpen.app/sentinel"
rmdir_dummy="$CHECK_TMP/hushpen.app"
rm "$rmdir_dummy/sentinel"
rmdir "$rmdir_dummy"
./scripts/make-app.sh "$CHECK_TMP/hushpen.app"
codesign --verify --deep --strict "$CHECK_TMP/hushpen.app"
plutil -lint "$CHECK_TMP/hushpen.app/Contents/Info.plist"
for notice in LICENSE-hushpen.txt LICENSE-desert-ant-core.md LICENSE-swift-numerics.txt PRIVACY.md; do
    test -s "$CHECK_TMP/hushpen.app/Contents/Resources/$notice"
done
./scripts/make-app.sh "$CHECK_TMP/hushpen.app"
codesign --verify --deep --strict "$CHECK_TMP/hushpen.app"
echo "All checks passed."
