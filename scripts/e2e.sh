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

echo "E2E OK"
