import XCTest
@testable import DeadboltCore

final class EnforcerTests: XCTestCase {
    private func makeTempHosts(content: String = "") throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadbolt-enforce-\(UUID().uuidString)")
            .path
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    func testFakeTerminatorReportsBlockedRunningApps() throws {
        let terminator = FakeAppTerminator(running: [
            RunningApp(bundleIdentifier: "com.apple.Safari", name: "Safari"),
            RunningApp(bundleIdentifier: "com.apple.Mail", name: "Mail"),
        ])
        let blocked = try terminator.blockedRunningApps(bundleIdentifiers: ["com.apple.Safari"])
        XCTAssertEqual(blocked.map(\.bundleIdentifier), ["com.apple.Safari"])
    }

    func testFakeTerminatorRecordsTerminations() throws {
        let terminator = FakeAppTerminator(running: [
            RunningApp(bundleIdentifier: "com.apple.Safari", name: "Safari"),
        ])
        let blocked = try terminator.blockedRunningApps(bundleIdentifiers: ["com.apple.Safari"])
        for app in blocked { try terminator.terminate(app) }
        XCTAssertEqual(terminator.terminated.map(\.bundleIdentifier), ["com.apple.Safari"])
    }

    func testEnforceLockedAppliesHostsAndTerminates() throws {
        let path = try makeTempHosts(content: "# keep\n127.0.0.1 localhost\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let terminator = FakeAppTerminator(running: [
            RunningApp(bundleIdentifier: "com.apple.Safari", name: "Safari"),
        ])

        let report = try Enforcer.run(
            state: .locked,
            blockList: BlockList(domains: ["example.com"], apps: ["com.apple.Safari"]),
            hostsBlocker: HostsBlocker(hostsPath: path),
            terminator: terminator,
            dryRun: false
        )

        XCTAssertEqual(report.hostsAction, .applied)
        XCTAssertEqual(report.appsTerminated, 1)
        XCTAssertEqual(terminator.terminated.count, 1)
        XCTAssertTrue(try read(path).contains(HostsBlocker.startMarker))
    }

    func testEnforceLockedDryRunChangesNothing() throws {
        let path = try makeTempHosts(content: "# keep\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let terminator = FakeAppTerminator(running: [
            RunningApp(bundleIdentifier: "com.apple.Safari", name: "Safari"),
        ])

        let report = try Enforcer.run(
            state: .locked,
            blockList: BlockList(domains: ["example.com"], apps: ["com.apple.Safari"]),
            hostsBlocker: HostsBlocker(hostsPath: path),
            terminator: terminator,
            dryRun: true
        )

        XCTAssertEqual(report.hostsAction, .applied)
        XCTAssertEqual(report.appsTerminated, 1)
        XCTAssertTrue(terminator.terminated.isEmpty)
        XCTAssertFalse(try read(path).contains(HostsBlocker.startMarker))
    }

    func testEnforceUnlockedClearsHosts() throws {
        let path = try makeTempHosts(content: "# keep\n127.0.0.1 localhost\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let blocker = HostsBlocker(hostsPath: path)
        try blocker.apply(domains: ["example.com"])
        XCTAssertTrue(try read(path).contains(HostsBlocker.startMarker))

        let report = try Enforcer.run(
            state: .unlocked,
            blockList: BlockList(domains: ["example.com"]),
            hostsBlocker: blocker,
            terminator: FakeAppTerminator(running: []),
            dryRun: false
        )

        XCTAssertEqual(report.hostsAction, .cleared)
        XCTAssertFalse(try read(path).contains(HostsBlocker.startMarker))
        XCTAssertTrue(try read(path).contains("127.0.0.1 localhost"))
    }
}
