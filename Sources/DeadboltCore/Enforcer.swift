import Foundation

/// The outcome of an enforcement run.
public struct EnforcementResult: Equatable, Sendable {
    public enum HostsAction: String, Equatable, Sendable {
        case applied
        case cleared
    }

    public let hostsAction: HostsAction
    public let domains: Int
    public let appsTerminated: Int
    public let dryRun: Bool

    public init(hostsAction: HostsAction, domains: Int, appsTerminated: Int, dryRun: Bool) {
        self.hostsAction = hostsAction
        self.domains = domains
        self.appsTerminated = appsTerminated
        self.dryRun = dryRun
    }
}

/// Applies or clears enforcement based on the lock state. Locked applies the
/// hosts block and terminates blocked apps; unlocked clears the hosts block.
/// `--dry-run` reports the would-be actions without changing anything.
public enum Enforcer {
    public static func run(
        state: LockState,
        blockList: BlockList,
        hostsBlocker: HostsBlocker,
        terminator: AppTerminator,
        dryRun: Bool
    ) throws -> EnforcementResult {
        switch state {
        case .locked:
            if !dryRun {
                try hostsBlocker.apply(domains: blockList.domains)
            }
            let blockedApps = try terminator.blockedRunningApps(
                bundleIdentifiers: Set(blockList.apps)
            )
            if !dryRun {
                for app in blockedApps {
                    try terminator.terminate(app)
                }
            }
            return EnforcementResult(
                hostsAction: .applied,
                domains: blockList.domains.count,
                appsTerminated: blockedApps.count,
                dryRun: dryRun
            )
        case .unlocked:
            if !dryRun {
                try hostsBlocker.clear()
            }
            return EnforcementResult(
                hostsAction: .cleared,
                domains: 0,
                appsTerminated: 0,
                dryRun: dryRun
            )
        }
    }
}
