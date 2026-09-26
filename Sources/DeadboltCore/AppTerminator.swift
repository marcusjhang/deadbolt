import AppKit
import Foundation

/// A running application identified by its bundle identifier.
public struct RunningApp: Codable, Equatable, Sendable {
    public let bundleIdentifier: String
    public let name: String

    public init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

/// Finds and terminates running applications whose bundle identifier is in a
/// blocked set. Real implementations act on the system; fakes record the
/// requests so tests and e2e never touch real processes.
public protocol AppTerminator {
    /// The running applications whose bundle identifier is in
    /// `bundleIdentifiers`.
    func blockedRunningApps(bundleIdentifiers: Set<String>) throws -> [RunningApp]

    /// Terminates a running application.
    func terminate(_ app: RunningApp) throws
}

/// The real, system-backed terminator using `NSWorkspace`.
public struct SystemAppTerminator: AppTerminator {
    public init() {}

    public func blockedRunningApps(bundleIdentifiers: Set<String>) throws -> [RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, bundleIdentifiers.contains(id) else {
                return nil
            }
            return RunningApp(bundleIdentifier: id, name: app.localizedName ?? id)
        }
    }

    public func terminate(_ app: RunningApp) throws {
        guard let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == app.bundleIdentifier
        }) else {
            return
        }
        _ = running.terminate()
    }
}

/// A fake terminator for tests and e2e. Records terminated apps without
/// touching real processes.
public final class FakeAppTerminator: AppTerminator {
    public var running: [RunningApp]
    public private(set) var terminated: [RunningApp] = []

    public init(running: [RunningApp]) {
        self.running = running
    }

    public convenience init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        let running = try DeadboltJSON.decoder.decode([RunningApp].self, from: data)
        self.init(running: running)
    }

    public func blockedRunningApps(bundleIdentifiers: Set<String>) throws -> [RunningApp] {
        running.filter { bundleIdentifiers.contains($0.bundleIdentifier) }
    }

    public func terminate(_ app: RunningApp) throws {
        terminated.append(app)
    }
}
