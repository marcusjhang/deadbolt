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
KEYS_FIXTURE="$(mktemp -t deadbolt-keys-fixture).json"
EMPTY_FIXTURE="$(mktemp -t deadbolt-empty-fixture).json"
STATE_DIR="$(mktemp -d -t deadbolt-state)"
trap 'rm -f "$FIXTURE" "$KEYS_FIXTURE" "$EMPTY_FIXTURE"; rm -rf "$STATE_DIR"' EXIT
cat > "$FIXTURE" <<'JSON'
[
  {"vendorID": 1234, "productID": 5678, "serialNumber": "ABC123456789", "name": "Key A"},
  {"volumeUUID": "11111111-2222-3333-4444-555555555555", "name": "Key B"},
  {"vendorID": 1234, "productID": 5678, "containerID": "C0FFEE", "name": "Key C"},
  {"vendorID": 1234, "productID": 5678, "vendorName": "Acme", "productName": "Widget", "name": "Key D"},
  {"serialNumber": "000000000", "name": "Key E placeholder"}
]
JSON
echo '[]' > "$EMPTY_FIXTURE"

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

cat > "$KEYS_FIXTURE" <<'JSON'
[
  {"vendorID": 1234, "productID": 5678, "serialNumber": "ABC123456789", "name": "Key A", "location": "0x14000000"},
  {"vendorID": 1234, "productID": 5678, "serialNumber": "ABC123456789", "name": "Key A", "location": "0x34000000"},
  {"vendorID": 1234, "productID": 5678, "vendorName": "Acme", "productName": "Widget", "name": "Key D"},
  {"serialNumber": "000000000", "name": "Key E placeholder"},
  {"vendorID": 9999, "productID": 8888, "serialNumber": "FIXED123456", "name": "Internal Disk", "isRemovable": false}
]
JSON

echo "== enroll Tier A writes a JSON key record =="
DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" enroll 1 --fake "$KEYS_FIXTURE" --label "Spare Drive"
[[ -f "$STATE_DIR/keys.json" ]]
grep -q '"fingerprint"' "$STATE_DIR/keys.json"
grep -q '"tier"' "$STATE_DIR/keys.json"
grep -q '"label"' "$STATE_DIR/keys.json"
grep -q '"createdAt"' "$STATE_DIR/keys.json"

echo "== keys --json includes fingerprint, tier, label, createdAt =="
KEYS_JSON="$(DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" keys --json)"
echo "$KEYS_JSON"
[[ "$KEYS_JSON" == *'"fingerprint"'* ]]
[[ "$KEYS_JSON" == *'"tier" : "A"'* ]]
[[ "$KEYS_JSON" == *'"label" : "Spare Drive"'* ]]
[[ "$KEYS_JSON" == *'"createdAt"'* ]]

echo "== keys (human-readable) =="
KEYS_HUMAN="$(DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" keys)"
echo "$KEYS_HUMAN"
[[ "$KEYS_HUMAN" == *'Spare Drive'* ]]
[[ "$KEYS_HUMAN" == *$'\tA\t'* ]]

echo "== fingerprint stable when only location changes =="
DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" enroll 1 --fake "$KEYS_FIXTURE" --label "Loc A"
DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" enroll 2 --fake "$KEYS_FIXTURE" --label "Loc B"
FP_COUNT="$(DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" keys --json | grep -o '"fingerprint" : "[a-f0-9]*"' | sort -u | wc -l | tr -d ' ')"
[[ "$FP_COUNT" == "1" ]]

echo "== Tier E enrollment refused (non-zero, no key written) =="
E_STATE="$(mktemp -d -t deadbolt-state-e)"
trap 'rm -f "$FIXTURE" "$KEYS_FIXTURE" "$EMPTY_FIXTURE"; rm -rf "$STATE_DIR" "$E_STATE"' EXIT
if DEADBOLT_STATE_DIR="$E_STATE" "$BIN/deadboltctl" enroll "Key E placeholder" --fake "$KEYS_FIXTURE" >/dev/null 2>&1; then
    echo "expected Tier E enrollment to fail" >&2
    exit 1
fi
[[ ! -f "$E_STATE/keys.json" ]]

echo "== Tier D requires --allow-weak =="
D_STATE="$(mktemp -d -t deadbolt-state-d)"
trap 'rm -f "$FIXTURE" "$KEYS_FIXTURE" "$EMPTY_FIXTURE"; rm -rf "$STATE_DIR" "$E_STATE" "$D_STATE"' EXIT
if DEADBOLT_STATE_DIR="$D_STATE" "$BIN/deadboltctl" enroll "Key D" --fake "$KEYS_FIXTURE" >/dev/null 2>&1; then
    echo "expected Tier D enrollment without --allow-weak to fail" >&2
    exit 1
fi
[[ ! -f "$D_STATE/keys.json" ]]
DEADBOLT_STATE_DIR="$D_STATE" "$BIN/deadboltctl" enroll "Key D" --fake "$KEYS_FIXTURE" --allow-weak
[[ -f "$D_STATE/keys.json" ]]

echo "== non-removable/internal requires --allow-internal =="
I_STATE="$(mktemp -d -t deadbolt-state-i)"
trap 'rm -f "$FIXTURE" "$KEYS_FIXTURE" "$EMPTY_FIXTURE"; rm -rf "$STATE_DIR" "$E_STATE" "$D_STATE" "$I_STATE"' EXIT
if DEADBOLT_STATE_DIR="$I_STATE" "$BIN/deadboltctl" enroll "Internal Disk" --fake "$KEYS_FIXTURE" >/dev/null 2>&1; then
    echo "expected non-removable enrollment without --allow-internal to fail" >&2
    exit 1
fi
[[ ! -f "$I_STATE/keys.json" ]]
DEADBOLT_STATE_DIR="$I_STATE" "$BIN/deadboltctl" enroll "Internal Disk" --fake "$KEYS_FIXTURE" --allow-internal
[[ -f "$I_STATE/keys.json" ]]

echo "== lock succeeds and persists across processes =="
DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" lock
STATUS_AFTER_LOCK="$(DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" status --fake "$KEYS_FIXTURE")"
echo "$STATUS_AFTER_LOCK"
[[ "$STATUS_AFTER_LOCK" == *'state: locked'* ]]
[[ "$STATUS_AFTER_LOCK" == *'attachedKey: Spare Drive'* ]]

echo "== status --json reports locked and names attached key =="
STATUS_JSON="$(DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" status --json --fake "$KEYS_FIXTURE")"
echo "$STATUS_JSON"
[[ "$STATUS_JSON" == *'"state" : "locked"'* ]]
[[ "$STATUS_JSON" == *'"attachedKey" : "Spare Drive"'* ]]

echo "== unlock fails while key absent, state stays locked =="
if DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" unlock --fake "$EMPTY_FIXTURE" >/dev/null 2>&1; then
    echo "expected unlock to fail while key absent" >&2
    exit 1
fi
STATUS_STILL_LOCKED="$(DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" status --fake "$EMPTY_FIXTURE")"
[[ "$STATUS_STILL_LOCKED" == *'state: locked'* ]]

echo "== unlock succeeds when matching key attached =="
DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" unlock --fake "$KEYS_FIXTURE"
STATUS_UNLOCKED="$(DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" status --fake "$KEYS_FIXTURE")"
echo "$STATUS_UNLOCKED"
[[ "$STATUS_UNLOCKED" == *'state: unlocked'* ]]

echo "== unenroll removes the matching key =="
DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" unenroll "Spare Drive"
KEYS_AFTER_UNENROLL="$(DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" keys)"
[[ "$KEYS_AFTER_UNENROLL" != *'Spare Drive'* ]]

echo "== reset --force clears state =="
DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" reset --force
STATUS_AFTER_RESET="$(DEADBOLT_STATE_DIR="$STATE_DIR" "$BIN/deadboltctl" status --fake "$KEYS_FIXTURE")"
echo "$STATUS_AFTER_RESET"
[[ "$STATUS_AFTER_RESET" == *'state: unlocked'* ]]
[[ "$STATUS_AFTER_RESET" == *'attachedKey: none'* ]]

echo "E2E OK"
