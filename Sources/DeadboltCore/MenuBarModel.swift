import Foundation

/// The menu-bar presentation model. Pure and testable: given the lock state,
/// the timed-lock deadline, the current time, the attached devices, and the
/// enrolled keys, it derives everything the menu needs to render without
/// touching hardware or system files.
public struct MenuBarModel: Equatable, Sendable {
    public let state: LockState
    public let lockedUntil: Date?
    public let now: Date
    public let devices: [USBDeviceIdentity]
    public let keys: [KeyRecord]

    public init(
        state: LockState,
        devices: [USBDeviceIdentity],
        keys: [KeyRecord],
        lockedUntil: Date? = nil,
        now: Date = Date()
    ) {
        self.state = state
        self.lockedUntil = lockedUntil
        self.now = now
        self.devices = devices
        self.keys = keys
    }

    /// Convenience initializer backed by a device source and key registry, so
    /// the app can build the model from its injected dependencies. An empty or
    /// unreadable registry yields no keys, and an empty state directory reports
    /// the unlocked state, without throwing.
    public init(
        deviceSource: DeviceSource,
        registry: KeyRegistry,
        state: LockState,
        lockedUntil: Date? = nil,
        now: Date = Date()
    ) {
        self.init(
            state: state,
            devices: (try? deviceSource.listDevices()) ?? [],
            keys: (try? registry.load()) ?? [],
            lockedUntil: lockedUntil,
            now: now
        )
    }

    /// The menu title.
    public var title: String { "Deadbolt" }

    /// The current state as a human-readable string.
    public var statusText: String {
        switch state {
        case .locked: return "Locked"
        case .unlocked: return "Unlocked"
        }
    }

    /// The SF Symbol that reflects the lock state.
    public var symbolName: String {
        switch state {
        case .locked: return "lock.fill"
        case .unlocked: return "lock.open"
        }
    }

    /// The enrolled key matched by a currently attached device, if any.
    public var attachedKey: KeyRecord? {
        LockMachine.attachedKey(devices: devices, keys: keys)
    }

    /// Whether a timed lock is still in force at the model's `now`.
    public var timedLockActive: Bool {
        LockMachine.timedLockActive(lockedUntil: lockedUntil, now: now)
    }

    /// Whole minutes remaining on an active timed lock, or nil.
    public var remainingMinutes: Int? {
        LockMachine.remainingMinutes(lockedUntil: lockedUntil, now: now)
    }

    /// A human-readable remaining-time string while a timed lock is active, or
    /// nil when no timed lock is in force.
    public var remainingTimeString: String? {
        guard let minutes = remainingMinutes else { return nil }
        return minutes == 1 ? "1 minute remaining" : "\(minutes) minutes remaining"
    }

    /// Whether Unlock is currently possible: an enrolled key is attached AND
    /// any timed lock has elapsed.
    public var unlockEnabled: Bool {
        attachedKey != nil && !timedLockActive
    }

    /// Human-readable description of the attached key, or "none".
    public var attachedKeyDescription: String {
        attachedKey?.label ?? "none"
    }

    /// All enrolled keys, with their tiers.
    public var enrolledKeys: [KeyRecord] { keys }
}
