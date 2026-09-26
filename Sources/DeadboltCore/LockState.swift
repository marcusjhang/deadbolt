import Foundation

/// The persisted lock state. Absent state means unlocked.
public enum LockState: String, Codable, Sendable, Equatable {
    case locked
    case unlocked
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
        guard FileManager.default.fileExists(atPath: stateFileURL.path) else {
            return .unlocked
        }
        let data = try Data(contentsOf: stateFileURL)
        return try DeadboltJSON.decoder.decode(StateContainer.self, from: data).state
    }

    public func write(_ state: LockState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try DeadboltJSON.encoder.encode(StateContainer(state: state))
        try data.write(to: stateFileURL, options: .atomic)
    }

    public func remove() throws {
        guard FileManager.default.fileExists(atPath: stateFileURL.path) else { return }
        try FileManager.default.removeItem(at: stateFileURL)
    }
}

private struct StateContainer: Codable {
    let state: LockState
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
}
