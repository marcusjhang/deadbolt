# "Brick for the MacBook" — Product Discovery & Technical Feasibility

**Author:** Marcus Jhang
**Date:** 2026-09-26
**Status:** Deep research complete. Recommendation included. No code written.
**One-line thesis:** Brick is a phone-only, hardware-key commitment device. There is **no true Mac equivalent** — and, importantly, the *easy* Mac approach (Apple's Screen Time API) is **not available on macOS**, so a real product must be built at the network/privileged-helper layer. QR is a fine physical key for Mac because **MacBooks have no NFC reader**.

---

## 0. TL;DR / Recommendation

1. **The gap is real and confirmed.** Brick (getbrick.com) works with iPhone + Android only. Its own site says "Works with iPhone & Android." No Mac app. Opal has a Mac app but it is explicitly **sessions/websites only** — "App Limits and Locks will come at a later date" and iPhone sync "coming later."
2. **The naive plan fails.** You cannot copy Brick's iPhone mechanism to Mac because Apple's Screen Time stack (`FamilyControls` / `ManagedSettings` / `DeviceActivity`) is **not available on native macOS** — only iOS, iPadOS, macCatalyst, and visionOS. See §6.1.
3. **The real Mac mechanism is a Network Extension (content filter or DNS proxy) shipped as a system extension via Developer ID**, plus a privileged helper that kills/quits blocked apps. macOS content filters are explicitly allowed outside the App Store (TN3134). See §6.2–6.4.
4. **Physical key:** MacBooks have no NFC reader (confirmed in Apple's M4 Pro tech specs — Wi-Fi 6E + Bluetooth 5.3 only). So the key is either (a) a **QR code scanned by the built-in/Continuity camera**, (b) a **USB NFC reader** — which could even read *the Brick you already own*, or (c) an iPhone acting as reader/relay. See §5.
5. **Recommended v1:** a notarized menu-bar Mac app + root LaunchDaemon that (i) enforces a blocklist system-wide via a **DNS proxy or content filter system extension**, (ii) terminates blocked apps, (iii) locks "off" until a **QR code is physically scanned** (or an NFC tag is tapped if you add a reader). Strict mode + limited emergency unbricks. Direct distribution (.dmg), not Mac App Store. See §8–§9.
6. **Biggest technical risk:** DNS-over-HTTPS (DoH). Any `/etc/hosts`- or plain-DNS-based block is bypassed by Chrome/Firefox DoH and by VPNs. This is *the* reason to prefer a content filter or a DNS proxy that also blocks DoH resolvers. See §6.6 and §11.

**Confidence:** High on the strategic gap and on the macOS API landscape (primary Apple docs + Brick's own site/App Store). Medium on individual competitor internals (their private implementations are inferred from public feature claims). Flagged inline where inferred.

---

## 1. What Brick actually is (primary sources)

From Brick's own site (getbrick.app / getbrick.com), FAQ, and the App Store listing (`Brick - Ditch Distractions`, id 6448794069, Brick LLC (Wisconsin)):

- **Hardware + app.** Passive, **battery-free** NFC tag shaped like a brick. "With no battery to charge, your Brick is always on."
- **Mechanic:** choose apps/sites → **tap phone to Brick** to activate → apps removed/blocked → **you must physically tap again to unblock.** Remote *activation* is possible in-app, but **remote unblock is not** — you still need the physical device. This is the commitment device.
- **Positioning** is explicitly against override-able solutions. Their comparison table lists Screen Time limits ("Easy to ignore"), deleting apps ("Easy to reinstall"), and grayscale ("Easy to undo") — all defeated by the fact that "the key that re-enables distractions is always within reach." Brick = "leave that key behind."
- **Strict Mode** "closes the loopholes and prevent[s] deleting the app or changing settings to unbrick."
- **5 Emergency Unbricks** included ("Accidents happen").
- **10 custom modes**, schedules, focus timer, analytics; **no subscription** ("Buy once, use forever"); local-only block lists.
- **Platform: iPhone (iOS 17+/18+) and Android 12+.** Not macOS. Not desktop.
- **Traction/social proof:** 55K ratings, 4.9; featured in NYT, WSJ, CNN, Economist, Fortune, Vogue, TechCrunch, CNET, Fast Company, WaPo, Business Insider, New Yorker; HSA/FSA eligible via Truemed.
- **Price:** The Brick listed at **$59** (collection page; product JSON shows a $77 list price currently discounted), Brick Case $51, Brick Mount $20 (shopify `products.json`).
- **Known weakness (verbatim reviews):** schedule reliability — "Scheduling portion… rarely works," "the brick won't unbrick when it is scheduled to." Also one reviewer chose Brick *over* Opal because Opal felt "annoying, intrusive and somewhat judgmental." Reliability and non-judgmental tone are openings.

Sources: `getbrick.app`, `getbrick.com/pages/faq`, `getbrick.com/collections/all`, `getbrick.com/products.json`, Apple App Store listing.

---

## 2. Why Brick works (behavioral science)

Brick is a textbook **commitment device / Ulysses contract**: a voluntary, costly-to-reverse arrangement made in a "cool" state that binds your "hot" future self.

- **Precommitment beats willpower.** kSafe (the time-lock container, Shark Tank) frames its whole product on this and cites Duhigg (*Power of Habit*), McGonigal (*Willpower Instinct*), and Baumeister (*Willpower*) — "precommitment… doubled the odds of reaching goals." The key property: **no overrides.**
- **Friction changes behavior at scale.** one sec's peer-reviewed research (Max Planck / PNAS 2023; CHI 2024) shows a brief forced pause cuts app openings ~57%. one sec is *deliberately gentle* (friction, not lock) and works precisely because it interrupts the automatic loop.
- **Physical separation is the differentiator.** Unpluq ($38 + subscription, 250k+ users) uses the same "tag is your key" idea and markets it as "putting the cookie jar on a higher shelf." Brick's edge over Unpluq/Opal/pure-software is that the key is *physically away from the device*.
- **Two design poles to choose between:**
  - **Hard commit (Brick/Cold Turkey/kSafe):** block cannot be lifted without the key. Higher relief, higher risk of self-harm in an emergency → needs emergency unlock budget.
  - **Soft friction (one sec/ClearSpace/ScreenZen):** pause, breathe, intent. Lower risk, lower ceiling for heavy users.
  - For a Brick user, **hard commit is the expectation.** Build hard commit, but ship the "5 emergency unbricks" safety valve.

---

## 3. The opportunity: the Mac is the unguarded screen

Brick users consistently report the same pattern: the phone gets bricked, but **work happens on a Mac**, and the Mac is where Slack, YouTube-in-a-tab, news, Reddit, X, and now `TV`/native apps live. Reviewers explicitly praise Brick because it removes the *phone* as the reflex surface — but nothing governs the laptop.

Evidence for the gap:
- Brick supports iPhone + Android only (its own FAQ).
- Opal for Mac exists but is limited: **"You can set-up Sessions to block distracting websites or apps on your Mac. App Limits and Locks will come at a later date."** iPhone↔Mac sync: "coming later this year." So even the best-funded screen-time company has an incomplete Mac product.
- Mac-only incumbents (Session, SelfControl, Cold Turkey) are **override-able in seconds** (quit the app, edit settings, uninstall) — the exact critique Brick levels at phone software.

**Product thesis:** *The missing half of the Brick ecosystem.* A Mac app whose "off" is not a toggle but a physical object, so a Brick user can be device-free on the laptop with the same rigor as the phone.

**Who it's for (segments, ranked):**
1. **Existing Brick owners who work on Mac** (Marcus, and the reviewer cohort) — highest intent, already believe in the mechanic, will pay.
2. **Opal/Freedom/Cold Turkey power users** who have out-grown override-able software (their reviews are full of "I just turned it off").
3. **ADHD / deep-work knowledge workers** who buy commitment devices (kSafe, Pavlok, Unpluq overlap).
4. **Students** (Brick targets exam prep heavily).
5. **Parents** (needs MDM-flavored family controls — different, heavier; not v1).

---

## 4. Competitive landscape (Mac + physical-key)

| Product | Platform | What it blocks | Key / override model | Price model | Weakness to exploit |
|---|---|---|---|---|---|
| **Brick** | iPhone, Android | Apps + selected Safari sites | **Passive NFC Brick**; strict mode; 5 emergency unbricks | $59 hw + free app, no sub | **No Mac. No desktop. No cross-device sync.** |
| **Opal** | iOS, Android, **Mac** | Apps + sites | Software rules; "Hard Mode" | Free; Pro $99.99/yr or $399 lifetime | Mac has **no app limits/locks yet**, no phone sync; users call it intrusive/judgmental |
| **Freedom** | macOS, Win, iOS, Android, Chrome, Linux | Apps, sites, entire internet | Software "Locked Mode" | Free; $39.99/yr or $199 lifetime | Key is always on the machine (temptation within reach) |
| **Cold Turkey Blocker** | macOS, Windows | Sites, apps, keywords, whole internet; **Micromanager** blocks all apps except an allowlist | Software lock; "uninstall prevention"; password | One-time (free tier) | Still software-keyed; no physical device |
| **SelfControl** | macOS (GPL, free) | Websites/hosts + mail servers | Timer; survives restart/app deletion | Free | `/etc/hosts`-based → **defeated by DoH/VPN**; no app blocking; lightly maintained (v4.0.2) |
| **Session** | macOS, iOS | Apps + sites (Safari/Chrome/Brave/Edge) | Software, session timer | Subscription | Not unbypassable; browser-scoped site blocking |
| **one sec** | iOS, Android, browser ext (Win/mac/Linux) | Apps + sites | **Friction** (pause/breathe) not lock | Freemium | Not a lock; no system-wide desktop app blocking |
| **Unpluq** | iPhone, Android | Apps | **NFC tag** as key + digital barriers | $38 + subscription | No Mac |
| **kSafe / Kitchen Safe** | Physical | Anything you put in the box | **Time lock, no override** | ~$50 one-time | Analogue; no software |

**Read:** There is a clean white space at the intersection of **"physical-key commitment"** × **"Mac system-wide enforcement."** Nobody occupies it. Brick owns the first half and is missing the second; Opal owns a quarter of the second and has none of the first.

Sources: `freedom.to`, `getcoldturkey.com`, `selfcontrolapp.com`, `stayinsession.com`, `one-sec.app`, `unpluq.com`, `thekitchensafe.com`, `opal.so/pricing`, `opal.so/mac`.

---

## 5. The physical-key problem on a Mac (no NFC)

**Fact:** MacBooks do not ship an NFC reader. Apple's 14″ MacBook Pro (M4 Pro/Max, 2024) tech specs list wireless as **Wi-Fi 6E + Bluetooth 5.3 only**, and the camera as a 12MP Center Stage cam. No NFC.

So "tap the Mac against the Brick" is impossible as-is. Options, roughly best-to-worst for a v1:

1. **QR code scanned by the Mac camera (recommended, zero extra hardware).**
   - Built-in camera (or iPhone via Continuity Camera) + AVFoundation `AVCaptureMetadataOutput(.qr)` / Vision `VNDetectBarcodesRequest`.
   - The key is a **secret QR code** (a signed/rotating payload) printed on a card, a sticker on a random object, or inside a drawer — matching Marcus's original note: *"scan QR code on any random object."*
   - Ergonomics caveat: the camera lives in the lid; you hold the code up to it. Works, feels deliberate (which is the point).
   - Security: QR must be an unforgeable secret (signed token, not just a URL). Rotate per unlock; never store the plain secret on disk unprotected (put it behind the privileged helper).

2. **USB NFC reader + your existing Brick (best "wow," small hardware cost).**
   - A PC/SC reader (e.g., ACS ACR1252U, ~$40–60) over USB, driven from macOS via CryptoTokenKit/PC-SC, can read the **UID/NDEF of Brick's passive tag**. Your Brick becomes the Mac's key too — a genuinely delightful story: *"the Brick you already own now works on your Mac."*
   - Caveat: needs the Brick's tag to be readable/writable in a standard way; UID read is trivially possible for most NTAG tags. Verify the exact tag family before betting on it. (Medium confidence — I could not confirm Brick's NFC tag IC from public sources.)

3. **iPhone as reader/relay.**
   - Tap iPhone to the Brick, iPhone app relays "unlock Mac" over the network. Most moving parts (two devices, sync, network). Least reliable; not v1.

4. **Other physical tokens (simpler alternatives).** A USB security key (YubiKey) as the key; a specific USB dongle; even "plug in the charger." Easy to enforce, less novel.

**Design principle inherited from Brick:** *activation can be remote, deactivation cannot.* The unlock token must be physically separable and normally stored out of reach.

---

## 6. Technical feasibility on macOS (the core research)

### 6.1 Apple's Screen Time API does **not** exist on native macOS (the key finding)

Apple's `FamilyControls` framework — the thing that makes Brick's iPhone blocking unbypassable — has availability: **iOS 15, iPadOS 15, macCatalyst 15, visionOS 1.0. No macOS.** Its companions (`ManagedSettings`, `DeviceActivity`) are the same. The `com.apple.developer.family-controls` entitlement is likewise iOS/iPadOS/macCatalyst/visionOS only.

**Implication:** You cannot build an Apple-sanctioned "shield" for native Mac apps and websites. The polished iOS approach Brick relies on is off the table. Any competitor (Opal Mac included) must use a different layer. This is *why* the Mac space is weak — and why this is defensible if you do it well.

Sources: Apple Developer docs — Family Controls, Managed Settings, Device Activity frameworks; Family Controls entitlement page.

### 6.2 What *is* available: Network Extensions, shipped as system extensions

Apple's own deployment matrix (TN3134) is unambiguous:

| Provider | Platform | Packaging | Min OS | Restriction |
|---|---|---|---|---|
| **Content filter** (`NEFilterDataProvider`) | **macOS** | **system extension** | **10.15** | **none listed** (i.e., not App-Store-only → Developer ID allowed) |
| DNS proxy | macOS | system extension | 10.15 | none listed |
| Transparent proxy | macOS | system extension | 10.15 | none listed |
| Packet tunnel (VPN) | macOS | system extension | 10.15 | none listed (app-extension form is App Store-only) |
| URL filter (new) | macOS | app extension | **26.0** | none listed |

Notes:
- On **iOS**, content filters require a supervised device or the Screen Time child flow. **On macOS there is no such restriction** — a content filter system extension is a first-class, permitted deployment. This asymmetry is the crux.
- **System extensions cannot be distributed on the Mac App Store.** So a serious Mac blocker is a **Developer ID, notarized, direct-download (.dmg)** product. Expect a one-time user approval in System Settings → Privacy & Security → Network Extensions, plus possibly a restart.
- `NEFilterDataProvider` gets `NEFilterFlow` objects per connection; for WebKit flows it can block the page and even show a custom "block" page. It sees network content in a very restrictive sandbox that **cannot exfiltrate user data** — a good privacy story.

Sources: `NEFilterDataProvider`, "Content filter providers", and TN3134 (Network Extension provider deployment).

### 6.3 The realistic enforcement menu (with honest limits)

| Layer | Blocks websites? | Blocks native apps? | Bypass resistance | Effort | Distribution |
|---|---|---|---|---|---|
| **Content filter (system ext)** | ✅ system-wide, all browsers/apps | ❌ (only their network) | High (works despite DoH/VPN? mostly; beats DNS-layer) | High | Developer ID |
| **DNS proxy (system ext)** | ✅ hostname-level, all apps | ❌ (network only) | Medium (DoH/DoT can bypass unless also blocked) | Medium | Developer ID |
| **Custom DNS / filtering resolver** | ✅ | ❌ | Low (user can change DNS) | Low | any |
| **`/etc/hosts` + helper (SelfControl model)** | ✅ | ❌ | **Low — DoH in Chrome/Firefox & VPN defeat it** | Low | any |
| **Kill/quit blocked apps (NSWorkspace + `kill` from a root LaunchDaemon; Cold Turkey "Micromanager" model)** | ❌ | ✅ (they relaunch → keep killing; hard to uninstall) | Medium–High if daemon is hardened | Medium | Developer ID |
| **Browser extension** | ✅ in-browser only | ❌ | Low | Low | App Store / stores |
| **MDM configuration profile** | ✅ via Web Content Filter payload; app allow/deny via `com.apple.applicationaccess` | ✅ | High | High (MDM/enterprise) | MDM/enterprise |

**Two enforcement layers are needed to match Brick's feel:** network-level (websites + app connectivity) **and** process-level (prevent/terminate blocked apps). Neither Apple API gives you a native "app shield," so app blocking is an active process (kill + relaunch prevention), not a declarative lock.

### 6.4 Privileged helper / anti-bypass (the "strict mode" machinery)

Brick's strict mode and Cold Turkey's "you can't just uninstall it" are the bar. On Mac that means:
- A **root LaunchDaemon** installed via `SMAppService` (modern) or a legacy `SMJobBless` helper, with a tamper-resistant plist (root-owned, monitor-and-recreate, `KeepAlive`).
- Block state stored where the user can't trivially edit it (root-owned file), with the UI reading via XPC.
- To make "off" require the physical key, the *unlock secret verification* should live in the daemon, not the UI.
- SelfControl demonstrates the reach: "you will be unable to access those sites—**even if you restart your computer or delete the application**." Cold Turkey claims uninstall prevention. So this is achievable. But be honest: a determined admin can always bypass (Recovery Mode, disabling system extensions, booting another OS). Design for **friction and commitment**, not invincibility — same as Brick (5 emergency unbricks exist precisely because it isn't absolute).

### 6.5 Trigger tech (Mac side), concretely

- **QR via camera:** `AVCaptureSession` + `AVCaptureMetadataOutput` with `[.qr]`; needs `NSCameraUsageDescription` (and camera TCC prompt). Continuity Camera gives you the iPhone lens for free. Decode → verify a signed token → unlock. Zero hardware.
- **NFC via USB reader:** PC/SC over CryptoTokenKit; read UID/NDEF. Small extra purchase; possible Brick-tag reuse. Medium confidence pending tag-family verification.
- **iPhone relay:** reachable via CloudKit/Multipeer/Bonjour, but two-device dependency and sync complexity. Not v1.

### 6.6 The DoH / VPN caveat (call this out loudly)

A `hosts`- or DNS-based block is bypassed by:
- **DNS-over-HTTPS (DoH)** in Chrome, Firefox, and increasingly system-wide (though macOS itself still uses the system resolver by default; browsers often do not).
- **VPNs / proxy extensions** the user installs.
- Editing `/etc/hosts` (admin user can), flushing DNS, switching networks.

Mitigations, in increasing robustness: (a) block the DoH resolver hostnames/IPs too; (b) force DNS to your resolver via configuration profile; (c) **use a content filter (NEFilterDataProvider)** which inspects flows even when DNS is encrypted. For a product that must feel like Brick, **(c) is the target end-state**; a hosts/DNS MVP is fine as a personal tool but should be labeled as bypassable.

### 6.7 Emerging: URL Filter provider on macOS 26

TN3134 (rev. 2025-08-19) adds a **URL filter provider** (macOS app extension, min macOS 26). This is a newer, lighter-weight sanctioned path to URL filtering and could become the simplest robust route for new work on macOS 26+. Worth tracking; not something to depend on across older Macs today.

---

## 7. Jobs-to-be-done & the design contract

**JTBD (functional):** "When I sit down to work on my Mac, keep the distracting apps and sites out of reach so I do the work."
**Emotional:** "Feel that I'm not fighting myself; the decision is already made."
**Social:** "Be present and productive; not the person who disappears into a screen."
**Anti-JTBD:** "Don't lock me out of something I genuinely need in an emergency."

**Design contract (from Brick, adapted):**
1. Activation may be remote; **deactivation requires the physical key.**
2. **No decorative overrides.** No "ignore limit," no one-click off.
3. **Strict mode** that resists uninstall/settings edits while active.
4. **Bounded emergency escape** (e.g., 5 unbricks) so the tool is safe.
5. **Non-judgmental** tone (a stated reason people prefer Brick to Opal).
6. **Reliable schedules** (a stated Brick weakness — make this a differentiator, not a liability).
7. Offline-first, local block lists (Brick: "all blocking information is stored locally").

---

## 8. Recommended architecture (v1 "Brick for Mac")

```
                     ┌─────────────────────────────────────────────┐
     QR code  ──►    │  Menu-bar app (SwiftUI / MenuBarExtra)       │
   (Mac camera)      │  - configure blocklist & modes               │
   OR NFC tag ──►    │  - show lock timer, strict-mode state        │
   (USB PC/SC reader)│  - scan QR / read tag to request UNLOCK      │
                     └───────────────┬─────────────────────────────┘
                                     │ XPC (authenticated)
                     ┌───────────────▼─────────────────────────────┐
                     │  Root LaunchDaemon (SMAppService)            │
                     │  - holds unlock secret; verifies token       │
                     │  - enforces state machine (locked/unlocked)  │
                     │  - tamper-resistant, KeepAlive               │
                     └───────┬───────────────────────┬─────────────┘
                             │                       │
             ┌───────────────▼──────────┐   ┌────────▼─────────────────┐
             │ Network enforcement       │   │ Process enforcement       │
             │ DNS proxy or NEFilter     │   │ NSWorkspace watcher +     │
             │ system extension          │   │ kill blocked bundle IDs   │
             │ (system-wide websites)    │   │ (native apps)             │
             └───────────────────────────┘   └───────────────────────────┘
```

**State machine:** `UNLOCKED → (scan QR / tap tag) → LOCKED → (scan QR / tap tag) → UNLOCKED`, with LOCKED possibly scheduled/duration-bound and with an emergency-unbrick counter that decrements.

**Enforcement split:**
- **Website/app-network blocking** → DNS proxy system extension (v1, easier) graduating to a **content filter** (v2, DoH-proof). Blocklist of domains + categories.
- **Native app blocking** → daemon watches `NSWorkspace.shared.notificationCenter` activation events, force-terminates blocked bundle IDs on launch/focus; optionally dims/overlays. (This mirrors Cold Turkey "Micromanager.")

**Distribution:** Developer ID, notarized `.dmg`. System extension approval UX must be scripted and explained (System Settings → Privacy & Security → Network Extensions → Allow; possibly restart).

**Tech stack:** Swift + SwiftUI; `NetworkExtension`; `SMAppService`/XPC; `AVFoundation` (QR); CryptoTokenKit/PC-SC (optional NFC). No third-party runtime needed; matches your environment (macOS 15.6, Xcode/Swift available — the workspace already has `swift`).

---

## 9. MVP scope & build plan

**Phase 0 — Spike (personal tool, ~days).** Menu-bar app + root LaunchDaemon; `/etc/hosts` blocklist + app-kill loop; unlock = QR scan with built-in camera; lock timer + strict flag. Prove the *feel*. Known limitation: DoH/VPN bypass. This is enough to use on yourself and to demo.

**Phase 1 — Real product core.** Replace hosts with a **DNS proxy system extension** (system-wide, all browsers/apps) and add DoH-resolver blocking; harden the daemon (root-owned state, SMAppService, tamper monitoring); polish lock/unlock UX and schedules. Notarize + ship .dmg.

**Phase 2 — Brick integration / differentiation.**
  - Optional **USB NFC reader** path; if Brick's tag is readable, "your Brick unlocks your Mac."
  - **Cross-device story:** modes/analytics sync with the phone Brick app (iCloud or own backend). Even Opal hasn't shipped Mac↔iPhone sync — beating them here is a moat.
  - **Content filter** upgrade for DoH-proof blocking.

**Phase 3 — optional.** MDM/profile-based family controls (parents), team/business plan, Windows (Freedom's turf).

**Explicitly out of scope for v1:** browser-only blocking (too weak), Mac App Store (can't ship system extensions), family/parental MDM, "impossible to bypass" claims (dishonest).

---

## 10. Business framing (if it's more than personal)

- **Pricing precedents:** Brick $59 one-time + free app (no sub) sets a strong user expectation of **one-time pricing**. Opal $99.99/yr, Freedom $39.99/yr, Unpluq $38+sub, Cold Turkey one-time. A **one-time $29–$49 Mac app** (or "included with Brick" via partnership) fits the culture of this niche far better than a subscription.
- **Two go-to-market shapes:**
  1. **Independent product** — "the Mac that can't be overridden." Sell to Brick owners + Opal/Freedom churn-outs. Direct download; small, focused, opinionated.
  2. **Brick companion / partnership** — pitch Brick the Mac half of their ecosystem (they have the brand, audience, and a phone-only gap; you have the Mac enforcement). Higher leverage, slower, relationship-dependent.
- **Moat:** the hard parts are (a) the privileged/system-extension engineering and (b) the anti-bypass reliability — exactly what the App Store crowd avoids. Reliability of schedules is a proven pain point in Brick's own reviews; own it.
- **Risks to the business:** Apple tightening system-extension rules; a major incumbent (Opal) finishing their Mac app limits/locks; low willingness to pay on desktop (mitigate with one-time pricing).

---

## 11. Risk register / hard truths

| Risk | Severity | Mitigation |
|---|---|---|
| **DoH/VPN bypass** of DNS/hosts blocks | High | Go to a **content filter**; block known DoH resolvers; document limits |
| Apple changes/curtails Network Extension or system extensions | Medium | Stay within documented, currently-sanctioned APIs (TN3134); ship fast on macOS 26 URL filters when viable |
| App blocking is "kill and relaunch" (no true shield) | Medium | Persistent daemon + relaunch prevention; accept friction-not-invincibility framing |
| Mac App Store can't ship system extensions | Medium → **constraint** | Commit to Developer ID/notarized direct distribution from day one |
| Permissions fatigue (camera TCC, system extension approval, possible restart) | Medium | Minimal, well-explained onboarding; one permission per value moment |
| "Who watches the watchman" — user locks themselves out | Medium | Emergency-unbrick budget (Brick's model), scheduled auto-unlock, recovery doc |
| No NFC on Mac | Low (solved) | QR via camera (v1); USB reader/iPhone relay (v2) |
| Legal/safety: blocking emergency services, work-critical apps | Low | Never block system/phone/emergency; clear allowlist defaults |
| Brick's tag format unknown → "reuse your Brick" may not work | Medium | Verify tag IC (NTAG21x UID read) before promising; fall back to QR |

---

## 12. Open questions / decisions to make

1. **Hard commit vs soft friction** for the Mac — assume hard (Brick user), but confirm.
2. **Distribution:** comfortable shipping a Developer ID `.dmg` with a system extension + a System Settings approval step? (Required for the robust path.)
3. **Physical key:** start with **QR + camera** (zero hardware) or invest early in a **USB NFC reader** (nicer story, small cost, Brick-reuse upside)?
4. **Website blocking depth:** accept a DNS-proxy MVP (bypassable by DoH) or go straight to a content filter (more work, robust)?
5. **App blocking scope:** which bundle IDs (browsers? YouTube app? Slack? Discord?) and severity (quit on focus vs refuse launch)?
6. **Emergency policy:** how many unbricks, and do they expire?
7. **Sync:** standalone, or sync modes/analytics with the phone Brick app (and would Brick partner)?
8. **Pricing:** free/personal, one-time, or companion-with-Brick?

---

## 13. Sources (primary unless noted)

**Brick:** `https://getbrick.app/` · `https://getbrick.com/pages/faq` · `https://getbrick.com/collections/all` · `https://getbrick.com/products.json` · App Store: `https://apps.apple.com/us/app/brick-ditch-distractions/id6448794069` (id 6448794069; "Only for iPhone").
**Apple:** Family Controls framework `https://developer.apple.com/documentation/familycontrols` · Managed Settings `https://developer.apple.com/documentation/managedsettings` · Device Activity `https://developer.apple.com/documentation/deviceactivity` · Family Controls entitlement `https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.family-controls` · Network Extension content filters `https://developer.apple.com/documentation/networkextension/content-filter-providers` · `NEFilterDataProvider` `https://developer.apple.com/documentation/networkextension/nefilterdataprovider` · **TN3134 Network Extension provider deployment** `https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment` · MacBook Pro 14″ M4 tech specs `https://support.apple.com/en-us/121553`.
**Competitors:** `https://www.opal.so/` · `https://www.opal.so/mac` · `https://www.opal.so/pricing` · `https://freedom.to/` · `https://getcoldturkey.com/` · `https://selfcontrolapp.com/` · `https://github.com/SelfControlApp/selfcontrol` · `https://www.stayinsession.com/` · `https://one-sec.app/` · `https://unpluq.com/` · `https://www.thekitchensafe.com/` · App Store listings for Opal (1497465230), ScreenZen (1541027222), ClearSpace (1572515807).
**Research cited by products:** Grüning, Riedel & Lorenz-Spreen (PNAS 2023) on one sec; Haliburton et al. (CHI 2024) design frictions; Duhigg/McGonigal/Baumeister via kSafe.



---

### Verification note / confidence
- **High confidence:** Brick is phone-only and its mechanics/pricing (its own site + App Store + Shopify JSON); Apple's Screen Time API is unavailable on native macOS and the Network Extension deployment matrix (primary Apple docs); MacBooks have no NFC (Apple tech specs); competitor feature/price claims (their own sites/listings).
- **Medium confidence (inferred):** how each competitor *implements* blocking internally (not public); whether Brick's NFC tag UID is readable by a generic PC/SC reader (needs hands-on verification).
- **Not yet tested:** an actual QR-scan-to-unlock + daemon lock spike on Marcus.s M4 Pro macOS 15.6. That is the natural next step if you want to move from research to build.
