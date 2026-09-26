import Foundation

/// A user-editable list of website domains and macOS app bundle identifiers
/// to block while the system is locked.
public struct BlockList: Codable, Equatable, Sendable {
    public var domains: [String]
    public var apps: [String]

    public init(domains: [String] = [], apps: [String] = []) {
        self.domains = domains
        self.apps = apps
    }
}

/// Persists the block list as JSON in the state directory so tests and e2e can
/// point it at a temporary location.
public struct BlockStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var blockFileURL: URL {
        directory.appendingPathComponent("blocklist.json")
    }

    public func load() throws -> BlockList {
        guard FileManager.default.fileExists(atPath: blockFileURL.path) else {
            return BlockList()
        }
        let data = try Data(contentsOf: blockFileURL)
        return try DeadboltJSON.decoder.decode(BlockList.self, from: data)
    }

    public func save(_ list: BlockList) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try DeadboltJSON.encoder.encode(list)
        try data.write(to: blockFileURL, options: .atomic)
    }

    public func addDomain(_ domain: String) throws {
        var list = try load()
        let normalized = normalizeDomain(domain)
        guard !normalized.isEmpty, !list.domains.contains(normalized) else { return }
        list.domains.append(normalized)
        try save(list)
    }

    public func removeDomain(_ domain: String) throws {
        var list = try load()
        let normalized = normalizeDomain(domain)
        let before = list.domains.count
        list.domains.removeAll { $0 == normalized }
        if list.domains.count != before { try save(list) }
    }

    public func addApp(_ bundleID: String) throws {
        var list = try load()
        let normalized = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !list.apps.contains(normalized) else { return }
        list.apps.append(normalized)
        try save(list)
    }

    public func removeApp(_ bundleID: String) throws {
        var list = try load()
        let normalized = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = list.apps.count
        list.apps.removeAll { $0 == normalized }
        if list.apps.count != before { try save(list) }
    }
}

/// Normalizes a domain for storage: trims whitespace and lowercases.
func normalizeDomain(_ domain: String) -> String {
    domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
