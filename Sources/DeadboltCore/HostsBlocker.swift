import Foundation

public enum HostsBlockerError: Error, Equatable, CustomStringConvertible {
    case notWritable(String)

    public var description: String {
        switch self {
        case .notWritable(let path):
            return "hosts file is not writable: \(path)"
        }
    }
}

/// Resolves the hosts file path: an explicit `--hosts-path` value first, then
/// the `DEADBOLT_HOSTS_PATH` environment variable, then `/etc/hosts`.
public enum HostsPath {
    public static func resolve(
        explicit: String?,
        environment: [String: String]
    ) -> String {
        if let explicit, !explicit.isEmpty { return explicit }
        if let env = environment["DEADBOLT_HOSTS_PATH"], !env.isEmpty { return env }
        return "/etc/hosts"
    }
}

/// Applies or clears a managed, marker-delimited block in a hosts file. The
/// managed block maps each blocked domain (and its `www.` variant) to
/// `0.0.0.0` and `::1`. Applying is idempotent and preserves every
/// pre-existing non-Deadbolt line and comment. Clearing removes only the
/// managed block. A non-writable file fails with a clear error and is never
/// modified.
public struct HostsBlocker {
    public let hostsPath: String

    public init(hostsPath: String) {
        self.hostsPath = hostsPath
    }

    public static let startMarker = "# BEGIN DEADBOLT"
    public static let endMarker = "# END DEADBOLT"

    public func apply(domains: [String]) throws {
        try ensureWritableIfExists()
        let original = try readContent()
        let coreLines = removeManagedBlock(from: lines(of: original))
        let newContent = render(coreLines + makeBlockLines(domains: domains))
        guard newContent != original else { return }
        try writeContent(newContent)
    }

    public func clear() throws {
        try ensureWritableIfExists()
        let original = try readContent()
        let coreLines = removeManagedBlock(from: lines(of: original))
        let newContent = render(coreLines)
        guard newContent != original else { return }
        try writeContent(newContent)
    }

    /// The raw managed block (markers included) for the given domains, used by
    /// tests to inspect the exact format.
    public func managedBlock(domains: [String]) -> String {
        makeBlockLines(domains: domains).joined(separator: "\n")
    }

    // MARK: - Private

    private func ensureWritableIfExists() throws {
        guard FileManager.default.fileExists(atPath: hostsPath) else { return }
        guard FileManager.default.isWritableFile(atPath: hostsPath) else {
            throw HostsBlockerError.notWritable(hostsPath)
        }
    }

    private func readContent() throws -> String {
        guard FileManager.default.fileExists(atPath: hostsPath) else { return "" }
        return try String(contentsOfFile: hostsPath, encoding: .utf8)
    }

    private func writeContent(_ content: String) throws {
        guard FileManager.default.isWritableFile(atPath: hostsPath) else {
            throw HostsBlockerError.notWritable(hostsPath)
        }
        try content.write(toFile: hostsPath, atomically: true, encoding: .utf8)
    }

    private func lines(of text: String) -> [String] {
        var result = text.components(separatedBy: "\n")
        if result.last == "" { result.removeLast() }
        return result
    }

    private func render(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    private func removeManagedBlock(from lines: [String]) -> [String] {
        var result: [String] = []
        var inside = false
        for line in lines {
            if line == Self.startMarker {
                inside = true
                continue
            }
            if inside {
                if line == Self.endMarker { inside = false }
                continue
            }
            result.append(line)
        }
        return result
    }

    private func makeBlockLines(domains: [String]) -> [String] {
        var lines: [String] = [Self.startMarker]
        let sorted = Set(domains.map(normalizeDomain))
            .filter { !$0.isEmpty }
            .sorted()
        for domain in sorted {
            lines.append(contentsOf: [
                "0.0.0.0 \(domain)",
                "0.0.0.0 www.\(domain)",
                "::1 \(domain)",
                "::1 www.\(domain)",
            ])
        }
        lines.append(Self.endMarker)
        return lines
    }
}
