# Deadbolt

**The Mac focus blocker you can't click past — unlocked only by a USB device you already own.**

Deadbolt removes distracting apps and websites system-wide on macOS and locks "off" behind a physical key: you enroll any USB device you're willing to stash away, then you must plug it back in to end a focus session. Same idea as [Brick](https://getbrick.com) for your phone — applied to the Mac, with hardware you already own.

> Status: **M0 spike built and verified** — menu-bar app, USB-key registry, lock/unlock, and enforcement, with 72 tests and an end-to-end gate. See [`docs/M0-STATUS.md`](./docs/M0-STATUS.md); plan in [`HANDOVER.md`](./HANDOVER.md).

## Why this exists

- Brick (the phone commitment device) is **iPhone + Android only** — no Mac app.
- Even the best-funded screen-time company (Opal) ships a Mac app that blocks by **puppeteering your browsers** via Automation permission (limited browser list, no anti-disable, no physical key, no sync).
- Apple's Screen Time APIs (`FamilyControls`/`ManagedSettings`) are **not available on native macOS**, so a real Mac blocker must work at the **Network Extension + privileged-daemon** layer — which is exactly why the App Store crowd doesn't build one.

Deadbolt occupies that gap: **OS-level enforcement + a physical USB key.**

## Documentation

| Doc | What it is |
|---|---|
| [`HANDOVER.md`](./HANDOVER.md) | **Start here.** Project status, decisions, how to begin, open questions. |
| [`docs/M0-STATUS.md`](./docs/M0-STATUS.md) | What was built and verified in the M0 spike, how to build/run it, known limits. |
| [`docs/market-research.md`](./docs/market-research.md) | Competitive landscape + macOS technical feasibility (primary sources). |
| [`docs/product-summary.md`](./docs/product-summary.md) | Condensed product definition, positioning, business model. |
| [`docs/usb-key-design.md`](./docs/usb-key-design.md) | Deep technical design of the USB-key unlock mechanism. |
| [`docs/product-plan.md`](./docs/product-plan.md) | Full 18-section product plan (features, UX, architecture, roadmap, GTM). |

## The core idea in one diagram

```
  Lock (menu bar / hotkey / schedule) ──►  blocked apps quit, blocked sites stop resolving
                                                    │
                          no "ignore", no snooze, no one-click off
                                                    │
  Unlock ◄── plug in the USB key you stashed away ──┘
```
