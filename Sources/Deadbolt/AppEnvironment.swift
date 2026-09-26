import DeadboltCore
import Foundation

/// Resolves the app's runtime dependencies from the environment. All of the
/// interesting logic lives in DeadboltCore; this is just wiring.
enum AppEnvironment {
    static func resolveDeviceSource() -> DeviceSource {
        if let path = ProcessInfo.processInfo.environment["DEADBOLT_FAKE_DEVICES"],
           !path.isEmpty,
           let source = try? FixtureDeviceSource(contentsOf: URL(fileURLWithPath: path)) {
            return source
        }
        return SystemDeviceSource()
    }

    static func makeController() -> DeadboltController {
        DeadboltController(
            stateDirectory: StateDirectory.resolve(),
            hostsPath: HostsPath.resolve(
                explicit: nil,
                environment: ProcessInfo.processInfo.environment
            ),
            deviceSource: resolveDeviceSource(),
            terminator: SystemAppTerminator()
        )
    }
}
