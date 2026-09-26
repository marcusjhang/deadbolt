import Foundation

/// Orchestrates lock/unlock and menu state for the menu-bar app. Holds the
/// injected dependencies (device source, state directory, hosts path,
/// terminator) so the SwiftUI layer stays a thin view over this logic.
public struct DeadboltController {
    public let stateDirectory: URL
    public let hostsPath: String
    public let deviceSource: DeviceSource
    public let terminator: AppTerminator

    public init(
        stateDirectory: URL,
        hostsPath: String,
        deviceSource: DeviceSource,
        terminator: AppTerminator
    ) {
        self.stateDirectory = stateDirectory
        self.hostsPath = hostsPath
        self.deviceSource = deviceSource
        self.terminator = terminator
    }

    /// The current persisted lock state; missing state means unlocked.
    public func currentState() -> LockState {
        (try? LockStore(directory: stateDirectory).read()) ?? .unlocked
    }

    /// Builds the menu-bar model from the current state and attached devices.
    public func menuBarModel() -> MenuBarModel {
        MenuBarModel(
            deviceSource: deviceSource,
            registry: KeyRegistry(directory: stateDirectory),
            state: currentState()
        )
    }

    /// Locks the system and applies enforcement. Enforcement is best-effort: a
    /// non-writable hosts file leaves the lock set without failing.
    @discardableResult
    public func lock() -> LockState {
        do {
            try LockStore(directory: stateDirectory).write(.locked)
            try enforce(.locked)
        } catch {
            // The lock stays set even when enforcement could not be applied.
        }
        return currentState()
    }

    /// Unlocks the system when an enrolled key is attached, clearing
    /// enforcement. Does nothing when no enrolled key matches.
    @discardableResult
    public func unlock() -> LockState {
        guard menuBarModel().unlockEnabled else { return currentState() }
        do {
            try LockStore(directory: stateDirectory).write(.unlocked)
            try enforce(.unlocked)
        } catch {
            // The unlock stays applied even when clearing failed.
        }
        return currentState()
    }

    private func enforce(_ state: LockState) throws {
        let blockList = try BlockStore(directory: stateDirectory).load()
        _ = try Enforcer.run(
            state: state,
            blockList: blockList,
            hostsBlocker: HostsBlocker(hostsPath: hostsPath),
            terminator: terminator,
            dryRun: false
        )
    }
}
