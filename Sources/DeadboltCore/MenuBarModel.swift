import Foundation

/// The menu-bar presentation model. Pure and testable: given the lock state,
/// the attached devices, and the enrolled keys, it derives everything the menu
/// needs to render without touching hardware or system files.
public struct MenuBarModel: Equatable, Sendable {
    public let state: LockState
    public let devices: [USBDeviceIdentity]
    public let keys: [KeyRecord]

    public init(state: LockState, devices: [USBDeviceIdentity], keys: [KeyRecord]) {
        self.state = state
        self.devices = devices
        self.keys = keys
    }

    /// Convenience initializer backed by a device source and key registry, so
    /// the app can build the model from its injected dependencies. An empty or
    /// unreadable registry yields no keys, and an empty state directory reports
    /// the unlocked state, without throwing.
    public init(deviceSource: DeviceSource, registry: KeyRegistry, state: LockState) {
        self.init(
            state: state,
            devices: (try? deviceSource.listDevices()) ?? [],
            keys: (try? registry.load()) ?? []
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

    /// Whether Unlock is currently possible: an enrolled key is attached.
    public var unlockEnabled: Bool {
        attachedKey != nil
    }

    /// Human-readable description of the attached key, or "none".
    public var attachedKeyDescription: String {
        attachedKey?.label ?? "none"
    }

    /// All enrolled keys, with their tiers.
    public var enrolledKeys: [KeyRecord] { keys }
}
