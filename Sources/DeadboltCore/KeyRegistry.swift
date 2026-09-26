import Foundation

/// Persists enrolled keys as JSON in the state directory. All mutable state
/// lives under one directory so tests can point it at a temporary location.
public struct KeyRegistry {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var keysFileURL: URL {
        directory.appendingPathComponent("keys.json")
    }

    public func load() throws -> [KeyRecord] {
        guard FileManager.default.fileExists(atPath: keysFileURL.path) else { return [] }
        let data = try Data(contentsOf: keysFileURL)
        return try DeadboltJSON.decoder.decode([KeyRecord].self, from: data)
    }

    public func save(_ keys: [KeyRecord]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try DeadboltJSON.encoder.encode(keys)
        try data.write(to: keysFileURL, options: .atomic)
    }

    public func enroll(_ record: KeyRecord) throws {
        var keys = try load()
        keys.append(record)
        try save(keys)
    }

    /// Removes any enrolled key whose fingerprint or label matches
    /// `selectorOrLabel` (labels match case-insensitively). Returns the number
    /// of keys removed.
    @discardableResult
    public func unenroll(_ selectorOrLabel: String) throws -> Int {
        let needle = selectorOrLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        var keys = try load()
        let before = keys.count
        keys.removeAll { record in
            record.fingerprint == needle
                || record.label.caseInsensitiveCompare(needle) == .orderedSame
        }
        let removed = before - keys.count
        if removed > 0 {
            try save(keys)
        }
        return removed
    }

    public func removeAll() throws {
        guard FileManager.default.fileExists(atPath: keysFileURL.path) else { return }
        try FileManager.default.removeItem(at: keysFileURL)
    }
}
