# Deadbolt — M0 build status

**Date:** 2026-09-26
**Status:** M0 spike is **built, running, and end-to-end verified** on the dev machine (Apple M4 Pro, macOS 15.6, Xcode 26.3, Swift 6.2).
**Branch:** `main`

This document records what was built today and how it was verified. The work was
driven through the repo-native software factory (`psf`): each goal ran
intake → triage → spec → approval → build → independent verify → review →
handoff, with a deterministic end-to-end gate (`bash scripts/e2e.sh`) run on
every step. Work items and their ledger live with the repo (see
`docs/psf-status.txt`, `docs/psf-metrics.txt`, `docs/psf-ledger.txt`).

## What Deadbolt is

A macOS focus blocker unlocked only by a physical USB device the user enrolled and
stashed away. Locking is easy; unlocking requires plugging the key back in. The key
is any generic USB device the user already owns. See `HANDOVER.md` for the product
definition.

## What works today (M0)

| Area | Behavior | CLI surface |
|---|---|---|
| Key detection | Enumerates USB (IOKit `IOUSBHostDevice`) and storage (DiskArbitration) devices; computes an identity strength tier A–E; rejects placeholder serials; never matches on `locationID` | `deadboltctl devices [--json]`, `deadboltctl identify <selector>` |
| Key registry | Enrolls a device as a stable fingerprint (location-independent) with tier + label; refuses Tier E; Tier D requires `--allow-weak`; refuses internal disks unless `--allow-internal` | `enroll`, `keys`, `unenroll` |
| Lock state | Persisted lock/unlock state; `unlock` requires an attached enrolled key | `lock`, `unlock`, `status [--json]`, `reset --force` |
| Timed lock | `lock --for <minutes>` blocks unlocking even with the key until the timer elapses | `lock --for`, `status` (remaining minutes) |
| Physical-switch mode | Optional auto-lock when the enrolled key is detached | `config set lockOnKeyRemoval on\|off`, `config get/list` |
| Enforcement | Managed hosts block (markers, idempotent, preserves other lines) + terminates running blocked apps | `block add/remove-domain`, `block add/remove-app`, `block list`, `enforce [--dry-run] [--hosts-path]` |
| Watch loop | Continuously applies/clears enforcement and honors lock-on-removal | `watch [--interval] [--hosts-path] [--once]` |
| Menu-bar app | SwiftUI `MenuBarExtra`; icon reflects state; Lock/Unlock; enrolled keys; periodic refresh; signed `.app` bundle | `scripts/make-app.sh` → `build/Deadbolt.app` |
| Headless entry points | For diagnostics/testing without the GUI | `Deadbolt --version`, `Deadbolt --diagnostics` (JSON) |

State lives in `~/Library/Application Support/Deadbolt` (override with
`DEADBOLT_STATE_DIR`). The hosts file defaults to `/etc/hosts` (override with
`--hosts-path` or `DEADBOLT_HOSTS_PATH`).

## Build and run

```bash
swift build                 # build all targets
swift test                  # 72 unit tests
bash scripts/e2e.sh         # deterministic end-to-end gate
bash scripts/make-app.sh    # assemble + ad-hoc sign build/Deadbolt.app
open build/Deadbolt.app     # run the menu-bar app
```

Quick manual smoke test (no root, no real state touched):

```bash
export DEADBOLT_STATE_DIR="$(mktemp -d)"
BIN="$(swift build --show-bin-path)"
"$BIN/deadboltctl" devices
"$BIN/deadboltctl" enroll <selector> --label spare
"$BIN/deadboltctl" lock
"$BIN/deadboltctl" status
```

## Verification evidence

- `bash scripts/e2e.sh` → **E2E OK** (builds all targets, runs 72 unit tests,
  exercises the full `deadboltctl` surface against JSON fixtures and a temporary
  state dir + hosts file, builds and validates `Deadbolt.app`, and runs the
  headless entry points).
- `swift test` → **72 tests, 0 failures**.
- `psf audit` → **healthy: True** (ledger chain ok, digest-bound approvals,
  guardrail 6/6, adapter 8/8, benchmark non-regression).
- Real hardware on the dev machine: enumerated the attached NS1081 drive as
  Tier A and the VIA Labs hubs (serial `000000000`) as refused placeholders;
  enrolled the NS1081, locked, and unlocked with the key attached.
- Real enforcement: with Calculator blocked and locked, `enforce` terminated the
  running Calculator process (verified `apps terminated: 1`, process gone).
- Real hosts block: a temporary hosts file gained the marked `0.0.0.0`/`::1`
  block on lock and lost exactly that block on unlock, preserving other lines.

## Factory work items

| Work item | Goal | State | Outcome |
|---|---|---|---|
| W-47706186 | USB key detection core + identity tier ladder | DONE | accepted |
| W-47c952bc | Key registry + lock/unlock state machine | DONE | accepted |
| W-9fc200a5 | Enforcement (hosts block + app termination) | verified, accepted | accepted |
| W-88b714c3 | Menu-bar app + app bundle + diagnostics | DONE | accepted |
| W-4fd797e7 | Timed lock + lock-on-key-removal + watch loop | DONE | accepted |

All five goals passed the deterministic e2e gate independently, in addition to
the factory's LLM verifier (quorum 2).

## Known limits (not done in M0)

- Enforcement runs from the CLI/app process. The **root LaunchDaemon** and
  **Network Extension system extension** (system-wide, survives quitting the app)
  are M1 — today `/etc/hosts` must be writable (root) for real system blocking.
- Website blocking is hosts/DNS-level; DoH/VPN bypass is not yet addressed
  (that is the M2 content-filter work).
- App blocking is terminate-and-repeat, not an OS-level shield.
- One key in v1; YubiKey challenge-response strong mode is v2.
- Distribution (notarized `.dmg`, Developer ID) is not set up yet; the bundle is
  ad-hoc signed for local use.

## Next steps (M1)

1. Promote the per-user helper to a root `SMAppService` LaunchDaemon and move
   state to root-owned `/Library/Application Support/Deadbolt`.
2. Add the `NEDNSProxyProvider` system extension for system-wide website blocking.
3. Daemon-side device monitoring (IOKit match notifications) instead of polling.
4. Re-verify the key after wake-from-sleep and after login.
