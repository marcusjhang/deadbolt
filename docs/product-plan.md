# Deadbolt — Full Product Plan
### The Mac focus blocker you can't click past. Locked behind any USB device you own.

*Master plan. Supersedes the QR/key mechanism in `product-summary.md`. Research: `market-research.md`. Key mechanics: `usb-key-design.md`.*

---

## 0. Decisions locked

| # | Decision |
|---|---|
| 1 | **Product:** a notarized, system-level Mac focus blocker (apps + websites, system-wide). |
| 2 | **The key is any generic USB device the user already owns** — a spare thumb drive, SD card, YubiKey, old mouse dongle, dev board. No purchase required, no special hardware. |
| 3 | **Lock is easy; unlock requires plugging the key in.** Same asymmetry as Brick. |
| 4 | **Enforcement runs in a root LaunchDaemon + Network Extension**, so it survives quitting the app. |
| 5 | **Direct distribution** (Developer ID `.dmg`), one-time price. Not the Mac App Store. |
| 6 | **Working name:** Deadbolt (trademark check pending). |

---

## 1. Vision, principles, design laws

**Vision:** make the Mac a place where deep work is the default, by borrowing the one thing phone blockers get right — a physical commitment device — and using hardware everyone already owns.

**Non-negotiable design laws**
1. **The off-switch is a physical object.** Ending a session costs a walk, not a click.
2. **No decorative overrides.** No "ignore," no "5 more minutes," no one-click off.
3. **Locking is frictionless; unlocking is not.**
4. **Reliability over cleverness.** Scheduled locks must fire (Brick's most-complained bug).
5. **Non-judgmental tone.** No shame, no guilt-gamification.
6. **Local-first & private.** Block lists and key fingerprints never leave the machine.
7. **Honest limits.** It's friction and commitment, not DRM. Admins can always bypass; we don't pretend otherwise.

---

## 2. Product definition & positioning

- **Category:** commitment-device software for the Mac.
- **One-liner:** *"Block the distractions. Then unplug the key and put it in a drawer. You're not getting it back until you go get it."*
- **Elevator pitch:** *Every Mac blocker lets you turn it off. Deadbolt doesn't. It removes distracting apps and sites system-wide — in every browser and every app — and the only way to end a session is to plug in the USB device you enrolled as your key and left somewhere inconvenient. It works with a drive you already own. No subscription.*
- **Against:** Opal (browser-puppeteering Mac app, no physical key), Freedom/Cold Turkey (software off-switch), Screen Time (tap "ignore").
- **Taglines:** *"Brick, for the Mac."* · *"Any USB stick is the off-switch."* · *"One key. Every screen."* (v2 vision)

---

## 3. Users, jobs, anti-users

**Primary personas**
- **The Brick owner on a Mac** — already believes the physical mechanic; the laptop is their unguarded screen.
- **The Opal/Freedom churn-out** — has defeated every software override; wants something that actually holds.
- **The ADHD deep-worker** — buys commitment devices (kSafe, Pavlok, Unpluq).

**JTBD**
- *Functional:* "When I sit down to work, keep the distracting apps and sites out of reach so I do the work."
- *Emotional:* "Stop making me fight myself; the decision is already made."
- *Social:* "Be present and productive, not the person lost in a screen."
- *Anti-job:* "Don't lock me out of something I genuinely need in an emergency."

**Anti-users (deliberately not serving v1):** enterprise IT (wants MDM), parents locking kids' Macs (needs MDM/Family), people who want a gentle nudge (that's one sec).

---

## 4. The Key — "any generic USB device you own"

### 4.1 UX contract
- Enrollment: plug in **any** USB device you're willing to stow away → app reads its identity → confirm → done.
- The key is normally **removed and stored away**.
- **Locked → plug the enrolled device in → unlocked.** Removing it does nothing by default.
- Opt-in **physical-switch mode:** removing the key *is* Lock.
- The key only matters at **unlock**; never needed to lock.

### 4.2 Identity model — how "any USB" can still be a key
Not all USB devices are equally identifiable (verified on your Mac: an ESP32 exposes `A1:B2:C3:D4:E5:F6`, but cheap hubs report `000000000` and some receivers expose no serial). So enrollment builds a **fingerprint** on a strength ladder and is honest about it:

| Tier | Identity | Strength | How |
|---|---|---|---|
| **A. Unique device** | `kUSBSerialNumberString` (real) + VID/PID | **Strong** | Serial present and not a placeholder |
| **B. Bound storage** | Volume UUID + 256-bit token file | **Strong** | For drives/cards without a serial |
| **C. Container** | `IOUSBHostDevice.containerID` (+VID/PID) | Medium | Stable per device; may reset on some hubs |
| **D. Model** | VID/PID + vendor/product strings | **Weak** | Matches any identical model — requires explicit consent |
| **E. Unusable** | placeholder serial only, no other data | Refuse | e.g. hub reporting `000000000` |

**Placeholder rejection rules** (from real data): reject serials that are all-zero, all one repeated char, shorter than 4 chars, or equal to the VID/PID rendered as a string. This stops every cheap hub from being "the same key."

**Matching at unlock time:** iterate currently-attached devices; unlock if any device's fingerprint matches an enrolled key (A/C/D), or a bound volume is mounted with a matching UUID **and** a valid token (B).

**Guidance surfaced at enrollment:** prefer a device that is *spare* and *removable* (a thumb drive is ideal). Warn if the chosen device is always connected (built-in, a hub, or your daily mouse) — an always-present key provides zero friction.

### 4.3 Enrollment flow (decision tree)
```
Plug in device
   │
   ├─ Is it internal / root hub / Apple built-in?  ── yes → refuse, explain
   │
   ├─ Real unique serial? ── yes → Tier A: "Strong key. Name it and stow it." ✔ done
   │
   ├─ Removable storage with writable FS? ── yes ─┐
   │                                             ├─ offer token → Tier B ✔ done
   │                                             └─ decline → Tier C/D
   │
   ├─ containerID present? → Tier C: "Good key."  ✔ done
   │
   ├─ Only VID/PID? → Tier D: "Weak key — any identical <Name> unlocks.
   │                   Continue anyway? Or use a spare drive for a strong key."
   │
   └─ Placeholder only → Tier E: refuse, suggest a spare drive.
```
UI shows a live "Key strength" badge as the user plugs devices, with a one-line explanation of why (so the user learns the tradeoff).

### 4.4 Detection & events (macOS plumbing)
- **Storage (drives, SD cards) → Disk Arbitration.** `DASession` + `DARegisterDiskAppeared/DisappearedCallback`; read `kDADiskDescriptionVolumeUUIDKey`, `MediaUUIDKey`, `MediaNameKey`, `DeviceVendorKey`, `DeviceModelKey`, plus `MediaRemovableKey` / `DeviceInternalKey` to exclude system disks.
- **All USB devices → IOKit.** Match `IOUSBHostDevice`; watch `kIOFirstMatchNotification` / `kIOTerminatedNotification` via `IONotificationPortCreate(kIOMainPortDefault)`; read `kUSBSerialNumberString`, `kUSBVendorID`, `kUSBProductID`, `IOUSBHostDevicePropertyKey.containerID`, vendor/product strings.
- **Never use `locationID`** (port/hub dependent) or BSD disk names.
- Both watchers run in the **daemon**, so detection and enforcement survive the UI app quitting.

### 4.5 Edge cases (explicit handling)
| Case | Behavior |
|---|---|
| Key plugged into a different port / via dock | Works (fingerprint-based) |
| Mac sleeps/wakes | Re-assert lock; re-scan attached devices |
| Reboot / power loss | Lock persists (root-owned state); key required to release |
| Key reformatted/wiped (Tier B) | Token gone → treated as "not the key"; re-enroll |
| Two identical model devices (Tier D) | Either unlocks — warned at enrollment; strong tiers unaffected |
| SD card ejected mid-session | Lock holds; card out = no unlock |
| Composite device (multi-interface) | Match the parent device, not interfaces |
| Key is always connected | Warn at enrollment; optional "physical-switch mode" |
| Device behind a non-Apple hub | Still enumerates with its own fingerprint — fine |
| Thunderbolt/PCIe device | Not in the USB plane; not usable as a key (documented) |

### 4.6 Key management
- **Multiple keys:** allow up to 3 enrolled (e.g., home key + travel key). v1 allows 1; v1.1 up to 3.
- **Rotation:** enroll new, retire old — requires an unlocked state or emergency.
- **Lost key:** spend an emergency unbrick; then re-enroll. Recovery doc ships.
- **Strong mode (v2):** a YubiKey using **HMAC-SHA1 challenge-response** over USB HID (Yubico-documented; no secret stored on the Mac) — uncloneable, for "Hardcore."
- **Custom dongle (v2):** optional branded USB-C key (hardware-first, Brick-style), or DIY (ESP32-S2/S3 / ATtiny presenting a unique serial).

---

## 5. Feature specification

### 5.1 v1 (MVP — ship this)
**Blocking**
- **System-wide website blocking** via a **DNS proxy Network Extension** (all browsers and apps, not browser-puppeteering) + **DoH-resolver blocking**.
- **App blocking** via daemon process enforcement: terminate + refuse relaunch of blocked bundle IDs on launch/activation.
- **Allow Only mode** (block everything except a work allowlist: Slack, Figma, GitHub, Zoom…).
- Presets (Social / Video / News / Games) + custom domains + custom app picker.

**Lock**
- Menu-bar Lock button, global hotkey, and **recurring schedules** (Work / Deep Work / Evening / Sleep).
- Menu-bar live timer; lock state persists across sleep/reboot.

**Key**
- Enrollment of **any USB device** (Tiers A–D), strength badge, placeholder rejection, Tier B token writing.
- Unlock by inserting the key; optional physical-switch mode; ratable **emergency budget** (default 2/month, cooldown).

**Other**
- Strict mode (no snooze/cancel; extension + daemon resist disabling; uninstall requires unlock).
- Non-judgmental analytics (time blocked, sessions completed, lock streak).
- Local-only data; no account required.

### 5.2 v1.x polish
- Up to 3 keys; key rotation UI; Focus-shield overlay; per-app severity; richer schedules; menu-bar-only "quick lock"; onboarding wizard polish; crash-safe state; Sparkle auto-update.

### 5.3 v2 (differentiators)
- **Content filter** (`NEFilterDataProvider`) for DoH/VPN-proof blocking.
- **YubiKey challenge-response** strong mode.
- **Custom USB-C key dongle** (hardware SKU).
- **iPhone companion** (Apple's Screen Time API *is* available on iOS) → **one physical key governs phone + Mac.**

### 5.4 Non-goals (v1)
Windows, Mac App Store, browser-extension-only blocking, parental/MDM, subscription-first pricing, "impossible to bypass" claims.

---

## 6. UX flows (screen by screen)

**6.1 Onboarding (5 steps):** value prop → choose what to block (presets) → **enroll your key** (live device list + strength badges) → stow-the-key instruction ("put it somewhere inconvenient — a drawer, another room") → grant system-extension approval + first Lock.

**6.2 Menu-bar states:** ○ Unlocked · ● Locked (with timer) · ◐ Unlocking (key detected, verifying) · ⚠ Emergency available · ▲ Needs attention (key missing / permission revoked).

**6.3 Lock:** one click/hotkey; optional "why" note; countdown if scheduled. No confirmation friction (locking should be easy).

**6.4 Locked screen (when opening a blocked app/site):** calm block page — "You're in a session. Unlock by plugging in your key." Shows remaining time and, if enabled, the emergency path.

**6.5 Unlock:** plug in key → verified → unlocked toast, timer stops, blocked things restored. If a non-key device is plugged: "That's not your key" (never reveal which device is the key beyond what the user enrolled).

**6.6 Emergency:** rationed; requires typing a confirmation phrase; optionally a short forced delay; decrements the counter visibly.

**6.7 Recovery/rotation:** lost-key flow → spend emergency or enter recovery mode → re-enroll; docs link.

**6.8 Settings:** block lists, schedules, strict mode, physical-switch mode, key(s), emergency budget, launch-at-login, analytics, uninstall.

**6.9 Error states:** key not recognized; permission revoked mid-session; extension failed to load; clock changed (anti-cheat on timers); disk read error on Tier B.

---

## 7. System architecture

### 7.1 Components
```
┌──────────────────────────────────────────────────────────────┐
│ Deadbolt.app — menu-bar UI (SwiftUI MenuBarExtra)             │
│  onboarding · policy editor · state · unlock prompt           │
└───────────────┬──────────────────────────────────────────────┘
                │ NSXPCConnection (client code-signature validated)
┌───────────────▼──────────────────────────────────────────────┐
│ Deadboltd — root LaunchDaemon (SMAppService.daemon)            │
│  · owns lock state, key registry, emergency counter           │
│  · KeyMonitor: DiskArbitration + IOKit notifications          │
│  · Scheduler · Enforcement coordinator · audit log            │
└──────┬──────────────────────┬──────────────────────┬──────────┘
       │                      │                      │
┌──────▼──────────┐  ┌────────▼─────────┐  ┌─────────▼───────────┐
│ Network Extension│  │ Process enforcer  │  │ Key verifier         │
│ DNS proxy (v1) / │  │ terminate+block   │  │ fingerprints, token, │
│ content filter   │  │ blocked bundles   │  │ (v2) challenge-resp. │
└──────────────────┘  └───────────────────┘  └──────────────────────┘
```

### 7.2 Process & privilege model
- **App** (user): UI only; cannot change lock state directly.
- **Daemon** (root, `SMAppService.daemon` on macOS 13+): authority over lock, keys, schedules, enforcement. Registered once, user-approved.
- **Network Extension** (system extension): DNS proxy (v1) → content filter (v2). Requires Network Extensions entitlement; Developer ID distribution allowed (Apple TN3134).
- **XPC:** NSXPCConnection; both sides validate the peer's code-signing requirement (same team ID).

### 7.3 State machine & persistence
States: `unlocked`, `locking`, `locked`, `unlocking` (key seen, verifying), `unlockedGrace`.
Persistence: root-owned `/Library/Application Support/Deadbolt/state.json` (owner `root:wheel`, mode `600`), so deleting the app or editing user prefs doesn't clear the lock. Tamper monitoring recreates the daemon/plist if removed (while locked).

### 7.4 Data model (root-owned)
- `KeyRecord { id, tier, vendorID, productID, serialHash?, containerID?, volumeUUID?, tokenHash?, displayName, strength, createdAt, lastUsedAt }`
- `Policy { presets[], domains[], blockedBundleIDs[], allowOnly, allowlist[], schedules[], strictMode, physicalSwitchMode }`
- `LockState { state, reason, startedAt, endsAt?, activePolicyId }`
- `Emergency { usedThisPeriod, periodStart, allowance }`
- `AuditLog { ts, event }` (local only)

### 7.5 Enforcement engine
- **Websites:** DNS proxy returns NXDOMAIN/blocked for denylist (or non-allowlist) hostnames; also blocks known DoH resolver endpoints. v2 content filter inspects flows (defeats DoH/VPN).
- **Apps:** daemon subscribes to `NSWorkspace` launch/activate notifications; on blocked bundle ID → `terminate()`, repeat on relaunch; optional network-cut fallback. Allow-Only kills everything not allowlisted (Cold Turkey "Micromanager" model).
- **Strict mode:** extension cannot be disabled mid-session; uninstall requires unlock; timers resilient to clock changes.

### 7.6 Key monitor
Runs on the daemon's run loop: a `DASession` for storage + an `IONotificationPort` for USB. Emits `keyAttached(fingerprint)` / `keyDetached(fingerprint)`; verifier compares against the registry.

---

## 8. Anti-bypass & threat model

| Bypass | Counter |
|---|---|
| Click ignore / snooze | No such control exists |
| Quit the app | Enforcement in daemon + extension |
| Reopen blocked app | Terminate + relaunch block |
| Another browser/app to reach a site | Network-layer, system-wide (Opal's weak spot) |
| DoH/VPN | v1 blocks DoH resolvers; v2 content filter |
| Uninstall / disable extension | Root-owned state; uninstall requires unlock |
| Edit `/etc/hosts` | Not hosts-based |
| Plug in *a* USB device | Only the enrolled fingerprint works |
| Spoof the key's serial | Possible on programmable USB (Tier A/C/D); Tier B binds to volume UUID; **YubiKey challenge-response (v2)** resists cloning |
| Recovery Mode / other OS | Out of scope — friction, not DRM |

**Adversary:** the user themselves, in a weak moment. Optimize for friction and precommitment, not cryptographic security.

---

## 9. Security & privacy
- Key fingerprints **hashed** at rest; raw secrets never in user-space or telemetry.
- Tier B token: 256-bit random, stored root-owned; the drive holds a hash, not the secret.
- No account; no network calls except license check + update check (both optional/offline-friendly).
- Audit log local only.
- System extension sandboxed by Apple (cannot exfiltrate network content).

---

## 10. Distribution, signing, updates, licensing
- **Signing:** Developer ID Application + Installer; Developer ID; hardened runtime.
- **Notarization + stapling**; ship a signed `.dmg`.
- **System extension** approval flow scripted in onboarding (System Settings → Privacy & Security → Network Extensions).
- **Entitlements:** `com.apple.developer.networking.networkextension` (DNS proxy / content filter). Request from Apple; Developer ID path is permitted for these provider types.
- **Updates:** Sparkle 2 (EdDSA-signed appcast) or custom updater.
- **Licensing:** offline signed license key via LemonSqueezy/Paddle/Gumroad; no phone-home required. One-time purchase.
- **Mac App Store:** excluded (system extensions can't ship there).

---

## 11. Tech stack & repo structure
**Stack:** Swift + SwiftUI (`MenuBarExtra`), `NetworkExtension`, `ServiceManagement`/XPC, `DiskArbitration`, `IOKit` (`IOUSBHostDevice`), `CryptoKit`, `CryptoTokenKit`/PC-SC (YubiKey), Sparkle.

```
deadbolt/
  Deadbolt.xcodeproj
  App/            # SwiftUI menu-bar app, onboarding, settings
  Daemon/         # root LaunchDaemon (SMAppService), state, XPC server
  KeyMonitor/     # DiskArbitration + IOKit watchers + fingerprinting
  NetExt/         # DNS proxy system extension (v1); content filter (v2)
  Enforcer/       # app terminate/relaunch guard
  Shared/         # models, XPC protocol, hashing, constants
  CLI/            # `deadbolt lock|status|enroll` (dev + power users)
  Tests/          # unit + integration + adversarial
  Scripts/        # signing, notarize, dmg, sparkle
  docs/
```
**Key modules:** `Fingerprint` (identity tiers + placeholder rules), `KeyRegistry`, `LockController` (state machine), `PolicyStore`, `Scheduler`, `Enforcement`, `XPCService`, `ExtensionManager`.

---

## 12. Testing & QA
- **Unit:** identity tiers, placeholder rejection, state machine, scheduler DST/timezone, token hashing.
- **Integration:** enroll+lock+unlock per device type; sleep/wake; reboot; multi-user; FileVault; extension load failure.
- **Hardware matrix:** thumb drives, SD cards, external SSD, YubiKey, mouse receivers (no serial → Tier D warning), dev boards (serial), hubs (placeholder → refused), composite devices.
- **Adversarial/bypass suite:** kill app, disable extension, edit prefs, remove root state, plug a different USB, spoof a serial, change clock, safe-boot.
- **OS matrix:** macOS 13, 14, 15, 26.
- **Dogfood:** you run it daily for ≥2 weeks before beta.

---

## 13. Metrics & telemetry (privacy-preserving, opt-in)
- Activation: % completing extension approval + first lock.
- Core value: sessions completed without emergency; median locked hours/day; 7/30-day retention.
- Bypass: emergency uses per user/month.
- Reliability: scheduled-lock fire rate (target >99.9%).
- Unlock UX: median "want out → unlocked" time.

---

## 14. Roadmap & milestones

| Milestone | Scope | Est. |
|---|---|---|
| **M0 — Spike** | Menu-bar app + per-user helper; USB fingerprinting (DA + IOKit); enroll any device; Lock/Unlock gated on key; `/etc/hosts` + simple app-kill; timer. Dogfood. | 1–2 wks |
| **M1 — Core MVP** | root LaunchDaemon (SMAppService) + XPC; robust KeyMonitor; DNS proxy system extension + DoH blocking; app enforcer; policy editor; schedules; strict mode; emergency; menu-bar UX. | 4–6 wks |
| **M2 — Productize** | Onboarding polish; key strength UX; notarize + DMG; Sparkle; licensing; landing page + docs; analytics; crash reporting. | 3–5 wks |
| **M3 — Beta/Launch** | Private beta (direct), fix list, support docs, launch (r/macapps, HN, PH, Brick community), "Brick for Mac" demo video. | 2–4 wks |
| **M4 — v2** | Content filter (DoH-proof); YubiKey challenge-response; custom USB-C key dongle; iPhone companion + one-key-sync. | 8–12 wks |

---

## 15. Business, GTM, moat, competition
- **Pricing:** one-time **$29–$39**. Optional **USB-C Key dongle** $25 (hardware-first identity). No subscription (matches Brick/Cold Turkey culture; undercuts Opal $99.99/yr and Freedom $39.99/yr).
- **GTM:** Brick owners (community/Reddit) → Opal/Freedom churn-outs → r/macapps / r/digitalminimalism / r/ADHD → Hacker News + Product Hunt → "I built Brick for the Mac" video. Optional partnership pitch to Brick.
- **Moat:** system-extension engineering + anti-bypass reliability + physical-key UX — structurally hard for App-Store-only indies; Opal's Mac app is browser-puppeteering and has no physical key; Brick has no Mac at all.
- **Expansion:** "One key. Every screen." — unify phone (Screen Time API) + Mac behind one physical key; a product neither incumbent has.

---

## 16. Risks & mitigations
| Risk | Mitigation |
|---|---|
| DoH/VPN bypass (v1 DNS layer) | Block DoH resolvers; ship content filter in v2 |
| Key detection flakiness / weak USB identities | Strength tiers + placeholder rejection + Tier B token + clear UX; dogfood matrix |
| System-extension permission friction | Scripted onboarding; it's the top activation risk |
| App blocking is kill-and-relaunch (no OS shield) | Reliable daemon + relaunch guard; honest framing |
| Apple platform churn | Stick to documented APIs (TN3134); adopt macOS 26 URL filter when viable |
| Incumbent shipping a real Mac app | Move fast on anti-bypass + physical key; own reliability |
| User locks themselves out | Emergency budget + recovery doc |
| Legal/naming ("Brick") | Distinct brand; trademark check |

---

## 17. Open decisions
1. Tier A default key recommendation in onboarding: suggest a **spare thumb drive** vs let users pick freely? (Recommend: suggest, but allow any.)
2. Support **multiple keys** in v1 or v1.1? (Recommend v1.1, ship 1.)
3. **Physical-switch mode** default off? (Recommend off.)
4. **YubiKey strong mode** in v1 or v2? (Recommend v2.)
5. Pricing: **$29 vs $39**, and free-trial vs paid-only? (Recommend $29 launch.)
6. Build a **custom dongle** SKU, or stay bring-your-own-USB? (Recommend BYO first, dongle later.)

---

## 18. Appendix

**APIs referenced:** `SMAppService.daemon(plistName:)` (macOS 13+) · `DiskArbitration` (`DADiskCopyDescription`, volume/media UUID, internal/removable keys) · `IOUSBHost` / `IOUSBHostDevice`, `serialNumberString`, `containerID`, `kUSBSerialNumberString`, VID/PID · `NEFilterDataProvider` / DNS proxy · YubiKey HMAC-SHA1 challenge-response over USB HID.

**On-machine findings (M4 Pro, macOS 15.6):** USB serials exposed (`A1:B2:C3:D4:E5:F6` ESP32; `0A1B2C3D4E5F6` bridge); placeholder serials on cheap hubs (`000000000`); no serial on Logitech receivers; distinct `Volume UUID` per volume; built-in SD reader present. This is why the identity ladder and placeholder rejection exist.

**Glossary:** *Key* = the enrolled USB device. *Tier* = identity strength. *Bound storage* = a drive whose UUID+token identify it. *Strict mode* = no override/cancel. *Emergency unbrick* = rationed escape hatch.
