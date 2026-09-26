import Foundation

/// The persisted lock state. Absent state means unlocked.
public enum LockState: String, Codable, Sendable, Equatable {
    case locked
    case unlocked
}

/// A point-in-time view of the lock state, including the timed-lock deadline
/// (if any). `lockedUntil` is set only when the lock was taken with a duration.
public struct LockSnapshot: Equatable, Sendable {
    public let state: LockState
    public let lockedUntil: Date?

    public init(state: LockState, lockedUntil: Date? = nil) {
        self.state = state
        self.lockedUntil = lockedUntil
    }
}

/// Persists the lock state in the state directory so it survives process
/// restarts. A missing state file means unlocked.
public struct LockStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var stateFileURL: URL {
        directory.appendingPathComponent("state.json")
    }

    public func read() throws -> LockState {
        try readSnapshot().state
    }

    public func readSnapshot() throws -> LockSnapshot {
        guard FileManager.default.fileExists(atPath: stateFileURL.path) else {
            return LockSnapshot(state: .unlocked, lockedUntil: nil)
        }
        let data = try Data(contentsOf: stateFileURL)
        let container = try DeadboltJSON.decoder.decode(StateContainer.self, from: data)
        return LockSnapshot(state: container.state, lockedUntil: container.lockedUntil)
    }

    public func write(_ state: LockState, lockedUntil: Date? = nil) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = StateContainer(state: state, lockedUntil: lockedUntil)
        let data = try DeadboltJSON.encoder.encode(container)
        try data.write(to: stateFileURL, options: .atomic)
    }

    public func remove() throws {
        guard FileManager.default.fileExists(atPath: stateFileURL.path) else { return }
        try FileManager.default.removeItem(at: stateFileURL)
    }
}

private struct StateContainer: Codable {
    let state: LockState
    let lockedUntil: Date?
}

/// Pure lock/unlock decision logic, hardware-independent for testability.
public enum LockMachine {
    /// Returns the enrolled key (if any) that a currently attached device
    /// matches by stable fingerprint.
    public static func attachedKey(
        devices: [USBDeviceIdentity],
        keys: [KeyRecord]
    ) -> KeyRecord? {
        let attached = Set(devices.map(\.fingerprint))
        return keys.first { attached.contains($0.fingerprint) }
    }

    public static func canUnlock(
        devices: [USBDeviceIdentity],
        keys: [KeyRecord]
    ) -> Bool {
        attachedKey(devices: devices, keys: keys) != nil
    }

    /// Unlock is possible only when an enrolled key is attached and any timed
    /// lock has elapsed (or no timed lock was taken).
    public static func canUnlock(
        devices: [USBDeviceIdentity],
        keys: [KeyRecord],
        lockedUntil: Date?,
        now: Date
    ) -> Bool {
        guard !timedLockActive(lockedUntil: lockedUntil, now: now) else { return false }
        return attachedKey(devices: devices, keys: keys) != nil
    }

    /// Whether a timed lock is still in force at `now`.
    public static func timedLockActive(lockedUntil: Date?, now: Date) -> Bool {
        guard let lockedUntil else { return false }
        return now < lockedUntil
    }

    /// Whole minutes remaining until a timed lock elapses, rounded up, or nil
    /// when no timed lock is active.
    public static func remainingMinutes(lockedUntil: Date?, now: Date) -> Int? {
        guard let lockedUntil, now < lockedUntil else { return nil }
        let seconds = lockedUntil.timeIntervalSince(now)
        return max(Int(ceil(seconds / 60.0)), 1)
    }
}
