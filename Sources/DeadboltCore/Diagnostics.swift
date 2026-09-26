import Foundation

/// A machine-readable snapshot of Deadbolt's current state, emitted by
/// `Deadbolt --diagnostics`.
public struct DiagnosticsReport: Codable, Equatable, Sendable {
    public let version: String
    public let state: String
    public let attachedKey: String?
    public let enrolledKeyCount: Int
    public let enrolledKeyTiers: [String]
    public let blockedDomainCount: Int
    public let blockedAppCount: Int
    public let hostsPathWritable: Bool

    public init(
        version: String,
        state: String,
        attachedKey: String?,
        enrolledKeyCount: Int,
        enrolledKeyTiers: [String],
        blockedDomainCount: Int,
        blockedAppCount: Int,
        hostsPathWritable: Bool
    ) {
        self.version = version
        self.state = state
        self.attachedKey = attachedKey
        self.enrolledKeyCount = enrolledKeyCount
        self.enrolledKeyTiers = enrolledKeyTiers
        self.blockedDomainCount = blockedDomainCount
        self.blockedAppCount = blockedAppCount
        self.hostsPathWritable = hostsPathWritable
    }

    private enum CodingKeys: String, CodingKey {
        case version, state, attachedKey, enrolledKeyCount, enrolledKeyTiers
        case blockedDomainCount, blockedAppCount, hostsPathWritable
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(state, forKey: .state)
        try container.encode(attachedKey, forKey: .attachedKey)
        try container.encode(enrolledKeyCount, forKey: .enrolledKeyCount)
        try container.encode(enrolledKeyTiers, forKey: .enrolledKeyTiers)
        try container.encode(blockedDomainCount, forKey: .blockedDomainCount)
        try container.encode(blockedAppCount, forKey: .blockedAppCount)
        try container.encode(hostsPathWritable, forKey: .hostsPathWritable)
    }
}

/// Builds a diagnostics report from the injected state directory, hosts path,
/// and device source, without throwing on an empty or unreadable state.
public enum Diagnostics {
    public static func report(
        stateDirectory: URL,
        hostsPath: String,
        deviceSource: DeviceSource
    ) -> DiagnosticsReport {
        let state = (try? LockStore(directory: stateDirectory).read()) ?? .unlocked
        let model = MenuBarModel(
            deviceSource: deviceSource,
            registry: KeyRegistry(directory: stateDirectory),
            state: state
        )
        let blockList = (try? BlockStore(directory: stateDirectory).load()) ?? BlockList()

        return DiagnosticsReport(
            version: Deadbolt.version,
            state: model.state.rawValue,
            attachedKey: model.attachedKey?.label,
            enrolledKeyCount: model.enrolledKeys.count,
            enrolledKeyTiers: model.enrolledKeys.map { $0.tier.rawValue },
            blockedDomainCount: blockList.domains.count,
            blockedAppCount: blockList.apps.count,
            hostsPathWritable: isWritable(hostsPath)
        )
    }

    /// A hosts path counts as writable when the file itself is writable, or
    /// when the file does not yet exist but its parent directory does.
    private static func isWritable(_ path: String) -> Bool {
        if FileManager.default.fileExists(atPath: path) {
            return FileManager.default.isWritableFile(atPath: path)
        }
        let parent = (path as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != path else { return false }
        return FileManager.default.isWritableFile(atPath: parent)
    }
}
