import XCTest
@testable import DeadboltCore

final class HostsBlockerTests: XCTestCase {
    private func makeTempHosts(content: String = "") throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadbolt-hosts-\(UUID().uuidString)")
            .path
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    func testHostsPathResolution() {
        XCTAssertEqual(HostsPath.resolve(explicit: "/a", environment: [:]), "/a")
        XCTAssertEqual(
            HostsPath.resolve(explicit: nil, environment: ["DEADBOLT_HOSTS_PATH": "/b"]),
            "/b"
        )
        XCTAssertEqual(HostsPath.resolve(explicit: nil, environment: [:]), "/etc/hosts")
        XCTAssertEqual(
            HostsPath.resolve(explicit: "/a", environment: ["DEADBOLT_HOSTS_PATH": "/b"]),
            "/a"
        )
    }

    func testApplyWritesManagedBlock() throws {
        let path = try makeTempHosts(content: "# a comment\n127.0.0.1 localhost\n")
        defer { try? FileManager.default.removeItem(atPath: path) }

        try HostsBlocker(hostsPath: path).apply(domains: ["example.com"])

        let content = try read(path)
        XCTAssertTrue(content.contains(HostsBlocker.startMarker))
        XCTAssertTrue(content.contains(HostsBlocker.endMarker))
        XCTAssertTrue(content.contains("0.0.0.0 example.com"))
        XCTAssertTrue(content.contains("0.0.0.0 www.example.com"))
        XCTAssertTrue(content.contains("::1 example.com"))
        XCTAssertTrue(content.contains("::1 www.example.com"))
        XCTAssertTrue(content.contains("# a comment"))
        XCTAssertTrue(content.contains("127.0.0.1 localhost"))
    }

    func testApplyIsIdempotent() throws {
        let path = try makeTempHosts(content: "# c\n127.0.0.1 localhost\n")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let blocker = HostsBlocker(hostsPath: path)

        try blocker.apply(domains: ["example.com"])
        let once = try read(path)
        try blocker.apply(domains: ["example.com"])
        let twice = try read(path)

        XCTAssertEqual(once, twice)
        let markerCount = once.components(separatedBy: HostsBlocker.startMarker).count - 1
        XCTAssertEqual(markerCount, 1)
    }

    func testClearRemovesOnlyManagedBlockAndPreservesSurrounding() throws {
        let original = "# top comment\n127.0.0.1 localhost\n::1 localhost\n# bottom comment\n"
        let path = try makeTempHosts(content: original)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let blocker = HostsBlocker(hostsPath: path)

        try blocker.apply(domains: ["example.com", "news.ycombinator.com"])
        try blocker.clear()

        let content = try read(path)
        XCTAssertFalse(content.contains(HostsBlocker.startMarker))
        XCTAssertFalse(content.contains(HostsBlocker.endMarker))
        XCTAssertEqual(content, original)
    }

    func testClearWithoutBlockLeavesFileUnchanged() throws {
        let original = "# c\n127.0.0.1 localhost\n"
        let path = try makeTempHosts(content: original)
        defer { try? FileManager.default.removeItem(atPath: path) }

        try HostsBlocker(hostsPath: path).clear()

        XCTAssertEqual(try read(path), original)
    }

    func testNotWritableFailsAndLeavesContentUnchanged() throws {
        let path = try makeTempHosts(content: "# keep\n")
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: path
            )
            try? FileManager.default.removeItem(atPath: path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: path)
        let blocker = HostsBlocker(hostsPath: path)

        XCTAssertThrowsError(try blocker.apply(domains: ["example.com"])) {
            XCTAssertEqual($0 as? HostsBlockerError, .notWritable(path))
        }
        XCTAssertEqual(try read(path), "# keep\n")
    }
}
