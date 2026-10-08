#!/bin/bash
# Fail when a pinned SDK update introduces unreviewed networking surfaces.
# This is a source audit, not an OS network isolation guarantee.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

CHECKOUT=".build/checkouts/desert-ant-core"
BASELINE="scripts/sdk-network-baseline.txt"
ALLOWED_MODULES="Usage ModelStore PlatformSupport"
SYMBOLS='URLSession|HTTPClient|URLRequest|sendBeacon|NWConnection|CFSocket|socket\('

fail=0
note() { printf '%s\n' "$*"; }

if [ ! -d "$CHECKOUT" ]; then
    note "ERROR: SDK checkout missing at $CHECKOUT."
    note "        Run 'swift build' first to resolve dependencies."
    exit 1
fi

note "SDK network surface audit"
note "=================="

if [ -f Package.resolved ]; then
    pinned=$(python3 - <<'PY'
import json
try:
    pins = json.load(open("Package.resolved")).get("pins", [])
except Exception:
    raise SystemExit(0)
for p in pins:
    if p.get("identity") == "desert-ant-core":
        st = p.get("state", {})
        print("%s %s" % (st.get("version", "?"), st.get("revision", "?")[:12]))
PY
)
    note "Pinned:  desert-ant-core ${pinned:-UNKNOWN}"
    if [ -z "$pinned" ]; then
        note "ERROR: desert-ant-core is not pinned in Package.resolved."
        fail=1
    fi
else
    note "ERROR: Package.resolved is missing; the dependency revision is not pinned."
    fail=1
fi

current=$(cd "$CHECKOUT" && for f in $(grep -rlE "$SYMBOLS" Sources 2>/dev/null); do
    if grep -vE '^[[:space:]]*//' "$f" | grep -qE "$SYMBOLS"; then printf '%s\n' "$f"; fi
done | sort)

note ""
note "Network-capable SDK files:"
if [ -z "$current" ]; then
    note "  (none)"
else
    printf '  %s\n' $current
fi

unexpected=""
for file in $current; do
    module=$(printf '%s' "$file" | cut -d/ -f2)
    case " $ALLOWED_MODULES " in
        *" $module "*) ;;
        *) unexpected="$unexpected $file" ;;
    esac
done

note ""
if [ -n "$unexpected" ]; then
    note "ERROR: Network code found outside the reviewed modules ($ALLOWED_MODULES):"
    printf '  %s\n' $unexpected
    note ""
    note "  Review the updated SDK and record the findings in docs/TECHNICAL.md"
    note "  before accepting a new baseline. Do not update the baseline just"
    note "  to make a failed check pass."
    fail=1
else
    note "OK: Network code is limited to the reviewed modules ($ALLOWED_MODULES)."
fi

if [ -f "$BASELINE" ]; then
    if diff_out=$(printf '%s\n' "$current" | diff -u "$BASELINE" - 2>&1); then
        note "OK: File list matches $BASELINE."
    else
        note ""
        note "ERROR: File list differs from $BASELINE:"
        printf '%s\n' "$diff_out" | sed 's/^/  /'
        fail=1
    fi
else
    note ""
    note "NOTICE: $BASELINE is missing. After review, record the baseline with:"
    note "  ./scripts/audit-sdk-network.sh --write-baseline"
    if [ "${1:-}" = "--write-baseline" ]; then
        printf '%s\n' "$current" > "$BASELINE"
        note "Written: $BASELINE"
    fi
fi

if [ "${1:-}" = "--write-baseline" ] && [ -f "$BASELINE" ]; then
    printf '%s\n' "$current" > "$BASELINE"
    note "Baseline updated: $BASELINE"
    note "WARNING: Update the baseline only after reviewing and documenting the findings."
    exit 0
fi

note ""
wire="$CHECKOUT/Sources/Usage/Wire.swift"
if [ -f "$wire" ]; then
    keys=$(grep -c '"[a-zA-Z]*", "' "$CHECKOUT/Sources/Usage/DeviceContext.swift" 2>/dev/null || echo 0)
    event_fields=$(awk '/public struct IngestEvent/,/^}/' "$wire" | grep -cE '^\s+public var ')
    note "Reporting payload: IngestEvent has $event_fields public fields (expected 5: name, deviceId, callCount, timestamp, context)."
    if [ "$event_fields" -ne 5 ]; then
        note "ERROR: The payload field count changed; review whether a new field can carry content."
        fail=1
    fi
    if grep -qE 'contextKeys[^=]*=\s*\[' "$CHECKOUT/Sources/Usage/DeviceContext.swift"; then
        note "OK: The context map uses a fixed key allowlist."
    else
        note "ERROR: Could not find the context key allowlist."
        fail=1
    fi
else
    note "ERROR: $wire is missing; the SDK structure changed."
    fail=1
fi

note ""
# The model is fetched only through the SDK's public Voz.download.
if grep -rnE '\bModelStore\b' Sources >/dev/null 2>&1; then
    note "ERROR: Application code uses ModelStore directly."
    grep -rnE '\bModelStore\b' Sources | sed 's/^/  /'
    fail=1
else
    note "OK: Application code downloads the model only through Voz.download."
fi

note ""
if [ "$fail" -eq 0 ]; then
    note "Result: passed."
else
    note "Result: FAILED."
fi
exit "$fail"
