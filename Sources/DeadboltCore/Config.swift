import Foundation

/// Persists user-editable configuration as JSON in the state directory. All
/// settings have safe defaults when no file exists, so a fresh state directory
/// behaves predictably.
public struct ConfigStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var configFileURL: URL {
        directory.appendingPathComponent("config.json")
    }

    /// Whether the machine should lock automatically when the enrolled key is
    /// removed while unlocked. Defaults to off.
    public func lockOnKeyRemoval() throws -> Bool {
        guard FileManager.default.fileExists(atPath: configFileURL.path) else {
            return false
        }
        let data = try Data(contentsOf: configFileURL)
        return try DeadboltJSON.decoder.decode(ConfigContainer.self, from: data).lockOnKeyRemoval
    }

    public func setLockOnKeyRemoval(_ value: Bool) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try DeadboltJSON.encoder.encode(ConfigContainer(lockOnKeyRemoval: value))
        try data.write(to: configFileURL, options: .atomic)
    }
}

private struct ConfigContainer: Codable {
    let lockOnKeyRemoval: Bool
}
