#!/usr/bin/env bash
# Deadbolt end-to-end gate. Run from anywhere; always operates on the repo root.
# This is the deterministic gate the factory runs after every implement step.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== swift build =="
swift build

echo "== swift test =="
swift test

BIN="$(swift build --show-bin-path)"

echo "== deadboltctl --version =="
"$BIN/deadboltctl" --version | grep -q "Deadbolt"

FIXTURE="$(mktemp -t deadbolt-fixture).json"
trap 'rm -f "$FIXTURE"' EXIT
cat > "$FIXTURE" <<'JSON'
[
  {"vendorID": 1234, "productID": 5678, "serialNumber": "ABC123456789", "name": "Key A"},
  {"volumeUUID": "11111111-2222-3333-4444-555555555555", "name": "Key B"},
  {"vendorID": 1234, "productID": 5678, "containerID": "C0FFEE", "name": "Key C"},
  {"vendorID": 1234, "productID": 5678, "vendorName": "Acme", "productName": "Widget", "name": "Key D"},
  {"serialNumber": "000000000", "name": "Key E placeholder"}
]
JSON

echo "== deadboltctl devices --fake (lists A-E) =="
OUT="$("$BIN/deadboltctl" devices --fake "$FIXTURE")"
echo "$OUT"
[[ "$OUT" == *$'\tA\t'* ]]
[[ "$OUT" == *$'\tB\t'* ]]
[[ "$OUT" == *$'\tC\t'* ]]
[[ "$OUT" == *$'\tD\t'* ]]
[[ "$OUT" == *$'\tE\t'* ]]

echo "== deadboltctl devices --json --fake (machine-readable tiers) =="
JSON_OUT="$("$BIN/deadboltctl" devices --json --fake "$FIXTURE")"
[[ "$JSON_OUT" == *'"tier" : "A"'* ]]
[[ "$JSON_OUT" == *'"tier" : "B"'* ]]
[[ "$JSON_OUT" == *'"tier" : "C"'* ]]
[[ "$JSON_OUT" == *'"tier" : "D"'* ]]
[[ "$JSON_OUT" == *'"tier" : "E"'* ]]

echo "== DEADBOLT_FAKE_DEVICES env var =="
ENV_OUT="$(DEADBOLT_FAKE_DEVICES="$FIXTURE" "$BIN/deadboltctl" devices)"
[[ "$ENV_OUT" == *$'\tA\t'* ]]
[[ "$ENV_OUT" == *$'\tE\t'* ]]

echo "== deadboltctl identify <selector> (tier + reason) =="
IDENT="$("$BIN/deadboltctl" identify "Key A" --fake "$FIXTURE")"
echo "$IDENT"
[[ "$IDENT" == *'tier: A'* ]]
[[ "$IDENT" == *'reason:'* ]]

echo "E2E OK"
