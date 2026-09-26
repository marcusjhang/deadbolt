# PRODUCT.md — "Deadbolt" (working name)
### The Mac focus blocker you can't click past — unlocked only by a physical key you leave behind.

*Companion to `market-research.md` and `usb-key-design.md`. This is the converged recommendation.*

---

## 1. The one-sentence product

**A menu-bar Mac app that removes distracting apps and websites system-wide and locks "off" behind a physical key — a USB stick / SD card / security key you keep in a drawer — so ending a focus session requires getting up, retrieving it, and plugging it in, exactly like Brick does for your phone.**

Working name candidates: **Deadbolt** (recommended) · Latch · Keystone · Out-of-Reach · Pocket Key. All need a trademark check; "Brick" must not be used in the name.

Tagline options:
- *"Brick, for the Mac."*
- *"The key to your attention shouldn't be on your keyboard."*
- *"One key. Every screen."* (phase 2 vision — see §10)

---

## 2. Why this specific product (evidence, not vibes)

| Signal | Source | What it means |
|---|---|---|
| Brick is **phone-only** (iPhone + Android); no desktop category in support; no Mac app | getbrick.app, getbrick.com/pages/faq, support.getbrick.com | The most-loved commitment device in the category has no Mac half |
| Opal users **explicitly beg for desktop**: "I wish I could put it on my PC," "I just wish it worked for Windows desktop so I can track my video games" | Opal App Store reviews (App Store id 1497465230) | Proven demand for a desktop blocker; Opal even replies "we're working on expanding across platforms" |
| Opal's Mac app blocks sites by **controlling browsers** (Automation permission; only Chrome, Safari, Opera, Edge, Brave, Arc) | Opal help: "How do I use the Mac App" | Competitor's Mac website blocking is browser-puppeteering → leaks Firefox/Comet/etc., needs the app open, no anti-disable on Mac |
| Opal Mac has **no app uninstall protection, no Screen Time-passcode equivalent, no device sync, one session at a time** | Opal help: Mac app + "How do I make Opal foolproof" | The Mac anti-bypass story is weak; big opening for "can't click past" |
| Opal's own users say **the value is "even uninstalling doesn't remove the block — it's brutal"** and "I cannot cancel once it starts" | Opal App Store reviews | The winning axis is **unoverrideable**, not features |
| Brick's most-complained bug is **schedule reliability** | Brick App Store reviews | Reliability is a differentiator we can own |
| Apple's Screen Time APIs are **not available on native macOS**; macOS **content filter / DNS proxy system extensions** are allowed outside the App Store | Apple docs (FamilyControls, TN3134) | Defensible technical moat: serious Mac blockers must be system-extension work, which App-Store-only indie devs avoid |
| MacBooks have **no NFC reader**, but they expose USB serials and disk UUIDs | Apple M4 Pro tech specs; on-machine IOKit/DiskArbitration inspection | Physical key = a USB device (spare drive, SD card, YubiKey, custom dongle). See `usb-key-design.md` |

**Conclusion:** build the **OS-level, unoverrideable, physical-key Mac blocker**. Nobody occupies that spot. It is technically harder than the App Store crowd will attempt, which is exactly why it's defensible.

---

## 3. Target users (in priority order)

1. **Brick owners who work on a Mac** — already believe in the mechanic; the Mac is their unguarded screen. *Primary.*
2. **Opal / Freedom / Cold Turkey power users who out-grew override buttons** — their reviews are full of "I just turned it off / hit ignore 15 more minutes." *Primary.*
3. **ADHD / deep-work knowledge workers** who buy commitment devices (kSafe, Pavlok, Unpluq, YubiKey-style tools). *Secondary.*
4. **Students** (Brick targets exam prep heavily; a Mac + phone combo is the student setup). *Secondary.*
5. **Parents** — deferred (needs MDM-style family controls; different product).

---

## 4. The core loop (the whole product in four beats)

1. **Choose** what's off-limits — presets (Social, Video, News, Games) + custom apps and domains + an **Allow Only** mode (block everything except a work allowlist: Slack, Figma, GitHub, Zoom…).
2. **Lock** — click Lock (or hit a schedule). Blocked apps vanish/quit; blocked sites stop resolving in **every** browser and app.
3. **Live** — a menu-bar timer counts up. There is no "ignore," no "5 more minutes," no one-click off.
4. **Unlock** — retrieve your physical key (a USB stick / SD card / security key you left in a drawer), plug it in. *That* is the only way off. Emergencies are covered by a small, rationed budget.

**Design law (inherited from Brick):** activation may be remote; **deactivation requires the physical key.**

---

## 5. Feature set

### v1 (ship this)
- **System-wide website blocking** — DNS proxy (or content filter) Network Extension system extension. Works in *every* browser (Safari, Chrome, Firefox, Arc, Comet, Perplexity…) and in native apps, not just a browser allowlist. Also disables known **DoH resolvers** so browsers can't tunnel past it.
- **App blocking** — privileged helper watches `/Applications` launches and foreground app switches; terminates + refuses relaunch of blocked bundle IDs. Optional network-cut fallback if an app can't be killed cleanly.
- **Physical unlock (USB key)** — the key is a USB device (spare USB-C drive, SD card, YubiKey, or custom dongle). Detected via DiskArbitration (storage keys: volume UUID + hidden token) and IOKit (serial keys). No camera, no printing. See `usb-key-design.md`.
- **Strict mode / Hard core** — no snooze, no early end; system extension + daemon can't be turned off while locked; app can't be uninstalled mid-session.
- **Modes & schedules** — Work / Deep Work / Evening / Sleep; recurring schedules; **reliable** by construction (a top Brick complaint — own it).
- **Emergency unlock budget** — e.g., 2 per month with a cooldown (Opal: 1/week; Brick: 5 lifetime). Show it, ration it.
- **Analytics that don't judge** — time blocked, sessions completed, lock streak. No shame copy (a stated reason people prefer Brick to Opal).
- **Menu-bar-first UX**, tiny surface area, no dashboard bloat.

### v2 (differentiators)
- **Alternate keys** — YubiKey challenge-response (uncloneable) as a power option; optional USB NFC reader so the user's existing **Brick** can be the key ("your Brick unlocks your Mac").
- **Content filter upgrade** — move from DNS-layer to `NEFilterDataProvider` for DoH/VPN-proof blocking.
- **Cross-device lock** — an iPhone companion app (Apple's Screen Time API *is* available on iOS) using the same physical key, so one key locks phone **and** Mac. See §10.
- **Focus shield** — optional full-screen "you're in a session" overlay.

### Explicit non-goals for v1
Windows, Mac App Store (can't ship system extensions), browser-extension-only blocking, parental/MDM controls, subscription-first pricing, "impossible to bypass" claims (dishonest).

---

## 6. Anti-bypass design (this is the product)

| Bypass attempt | How we stop it |
|---|---|
| Click "ignore" / "5 more minutes" | No such control exists in-app |
| Quit the app | Enforcement lives in a **root LaunchDaemon** (SMAppService) + system extension, not the UI app |
| Reopen a blocked app | Daemon terminates + blocks relaunch while locked |
| Use another browser / app to reach a site | Network-layer block is system-wide, not browser-scripted (Opal's weak spot) |
| Turn on DoH to escape DNS blocks | Blocklist includes known DoH resolver hostnames/IPs; v2 content filter ignores DNS entirely |
| Uninstall / disable the extension | Root-owned state + tamper monitoring; extension can't be toggled off mid-session; uninstall requires unlock |
| Just edit `/etc/hosts` back | Enforcement is not hosts-based; state is root-owned |
| Recovery Mode / boot other OS | Out of scope — we sell **friction and commitment**, not invincibility (Brick doesn't claim invincibility either) |

**Onboarding reality to plan for:** the app will ask for (a) Network Extension/system-extension approval in System Settings, and (b) enrollment of the USB key (no OS permission is needed to enumerate USB/disk devices on macOS). Script this flow carefully — it's the #1 adoption risk.

---

## 7. Positioning

- **Category:** commitment-device software for the Mac (not "another screen-time app").
- **For:** people who have already tried — and defeated — Opal, Freedom, Cold Turkey, and Screen Time's own limits.
- **Against:** *"Every Mac blocker lets you turn it off. This one makes you go get the key."*
- **Tone:** calm, non-judgmental, no shame, no gamified gems/streaks-as-guilt (contrast with Opal's gem/leaderboard layer).
- **Proof:** the physical key; the absence of an off switch; reliability.

---

## 8. Business model & distribution

- **Distribution:** notarized **Developer ID `.dmg`**, direct download (required — system extensions can't ship on the Mac App Store). Consider Setapp as a secondary channel.
- **Pricing:** **one-time $29–$39** to match the niche's anti-subscription culture (Brick: $59 hw, no sub; Cold Turkey: one-time; Opal $99.99/yr; Freedom $39.99/yr). Optional later: sell a branded **USB-C Key** dongle for ~$25 as an upsell — mirror Brick's hardware-first identity.
- **Positioning wedge for the first 1,000 users:** Brick's own community + Opal churn-outs + r/macapps + Hacker News + a "I built Brick for the Mac" demo video.

---

## 9. Metrics that matter

- **Activation:** % who complete setup (extension approved + first lock).
- **Core value:** sessions completed without emergency unlock; median locked hours/day; 7-day and 30-day retention.
- **Bypass rate:** emergency-unbrick uses per user per month (target: low but non-zero).
- **Reliability:** scheduled-lock fire rate (must beat Brick's reputation here).
- **Unlock UX:** median time from "want out" to unlocked (should feel deliberate, not broken).

---

## 10. The moonshot it rolls up into: "One key. Every screen."

Apple gives iOS apps the Screen Time API (`FamilyControls`/`ManagedSettings`) — it just **doesn't exist on macOS**. So:
- The **iPhone side** of a commitment app is buildable the standard way.
- The **Mac side** needs the system-extension work described here.
- **No one has unified both behind one physical key.**

So the roadmap compounds: ship the Mac blocker (wedge) → add an iPhone companion using Screen Time → **one physical key governs phone + Mac.** That's a product Brick can't make (no Mac) and Opal hasn't made (no physical key, weak Mac, no sync). This is the "product we should build," staged.

---

## 11. Build plan

**Phase 0 — Prove the feel (personal, ~1–2 weeks).**
Menu-bar app + root helper; start with a fast `/etc/hosts` blocklist + app-kill loop; **USB-key unlock** (DiskArbitration + IOKit enroll/verify); lock timer + strict flag. *Goal: live with it on Marcus.s M4 Pro (macOS 15.6) and confirm the mechanic feels like Brick.* Known limit: DoH/VPN can bypass — acceptable for the spike. Details in `usb-key-design.md` §9.

**Phase 1 — Make it real (product, ~4–8 weeks).**
DNS proxy system extension (system-wide, all browsers/apps) + DoH-resolver blocking; harden daemon (root-owned state, SMAppService, tamper monitoring, unlock verification in the daemon); polished onboarding for extension approval; notarize; `.dmg`; checkout; landing page.

**Phase 2 — Differentiate.**
Content filter for DoH-proof blocking; YubiKey challenge-response + custom USB-C key dongle; iPhone companion (Screen Time API) + one-key-sync.

**Stack:** Swift + SwiftUI (`MenuBarExtra`), `NetworkExtension`, `SMAppService`/XPC, `DiskArbitration` + `IOKit` (`IOUSBHostDevice`) for key detection, `CryptoTokenKit`/PC-SC for YubiKey. Native, no third-party runtime. Your machine already has Xcode/Swift.

---

## 12. Risks & honest caveats

- **DoH/VPN bypass** at the DNS layer → mitigated by content filter (v2) and by blocking DoH resolvers (v1).
- **Permission friction** (system extension approval) → invest in onboarding; it's the top activation risk.
- **Apple platform churn** → stay on documented APIs (TN3134); macOS 26 adds a URL-filter provider we can adopt.
- **Incumbent risk** → Opal is actively "expanding across platforms" and now has a Mac app (weak); Brick has no desktop. Move fast on the anti-bypass + physical-key angle, which is structurally hard for App-Store-only players.
- **App blocking is kill-and-relaunch**, not a true OS shield (Apple gives no third-party app shield on Mac) → frame as friction/commitment, and keep it reliable.
- **"Who watches the watchman"** — user locks themselves out → rationed emergency budget + clear recovery doc.

---

## 13. The decision

**Build Deadbolt (working name): a notarized, system-extension-based Mac focus blocker whose "off" is a physical USB key (spare drive / SD card / YubiKey / custom dongle) — positioned as the missing Mac half of the Brick/commitment-device world.**

- **Do first:** the Phase 0 USB-key spike to validate the feel.
- **Then:** the DNS-proxy system extension + hardened daemon to make it unoverrideable and system-wide.
- **Don't:** build a browser extension, put it on the Mac App Store, or ship before onboarding for the extension permission is polished.

If you want, the next step is a Phase 0 build spike — a menu-bar app + root helper + USB-key unlock that actually locks a blocklist on this machine.
