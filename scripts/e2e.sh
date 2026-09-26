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

echo "== block add/remove domain and app, observable via list --json =="
BLOCK_STATE="$(mktemp -d -t deadbolt-state-block)"
HOSTS_FILE="$(mktemp -t deadbolt-hosts)"
APPS_FILE="$(mktemp -t deadbolt-apps).json"
trap 'rm -f "$FIXTURE" "$KEYS_FIXTURE" "$EMPTY_FIXTURE" "$HOSTS_FILE" "$APPS_FILE"; rm -rf "$STATE_DIR" "$E_STATE" "$D_STATE" "$I_STATE" "$BLOCK_STATE"' EXIT

DEADBOLT_STATE_DIR="$BLOCK_STATE" "$BIN/deadboltctl" block add-domain news.ycombinator.com
DEADBOLT_STATE_DIR="$BLOCK_STATE" "$BIN/deadboltctl" block add-domain example.com
DEADBOLT_STATE_DIR="$BLOCK_STATE" "$BIN/deadboltctl" block add-app com.apple.Safari

BLOCK_JSON="$(DEADBOLT_STATE_DIR="$BLOCK_STATE" "$BIN/deadboltctl" block list --json)"
echo "$BLOCK_JSON"
[[ "$BLOCK_JSON" == *'news.ycombinator.com'* ]]
[[ "$BLOCK_JSON" == *'example.com'* ]]
[[ "$BLOCK_JSON" == *'com.apple.Safari'* ]]

echo "== block remove-domain omits the domain =="
DEADBOLT_STATE_DIR="$BLOCK_STATE" "$BIN/deadboltctl" block remove-domain news.ycombinator.com
BLOCK_JSON="$(DEADBOLT_STATE_DIR="$BLOCK_STATE" "$BIN/deadboltctl" block list --json)"
[[ "$BLOCK_JSON" != *'news.ycombinator.com'* ]]
[[ "$BLOCK_JSON" == *'example.com'* ]]

echo "== block remove-app omits the app =="
DEADBOLT_STATE_DIR="$BLOCK_STATE" "$BIN/deadboltctl" block remove-app com.apple.Safari
BLOCK_JSON="$(DEADBOLT_STATE_DIR="$BLOCK_STATE" "$BIN/deadboltctl" block list --json)"
[[ "$BLOCK_JSON" != *'com.apple.Safari'* ]]
DEADBOLT_STATE_DIR="$BLOCK_STATE" "$BIN/deadboltctl" block add-app com.apple.Safari

echo "== block list persists across fresh invocations =="
BLOCK_JSON="$(DEADBOLT_STATE_DIR="$BLOCK_STATE" "$BIN/deadboltctl" block list --json)"
[[ "$BLOCK_JSON" == *'example.com'* ]]
[[ "$BLOCK_JSON" == *'com.apple.Safari'* ]]

printf '# pre comment\n127.0.0.1 localhost\n::1 localhost\n' > "$HOSTS_FILE"
cat > "$APPS_FILE" <<'JSON'
[
  {"bundleIdentifier": "com.apple.Safari", "name": "Safari"},
  {"bundleIdentifier": "com.apple.Mail", "name": "Mail"}
]
JSON

echo "== enforce --dry-run changes nothing =="
DEADBOLT_STATE_DIR="$BLOCK_STATE" "$BIN/deadboltctl" lock
DRY_OUT="$(DEADBOLT_STATE_DIR="$BLOCK_STATE" DEADBOLT_FAKE_APPS="$APPS_FILE" "$BIN/deadboltctl" enforce --dry-run --hosts-path "$HOSTS_FILE")"
echo "$DRY_OUT"
[[ "$DRY_OUT" == *'hosts: would-apply'* ]]
[[ "$DRY_OUT" == *'apps would terminate: 1'* ]]
! grep -q 'BEGIN DEADBOLT' "$HOSTS_FILE"

echo "== enforce while locked applies hosts block and terminates fake apps =="
ENFORCE_OUT="$(DEADBOLT_STATE_DIR="$BLOCK_STATE" DEADBOLT_FAKE_APPS="$APPS_FILE" "$BIN/deadboltctl" enforce --hosts-path "$HOSTS_FILE")"
echo "$ENFORCE_OUT"
[[ "$ENFORCE_OUT" == *'hosts: applied'* ]]
[[ "$ENFORCE_OUT" == *'apps terminated: 1'* ]]
grep -q 'BEGIN DEADBOLT' "$HOSTS_FILE"
grep -q '0.0.0.0 example.com' "$HOSTS_FILE"
grep -q '0.0.0.0 www.example.com' "$HOSTS_FILE"
grep -q '::1 example.com' "$HOSTS_FILE"
grep -q '::1 www.example.com' "$HOSTS_FILE"

echo "== applying a second time is idempotent (no duplicate block) =="
HOSTS_SNAPSHOT="$(cat "$HOSTS_FILE")"
DEADBOLT_STATE_DIR="$BLOCK_STATE" DEADBOLT_FAKE_APPS="$APPS_FILE" "$BIN/deadboltctl" enforce --hosts-path "$HOSTS_FILE" >/dev/null
[[ "$(cat "$HOSTS_FILE")" == "$HOSTS_SNAPSHOT" ]]
[[ "$(grep -c 'BEGIN DEADBOLT' "$HOSTS_FILE")" == "1" ]]

echo "== enforce while unlocked clears the hosts block =="
DEADBOLT_STATE_DIR="$BLOCK_STATE" "$BIN/deadboltctl" enroll 1 --fake "$KEYS_FIXTURE" --label "E2E Unlock"
DEADBOLT_STATE_DIR="$BLOCK_STATE" "$BIN/deadboltctl" unlock --fake "$KEYS_FIXTURE"
UNLOCK_OUT="$(DEADBOLT_STATE_DIR="$BLOCK_STATE" DEADBOLT_FAKE_APPS="$APPS_FILE" "$BIN/deadboltctl" enforce --hosts-path "$HOSTS_FILE")"
echo "$UNLOCK_OUT"
[[ "$UNLOCK_OUT" == *'hosts: cleared'* ]]
! grep -q 'BEGIN DEADBOLT' "$HOSTS_FILE"
grep -q '127.0.0.1 localhost' "$HOSTS_FILE"
grep -q '# pre comment' "$HOSTS_FILE"

echo "== enforce fails non-zero when hosts file not writable and leaves it unchanged =="
NOTWRITABLE_STATE="$(mktemp -d -t deadbolt-state-notwritable)"
NOTWRITABLE_HOSTS="$(mktemp -t deadbolt-hosts-notwritable)"
trap 'rm -f "$FIXTURE" "$KEYS_FIXTURE" "$EMPTY_FIXTURE" "$HOSTS_FILE" "$APPS_FILE" "$NOTWRITABLE_HOSTS"; rm -rf "$STATE_DIR" "$E_STATE" "$D_STATE" "$I_STATE" "$BLOCK_STATE" "$NOTWRITABLE_STATE"' EXIT
DEADBOLT_STATE_DIR="$NOTWRITABLE_STATE" "$BIN/deadboltctl" block add-domain example.com
DEADBOLT_STATE_DIR="$NOTWRITABLE_STATE" "$BIN/deadboltctl" lock
printf '# keep\n' > "$NOTWRITABLE_HOSTS"
chmod 0444 "$NOTWRITABLE_HOSTS"
if DEADBOLT_STATE_DIR="$NOTWRITABLE_STATE" DEADBOLT_FAKE_APPS="$APPS_FILE" "$BIN/deadboltctl" enforce --hosts-path "$NOTWRITABLE_HOSTS" >/dev/null 2>&1; then
    echo "expected enforce to fail when hosts file not writable" >&2
    exit 1
fi
[[ "$(cat "$NOTWRITABLE_HOSTS")" == "# keep" ]]
chmod 0644 "$NOTWRITABLE_HOSTS"

echo "== lock/unlock apply and clear enforcement when a hosts path is configured =="
LOCK_ENFORCE_STATE="$(mktemp -d -t deadbolt-state-lockenf)"
LOCK_ENFORCE_HOSTS="$(mktemp -t deadbolt-hosts-lockenf)"
trap 'rm -f "$FIXTURE" "$KEYS_FIXTURE" "$EMPTY_FIXTURE" "$HOSTS_FILE" "$APPS_FILE" "$NOTWRITABLE_HOSTS" "$LOCK_ENFORCE_HOSTS"; rm -rf "$STATE_DIR" "$E_STATE" "$D_STATE" "$I_STATE" "$BLOCK_STATE" "$NOTWRITABLE_STATE" "$LOCK_ENFORCE_STATE"' EXIT
printf '# keep me\n' > "$LOCK_ENFORCE_HOSTS"
DEADBOLT_STATE_DIR="$LOCK_ENFORCE_STATE" "$BIN/deadboltctl" block add-domain example.com
DEADBOLT_STATE_DIR="$LOCK_ENFORCE_STATE" DEADBOLT_HOSTS_PATH="$LOCK_ENFORCE_HOSTS" DEADBOLT_FAKE_APPS="$APPS_FILE" "$BIN/deadboltctl" lock
grep -q 'BEGIN DEADBOLT' "$LOCK_ENFORCE_HOSTS"
DEADBOLT_STATE_DIR="$LOCK_ENFORCE_STATE" "$BIN/deadboltctl" enroll 1 --fake "$KEYS_FIXTURE" --label "lockenf"
DEADBOLT_STATE_DIR="$LOCK_ENFORCE_STATE" DEADBOLT_HOSTS_PATH="$LOCK_ENFORCE_HOSTS" "$BIN/deadboltctl" unlock --fake "$KEYS_FIXTURE"
! grep -q 'BEGIN DEADBOLT' "$LOCK_ENFORCE_HOSTS"

echo "== lock reports but does not crash when hosts file not writable =="
NOTWRITABLE_LOCK_STATE="$(mktemp -d -t deadbolt-state-locknw)"
NOTWRITABLE_LOCK_HOSTS="$(mktemp -t deadbolt-hosts-locknw)"
trap 'rm -f "$FIXTURE" "$KEYS_FIXTURE" "$EMPTY_FIXTURE" "$HOSTS_FILE" "$APPS_FILE" "$NOTWRITABLE_HOSTS" "$LOCK_ENFORCE_HOSTS" "$NOTWRITABLE_LOCK_HOSTS" "$DIAG_FILE"; rm -rf "$STATE_DIR" "$E_STATE" "$D_STATE" "$I_STATE" "$BLOCK_STATE" "$NOTWRITABLE_STATE" "$LOCK_ENFORCE_STATE" "$NOTWRITABLE_LOCK_STATE" "$DIAG_STATE"' EXIT
printf '# keep\n' > "$NOTWRITABLE_LOCK_HOSTS"
chmod 0444 "$NOTWRITABLE_LOCK_HOSTS"
DEADBOLT_STATE_DIR="$NOTWRITABLE_LOCK_STATE" DEADBOLT_HOSTS_PATH="$NOTWRITABLE_LOCK_HOSTS" "$BIN/deadboltctl" lock >/dev/null 2>&1
DEADBOLT_STATE_DIR="$NOTWRITABLE_LOCK_STATE" "$BIN/deadboltctl" status --fake "$KEYS_FIXTURE" | grep -q 'state: locked'
chmod 0644 "$NOTWRITABLE_LOCK_HOSTS"

echo "== timed lock: lock --for 30 persists lockedUntil; unlock fails with remaining time =="
TIMED_STATE="$(mktemp -d -t deadbolt-state-timed)"
CFG_STATE="$(mktemp -d -t deadbolt-state-cfg)"
WATCH_STATE="$(mktemp -d -t deadbolt-state-watch)"
WATCH_HOSTS="$(mktemp -t deadbolt-hosts-watch)"
WATCH_APPS="$(mktemp -t deadbolt-apps-watch).json"
trap 'rm -f "$FIXTURE" "$KEYS_FIXTURE" "$EMPTY_FIXTURE" "$HOSTS_FILE" "$APPS_FILE" "$NOTWRITABLE_HOSTS" "$LOCK_ENFORCE_HOSTS" "$NOTWRITABLE_LOCK_HOSTS" "$DIAG_FILE" "$WATCH_HOSTS" "$WATCH_APPS"; rm -rf "$STATE_DIR" "$E_STATE" "$D_STATE" "$I_STATE" "$BLOCK_STATE" "$NOTWRITABLE_STATE" "$LOCK_ENFORCE_STATE" "$NOTWRITABLE_LOCK_STATE" "$DIAG_STATE" "$TIMED_STATE" "$CFG_STATE" "$WATCH_STATE"' EXIT

NOW="2026-01-01T00:00:00Z"
LATER="2026-01-01T00:31:00Z"
DEADBOLT_STATE_DIR="$TIMED_STATE" "$BIN/deadboltctl" enroll 1 --fake "$KEYS_FIXTURE" --label "Timed Key"
DEADBOLT_STATE_DIR="$TIMED_STATE" DEADBOLT_NOW="$NOW" "$BIN/deadboltctl" lock --for 30
TIMED_STATUS="$(DEADBOLT_STATE_DIR="$TIMED_STATE" DEADBOLT_NOW="$NOW" "$BIN/deadboltctl" status --fake "$KEYS_FIXTURE")"
echo "$TIMED_STATUS"
[[ "$TIMED_STATUS" == *'state: locked'* ]]
[[ "$TIMED_STATUS" == *'lockedUntil'* ]]
[[ "$TIMED_STATUS" == *'remainingMinutes: 30'* ]]

echo "== status --json includes lockedUntil and remainingMinutes =="
TIMED_JSON="$(DEADBOLT_STATE_DIR="$TIMED_STATE" DEADBOLT_NOW="$NOW" "$BIN/deadboltctl" status --json --fake "$KEYS_FIXTURE")"
echo "$TIMED_JSON"
[[ "$TIMED_JSON" == *'"state" : "locked"'* ]]
[[ "$TIMED_JSON" == *'"lockedUntil"'* ]]
[[ "$TIMED_JSON" == *'"remainingMinutes" : 30'* ]]

echo "== unlock fails during active timed lock even with key attached =="
UNLOCK_ERR="$(DEADBOLT_STATE_DIR="$TIMED_STATE" DEADBOLT_NOW="$NOW" "$BIN/deadboltctl" unlock --fake "$KEYS_FIXTURE" 2>&1 >/dev/null || true)"
echo "$UNLOCK_ERR"
[[ "$UNLOCK_ERR" == *'remaining'* ]]
[[ "$(DEADBOLT_STATE_DIR="$TIMED_STATE" DEADBOLT_NOW="$NOW" "$BIN/deadboltctl" status --fake "$KEYS_FIXTURE")" == *'state: locked'* ]]

echo "== advancing DEADBOLT_NOW past lockedUntil lets unlock succeed =="
DEADBOLT_STATE_DIR="$TIMED_STATE" DEADBOLT_NOW="$LATER" "$BIN/deadboltctl" unlock --fake "$KEYS_FIXTURE"
[[ "$(DEADBOLT_STATE_DIR="$TIMED_STATE" DEADBOLT_NOW="$LATER" "$BIN/deadboltctl" status --fake "$KEYS_FIXTURE")" == *'state: unlocked'* ]]

echo "== config get/set/list for lockOnKeyRemoval =="
[[ "$(DEADBOLT_STATE_DIR="$CFG_STATE" "$BIN/deadboltctl" config get lockOnKeyRemoval)" == "off" ]]
DEADBOLT_STATE_DIR="$CFG_STATE" "$BIN/deadboltctl" config set lockOnKeyRemoval on
[[ "$(DEADBOLT_STATE_DIR="$CFG_STATE" "$BIN/deadboltctl" config get lockOnKeyRemoval)" == "on" ]]
CFG_LIST="$(DEADBOLT_STATE_DIR="$CFG_STATE" "$BIN/deadboltctl" config list)"
echo "$CFG_LIST"
[[ "$CFG_LIST" == *'lockOnKeyRemoval'* ]]
[[ "$CFG_LIST" == *'on'* ]]
CFG_JSON="$(DEADBOLT_STATE_DIR="$CFG_STATE" "$BIN/deadboltctl" config list --json)"
echo "$CFG_JSON"
[[ "$CFG_JSON" == *'"lockOnKeyRemoval" : true'* ]]
if DEADBOLT_STATE_DIR="$CFG_STATE" "$BIN/deadboltctl" config set lockOnKeyRemoval maybe >/dev/null 2>&1; then
    echo "expected config set with invalid value to fail" >&2
    exit 1
fi

echo "== watch --once locks when key absent with lockOnKeyRemoval on =="
cat > "$WATCH_APPS" <<'JSON'
[
  {"bundleIdentifier": "com.apple.Safari", "name": "Safari"}
]
JSON
printf '# keep\n' > "$WATCH_HOSTS"
DEADBOLT_STATE_DIR="$WATCH_STATE" "$BIN/deadboltctl" config set lockOnKeyRemoval on
DEADBOLT_STATE_DIR="$WATCH_STATE" "$BIN/deadboltctl" enroll 1 --fake "$KEYS_FIXTURE" --label "Watch Key"
DEADBOLT_STATE_DIR="$WATCH_STATE" "$BIN/deadboltctl" block add-domain example.com

DEADBOLT_STATE_DIR="$WATCH_STATE" DEADBOLT_FAKE_DEVICES="$EMPTY_FIXTURE" DEADBOLT_FAKE_APPS="$WATCH_APPS" "$BIN/deadboltctl" watch --once --hosts-path "$WATCH_HOSTS"
[[ "$(DEADBOLT_STATE_DIR="$WATCH_STATE" "$BIN/deadboltctl" status --fake "$EMPTY_FIXTURE")" == *'state: locked'* ]]
grep -q 'BEGIN DEADBOLT' "$WATCH_HOSTS"

echo "== watch --once while unlocked clears the hosts block =="
DEADBOLT_STATE_DIR="$WATCH_STATE" "$BIN/deadboltctl" unlock --fake "$KEYS_FIXTURE"
DEADBOLT_STATE_DIR="$WATCH_STATE" DEADBOLT_FAKE_DEVICES="$KEYS_FIXTURE" DEADBOLT_FAKE_APPS="$WATCH_APPS" "$BIN/deadboltctl" watch --once --hosts-path "$WATCH_HOSTS"
[[ "$(DEADBOLT_STATE_DIR="$WATCH_STATE" "$BIN/deadboltctl" status --fake "$KEYS_FIXTURE")" == *'state: unlocked'* ]]
! grep -q 'BEGIN DEADBOLT' "$WATCH_HOSTS"
grep -q '# keep' "$WATCH_HOSTS"

echo "== long-running watch exits cleanly (0) on SIGINT =="
DEADBOLT_STATE_DIR="$WATCH_STATE" DEADBOLT_FAKE_DEVICES="$EMPTY_FIXTURE" DEADBOLT_FAKE_APPS="$WATCH_APPS" "$BIN/deadboltctl" watch --interval 1 --hosts-path "$WATCH_HOSTS" &
WPID=$!
sleep 1.5
kill -INT "$WPID"
wait "$WPID"

echo "== make-app.sh builds and signs Deadbolt.app =="
bash scripts/make-app.sh
APP="build/Deadbolt.app"
[[ -d "$APP" ]]
[[ -f "$APP/Contents/MacOS/Deadbolt" ]]
[[ -x "$APP/Contents/MacOS/Deadbolt" ]]
[[ -f "$APP/Contents/Info.plist" ]]
[[ -d "$APP/Contents/Resources" ]]

echo "== re-running make-app.sh succeeds (re-runnable) =="
bash scripts/make-app.sh

echo "== Info.plist validates and sets required keys =="
plutil -lint "$APP/Contents/Info.plist"
[[ "$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" == "com.deadbolt.app" ]]
[[ "$(plutil -extract LSUIElement raw "$APP/Contents/Info.plist")" == "true" ]]
[[ "$(plutil -extract CFBundlePackageType raw "$APP/Contents/Info.plist")" == "APPL" ]]
[[ "$(plutil -extract CFBundleExecutable raw "$APP/Contents/Info.plist")" == "Deadbolt" ]]
[[ "$(plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist")" == "13.0" ]]
[[ -n "$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")" ]]
[[ -n "$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")" ]]

echo "== bundle is ad-hoc signed =="
codesign --verify "$APP"

echo "== Deadbolt --version =="
"$APP/Contents/MacOS/Deadbolt" --version | grep -q "Deadbolt"

echo "== Deadbolt --diagnostics emits parseable JSON and exits 0 =="
DIAG_STATE="$(mktemp -d -t deadbolt-diag-state)"
DIAG_FILE="$(mktemp -t deadbolt-diag)"
DEADBOLT_STATE_DIR="$DIAG_STATE" "$APP/Contents/MacOS/Deadbolt" --diagnostics > "$DIAG_FILE"
python3 -c 'import json,sys; json.load(sys.stdin)' < "$DIAG_FILE"
grep -q '"version"' "$DIAG_FILE"
grep -q '"attachedKey"' "$DIAG_FILE"
grep -q '"hostsPathWritable"' "$DIAG_FILE"
grep -q '"enrolledKeyCount"' "$DIAG_FILE"

echo "E2E OK"
