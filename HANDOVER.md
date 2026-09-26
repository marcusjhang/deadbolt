# Handover — Deadbolt

**Read this first.** Everything needed to pick up the project and start building.

- **Date:** 2026-09-26
- **Status:** Product discovery + technical design + full plan complete. **No code written yet.**
- **Next step:** the M0 spike (see [§7](#7-how-to-start-the-m0-spike)).
- **Owner:** Marcus Jhang

---

## 1. What we're building

**Deadbolt** is a macOS focus blocker with a physical key.

- It removes distracting **apps and websites system-wide** — every browser and every app, not just a browser extension.
- **Locking is easy** (menu bar, hotkey, or schedule).
- **Unlocking requires a physical USB device you enrolled and stashed away.** Plug it in to end the session. There is no "ignore," no snooze, no one-click off.
- **The key is any generic USB device you already own** — a spare thumb drive, an SD card, a YubiKey, an old mouse dongle, a dev board. No purchase, no special hardware.

Working name is **Deadbolt** (trademark check pending). Do **not** use "Brick" in any product name — it is another company's trademark.

**Taglines:** *"Brick, for the Mac."* · *"Any USB stick is the off-switch."*

---

## 2. Why this is worth building (the gap)

| Finding | Source |
|---|---|
| Brick is **phone-only** (iPhone + Android); no desktop app. | getbrick.com FAQ, support.getbrick.com, App Store |
| Opal users explicitly ask for a desktop version; Opal says it's "expanding across platforms." | Opal App Store reviews |
| Opal's **Mac app blocks by controlling browsers** via Automation permission (only Chrome/Safari/Opera/Edge/Brave/Arc) — leaks other browsers, needs the app open, no anti-disable, no sync. | Opal help: "How do I use the Mac App" |
| The winning axis is **unoverrideable**, per users themselves ("even uninstalling doesn't remove the block"). | Opal App Store reviews |
| **Apple's Screen Time APIs are not available on native macOS** (iOS/iPadOS/macCatalyst/visionOS only). macOS content-filter/DNS-proxy Network Extensions are deployable as system extensions **outside** the App Store. | Apple docs: FamilyControls; TN3134 |
| MacBooks have **no NFC reader**, but expose **USB serials and disk UUIDs**. | Apple M4 Pro tech specs; on-machine IOKit/DiskArbitration inspection |

Full detail + citations: [`docs/market-research.md`](./docs/market-research.md).

---

## 3. Decisions already locked

1. **Form factor:** notarized macOS app (menu-bar first) + root LaunchDaemon + Network Extension system extension.
2. **The key is any generic USB device the user owns.** Bring-your-own-USB; no purchase required. (Optional branded USB-C dongle is a later SKU.)
3. **Lock easy / unlock hard** asymmetry. Explicit Lock + key-to-Unlock by default; optional "pull the key = Lock" physical-switch mode.
4. **Enforcement in a root daemon + system extension**, so it survives quitting the UI app.
5. **Distribution:** Developer ID, notarized `.dmg`, direct download. **Not** the Mac App Store (system extensions can't ship there — this is also the moat).
6. **Pricing:** one-time ~$29–39. No subscription.
7. **One key in v1**, up to 3 in v1.1.
8. **YubiKey challenge-response** strong mode is v2, not v1.

---

## 4. The key mechanism (the crux)

Because "any USB device" ranges from a YubiKey (real unique serial) to a cheap hub (serial `000000000`), enrollment builds a **fingerprint on a strength ladder** and is honest about it:

| Tier | Identity | Strength | Notes |
|---|---|---|---|
| **A** | Real unique serial (`kUSBSerialNumberString`) + VID/PID | Strong | Best case |
| **B** | Volume UUID (`kDADiskDescriptionVolumeUUIDKey`) + hidden 256-bit token file | Strong | For drives/cards with no serial |
| **C** | `IOUSBHostDevice.containerID` + VID/PID | Medium | May reset on some hubs |
| **D** | VID/PID + vendor/product strings | Weak | Matches any identical model; requires explicit consent |
| **E** | Placeholder serial only | Refused | e.g. hubs reporting `000000000` |

**Placeholder rejection** (all-zero, repeated-char, <4 chars, or equal to VID/PID) is essential — verified on the dev machine where several cheap hubs reported `000000000`.

**Detection:** DiskArbitration for storage keys, IOKit (`IOUSBHostDevice`) for serial keys. **Never match on `locationID`** (changes with port/hub). Enrollment UI shows a live "key strength" badge and steers users to a *spare, removable* device (an always-connected device = no friction).

Full design: [`docs/usb-key-design.md`](./docs/usb-key-design.md).

---

## 5. Architecture (summary)

```
Deadbolt.app (menu-bar UI, SwiftUI)
      │  XPC (code-signature validated)
Deadboltd (root LaunchDaemon via SMAppService)
      │  owns lock state, key registry, schedules, emergency budget
      ├── KeyMonitor  (DiskArbitration + IOKit)
      ├── Network Extension system extension  (DNS proxy v1 → content filter v2)
      └── Process enforcer  (terminate + block relaunch of blocked apps)
```

- **App:** UI only; cannot change lock state directly.
- **Daemon:** authority; root-owned state at `/Library/Application Support/Deadbolt/` (mode 600) so deleting the app doesn't clear the lock.
- **Network Extension:** `NEDNSProxyProvider` (v1) for system-wide website blocking + DoH-resolver blocking; `NEFilterDataProvider` (v2) for DoH/VPN-proof.
- **Enforcer:** `NSWorkspace` launch/activate notifications → terminate blocked bundle IDs; repeats on relaunch.
- **Entitlement:** `com.apple.developer.networking.networkextension` (request from Apple; Developer ID allowed for these provider types).

---

## 6. Artifacts in this repo

| File | Contents |
|---|---|
| `docs/market-research.md` | Competitive landscape + macOS feasibility, with primary-source citations. |
| `docs/product-summary.md` | Condensed product definition, users, positioning, pricing, roadmap. |
| `docs/usb-key-design.md` | USB-key identity ladder, detection APIs, edge cases, security model, spike plan. |
| `docs/product-plan.md` | Full plan: features (v1/v1.x/v2), UX flows, architecture, data model, anti-bypass, distribution, testing, roadmap, GTM, risks. |

---

## 7. How to start (the M0 spike)

**Goal:** prove the feel on the dev machine (Apple M4 Pro, macOS 15.6). ~1–2 weeks.

1. **Menu-bar app** (SwiftUI `MenuBarExtra`) with a per-user helper (skip the root daemon for the spike).
2. **Key enrollment** — list attached USB/storage devices with identities; enroll one; show strength tier.
   - IOKit: match `IOUSBHostDevice`, read `kUSBSerialNumberString` + `kUSBVendorID`/`kUSBProductID`.
   - DiskArbitration: `DADiskCopyDescription` → volume UUID; reject internal/fixed disks.
3. **Lock/Unlock state machine** gated on the enrolled key being attached.
4. **Trivial enforcement** — start with `/etc/hosts` blocklist + terminate 1–2 blocked bundle IDs.
5. **Menu-bar lock timer.**
6. **Dogfood for ≥1 week** — confirm enrollment is painless, the key is recognized across ports and after sleep/reboot, and the "go get the key" friction feels right.

Then promote the helper to a root `SMAppService` daemon and add the DNS-proxy system extension. Milestones M0→M4 are in [`docs/product-plan.md`](./docs/product-plan.md) §14.

**Stack:** Swift + SwiftUI, `NetworkExtension`, `ServiceManagement`/XPC, `DiskArbitration`, `IOKit` (`IOUSBHostDevice`), `CryptoKit`, `CryptoTokenKit`/PC-SC (YubiKey), Sparkle.

**Watch out for in the spike:** placeholder serials on cheap devices, mount-timing races, and re-verifying the key after wake-from-sleep.

---

## 8. Open decisions

1. Onboarding recommends a **spare thumb drive** but allows any device — confirm approach.
2. **1 key in v1** vs up to 3 now.
3. Physical-switch mode default **off** — confirm.
4. YubiKey strong mode v1 vs v2 (currently v2).
5. Price **$29 vs $39**; free trial vs paid-only.
6. Custom dongle SKU later vs bring-your-own-USB only (currently BYO first).
7. Final product name + trademark check.

---

## 9. Risks & honest limits

- **DoH/VPN can bypass** a DNS-layer block; v1 also blocks DoH resolvers, v2 moves to a content filter.
- **System-extension permission** is the top activation risk — onboarding must be polished.
- **App blocking is kill-and-relaunch**, not an OS shield (Apple gives no third-party app shield on Mac). Frame as friction, keep it reliable.
- **A determined admin can always bypass** (Recovery Mode, disabling the daemon, another OS). We sell commitment, not DRM.
- **USB identity can be weak** (Tier D) or spoofable; strong mode (YubiKey challenge-response) is the answer for the paranoid.

---

## 10. Glossary

- **Key** — the enrolled USB device used to unlock.
- **Tier** — identity strength class (A–E).
- **Bound storage** — a drive identified by volume UUID + token file (Tier B).
- **Strict mode** — no override/cancel; resists disabling while locked.
- **Emergency unbrick** — rationed escape hatch (default 2/month).
- **One key. Every screen.** — v2 vision: same physical key unlocks phone (iOS Screen Time API) and Mac.
