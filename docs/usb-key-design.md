# Deadbolt — USB Key Unlock: Technical Design

*Replaces the QR-key idea. Companion to `product-summary.md` and `market-research.md`.*

**Idea:** the Mac's lock state is governed by a **physical USB device**. To end a focus session you must physically plug the key back in. Keep it in a drawer / another room and the friction is real — Brick's "leave the key behind," using ports the Mac already has. No camera, no printing, no scanning.

---

## 1. The UX contract

**Lock (easy):** click **Lock** in the menu bar, press a hotkey, or let a schedule fire. Blocked apps quit; blocked sites stop resolving. The key is *not* required to lock.

**Unlock (hard):** there is no in-app "ignore." To end the session you must **plug in the key you stashed**. The daemon verifies it's *that specific device*, then releases the lock.

**Rules:**
- Locking is frictionless; unlocking costs a walk. That asymmetry is the product.
- The key is normally **stored away**, not left in the machine (same discipline as leaving the Brick on the fridge).
- Optional **physical-switch mode:** pulling the key out *is* Lock (nice for people who like a dedicated dongle). Off by default because it forces the key to stay inserted for normal use.
- Emergency budget still applies (e.g. 2/month) for genuine lockouts.

State machine:

```
        Lock (menu / hotkey / schedule)
UNLOCKED ───────────────────────────────► LOCKED
   ▲                                        │
   └──────────────  key inserted  ──────────┘
                (verified identity / challenge-response)
```

---

## 2. What can be "the key"

| Key | Cost | Identity used | Notes |
|---|---|---|---|
| **Any spare USB-C thumb drive** | $0 | Volume UUID + hidden token file | Free default. Works on every Mac. |
| **SD card (MacBook Pro slot)** | $0 | Card's volume UUID + token file | No dongle protruding; MBP-only. |
| **YubiKey / security key** | $30–70 | Serial + **HMAC-SHA1 challenge-response** | Strongest; can't be cloned by copying files. |
| **Custom USB dongle** (ESP32-S2/S3, ATtiny, etc.) | ~$2–10 | Unique USB serial, or challenge-response | Product-izable hardware; you build hardware already. |
| **Existing device with a unique serial** | $0 | `kUSBSerialNumberString` | Works only if serial is real (see §4). |

**Never a key:** the internal SSD, any `Removable Media: Fixed` / `Device Internal: true` disk, or any device reporting a placeholder serial (see §4).

---

## 3. How macOS detects the key (the plumbing)

Two complementary, sanctioned APIs cover every key type. Both work from a background **root LaunchDaemon**, so enforcement does not depend on the UI app being open.

### 3.1 Storage keys (thumb drive, SD card) → Disk Arbitration
- Create a `DASession`, register `DARegisterDiskAppearedCallback` / `DARegisterDiskDisappearedCallback` (or set a dispatch queue with `DASessionSetDispatchQueue`).
- `DADiskCopyDescription(disk)` gives a dictionary with exactly the keys we need:
  - `kDADiskDescriptionVolumeUUIDKey` — stable, filesystem-level ID for the drive.
  - `kDADiskDescriptionMediaUUIDKey`, `kDADiskDescriptionMediaNameKey`
  - `kDADiskDescriptionDeviceVendorKey` / `DeviceModelKey` / `DeviceProtocolKey` / `DeviceGUIDKey`
  - `kDADiskDescriptionMediaRemovableKey`, `kDADiskDescriptionDeviceInternalKey` — **use these to reject the system disk.**
  - `kDADiskDescriptionVolumePathKey` — where it mounted.
- Inserting/removing the drive fires appeared/disappeared → the natural Lock/Unlock event.
- **Enrollment:** at setup, write a hidden **token file** (a random 256-bit secret) to the key volume and record its `VolumeUUID` + vendor/model. Unlock requires **both** a matching volume UUID **and** a matching token. Copying the token file to another drive fails the UUID check; reformatting the key fails enrollment (re-enroll once).
- This is why it's robust even for drives with no serial.

### 3.2 Non-storage USB keys (YubiKey, custom dongle) → IOKit
- Enumerate/match with `IOServiceMatching("IOUSBHostDevice")` and watch hot-plug via `IONotificationPortCreate(kIOMainPortDefault)` + `IOServiceAddMatchingNotification(... kIOFirstMatchNotification ...)` and `... kIOTerminatedNotification ...`.
- Read device properties with `IORegistryEntryCreateCFProperty`:
  - `kUSBSerialNumberString` (also surfaced as `"USB Serial Number"`)
  - `kUSBVendorID` / `kUSBProductID` (`"idVendor"` / `"idProduct"`), `kUSBProductString`/`kUSBVendorString`
- Ignore `locationID` — it changes with the port/hub, so a key plugged into a different port would stop working. Match on serial + VID/PID instead.

### 3.3 Strong mode → YubiKey challenge-response
- Per Yubico's docs, challenge-response uses the **HID protocol over USB** (not NFC), with **HMAC-SHA1**: app sends a challenge (up to 64 bytes), key returns a 20-byte HMAC (or a 6–10 digit code); optionally requires a physical touch.
- No secret is stored on the Mac — the response is verified against the expected HMAC. This defeats "copy the key file" attacks.
- macOS access via `ykman otp chalresp` / libykpers-style APDUs, or FIDO2 `hmac-secret` via libfido2. Optional later; identity-based keys ship first.

---

## 4. Identification rules (learned from real hardware)

I inspected this actual M4 Pro MacBook. Real findings that shape the design:

- **Real serials exist and are stable:** your ESP32 JTAG unit reports `A1:B2:C3:D4:E5:F6`; a USB bridge reported `0A1B2C3D4E5F6`. These make good keys.
- **Cheap devices report junk serials:** two VIA hubs reported `000000000`; an Anker hub `0000000000000001`. **Must reject placeholder serials** (all-zero / repeated-digit / equal to VID/PID) or half your devices are "the same key."
- **Some devices have no serial at all:** the Logitech USB receivers expose only VID/PID → unusable as identity keys.
- **Disk identities are clean:** `diskutil` shows distinct `Volume UUID` for every volume; internal disks are marked `Removable Media: Fixed` and enumerated as internal → easy to exclude.
- **SD card:** the machine has a built-in SD reader (`0x17a0:0x9755`); inserting a card makes it a normal disk → same DiskArbitration path. Identify the **card**, never the reader.
- **Hubs/docks are fine:** devices behind a hub still enumerate with their own serial/UUID; they just get a different `locationID` — another reason to ignore location.

**Enrollment validation checklist** (refuse to register a key if any fail):
1. Not internal, not `RemovableMedia: Fixed`.
2. Volume UUID present and ≠ any system volume.
3. Token written and re-read successfully.
4. (Serial route) serial exists and is not a placeholder.

---

## 5. Architecture

```
┌────────────────────────────────────────────┐
│ Menu-bar app (SwiftUI)                      │
│  - Lock now / schedule / hotkey             │
│  - "Insert your key to unlock" screen       │
│  - enroll key, show state, emergency budget │
└───────────────┬────────────────────────────┘
                │ XPC (code-signing validated)
┌───────────────▼────────────────────────────┐
│ Root LaunchDaemon (SMAppService.daemon)     │
│  - owns lock state + key registry           │
│  - DiskArbitration session (storage keys)   │
│  - IOKit notification port (USB keys)       │
│  - verifies key (UUID+token or challenge)   │
│  - enforces: network block + app kill       │
└───────┬───────────────────────┬────────────┘
        │                       │
┌───────▼─────────┐   ┌─────────▼──────────────┐
│ Network Extension│   │ Process enforcement     │
│ (DNS proxy /     │   │ (kill/relaunch blocked  │
│  content filter) │   │  apps on launch/focus)  │
└──────────────────┘   └─────────────────────────┘
```

- **LaunchDaemon registration:** `SMAppService.daemon(plistName:)` (macOS 13+), user approves in Login Items.
- The daemon keeps the lock even if the UI app is quit. The UI only requests Lock/Unlock; the daemon decides.
- Key registry + lock secret + emergency counter live in a **root-owned** file (not user-writable), so editing the app prefs or deleting the app doesn't clear the lock.

---

## 6. Failure & edge cases (design for these explicitly)

| Case | Handling |
|---|---|
| Key left plugged in | Allowed; user discipline. Optional nudges. |
| Mac sleeps / wakes | Re-assert lock on wake; re-verify key presence. |
| Reboot / power loss | Lock state persists (root file); key required to release after boot. |
| Two identical drives, no serial | Disambiguated by Volume UUID + token file. |
| Key reformatted / wiped | Fails UUID/token → treated as "not the key"; re-enroll required. |
| Key plugged via a dock/hub | Fine — match by serial/UUID, never location. |
| Thunderbolt/PCIe drive | Not in the USB plane; use the storage (DiskArbitration) path instead. |
| SD card ejected during session | Fires `DiskDisappeared` → lock holds; card out = no unlock. |
| Reading token before mount completes | Wait for the `didMount`/description pass; retry with backoff. |
| Key stolen/copied | Identity keys: copying the token file alone fails the UUID check. Strong mode (YubiKey challenge-response) resists cloning entirely. |
| User genuinely locked out | Rationed emergency budget + documented recovery path. |

---

## 7. Security & threat model (honest version)

- **The adversary is you**, not an attacker. The goal is friction and precommitment, not cryptographic invulnerability. Brick doesn't claim invincibility either (it ships 5 emergency unbricks).
- **Identity-based keys can be spoofed** by a programmable USB device that clones a serial, and a token file can be copied — though binding to the volume UUID blocks the naive file copy. That's acceptable for self-discipline.
- **Strong mode** (YubiKey HMAC-SHA1 challenge-response, or a custom dongle with a secure element) makes the key uncloneable; sell it as "Hardcore key."
- **A determined admin can always bypass** (Recovery Mode, disable the daemon, boot another OS). We sell commitment, not DRM.

---

## 8. Recommended defaults

- **Free tier key:** any spare USB-C thumb drive, enrolled by writing a token (volume UUID + token).
- **Power key:** YubiKey (challenge-response) or SD card.
- **Hardware angle:** a branded **USB-C "Key" dongle** shipped with the app — hardware-first, Brick's playbook. If you want to build it yourself, an **ESP32-S2/S3 or ATtiny-class** USB device can present a unique serial (you already build hardware), or a secure-element MCU can do real challenge-response.
- **Lock model:** explicit Lock + key-to-Unlock by default; offer "pull key = Lock" as an opt-in physical-switch mode.
- **Compatibility:** USB-C key is universal (all Macs); SD key is a bonus for MacBook Pro.

---

## 9. Phase 0 spike (what to actually build first)

1. Menu-bar app + a **per-user** helper first (skip the root daemon for the spike) that:
   - enumerates USB/SD via DiskArbitration + IOKit and prints identities;
   - enrolls one drive (writes token, stores volume UUID);
   - implements Lock/Unlock gated on that key being present;
   - enforces a trivial block (start with app-kill of 1–2 bundle IDs + `hosts` entries);
   - shows the menu-bar lock timer.
2. Run it on Marcus.s M4 Pro (macOS 15.6) for a week. Confirm: enrollment is painless, the key is recognized across ports and after sleep/reboot, and the "go get the key" friction feels right.
3. Only then promote the helper to a root LaunchDaemon (`SMAppService.daemon`) and add the network-extension layer.

**Risks to watch in the spike:** placeholder serials on cheap devices (§4), mount-timing races, and wake-from-sleep re-verification.

---

## 10. Open questions

1. Default key: **thumb drive** (free/universal) vs **SD card** (cleaner on MBP) vs **YubiKey** (secure)?
2. Ship a **custom dongle** as hardware, or keep it software + bring-your-own-key?
3. Lock model: explicit-Lock (recommended) or physical-switch (pull-to-lock) as the default?
4. Do you want **strong mode (YubiKey challenge-response)** in v1 or v2?
