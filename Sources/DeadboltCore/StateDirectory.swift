import Foundation

/// Resolves the state directory: `DEADBOLT_STATE_DIR` when set, otherwise
/// `~/Library/Application Support/Deadbolt`. Injectable via the environment
/// dictionary so tests and e2e never touch the real directory.
public enum StateDirectory {
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let dir = environment["DEADBOLT_STATE_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Deadbolt", isDirectory: true)
    }
}
