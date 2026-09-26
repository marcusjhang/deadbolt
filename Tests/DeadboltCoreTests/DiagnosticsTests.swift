import XCTest
@testable import DeadboltCore

final class DiagnosticsTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadbolt-diag-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testReportReflectsStateKeysAndBlockList() throws {
        let hosts = directory.appendingPathComponent("hosts")
        try "127.0.0.1 localhost\n".write(to: hosts, atomically: true, encoding: .utf8)

        let device = USBDeviceIdentity(
            vendorID: 1234, productID: 5678, serialNumber: "ABC123456789"
        )
        let key = KeyRecord(
            fingerprint: device.fingerprint, tier: .A, label: "Key", createdAt: Date()
        )
        try KeyRegistry(directory: directory).enroll(key)
        try BlockStore(directory: directory).addDomain("example.com")
        try BlockStore(directory: directory).addApp("com.apple.Safari")
        try LockStore(directory: directory).write(.locked)

        let report = Diagnostics.report(
            stateDirectory: directory,
            hostsPath: hosts.path,
            deviceSource: FixtureDeviceSource(devices: [device])
        )

        XCTAssertEqual(report.version, Deadbolt.version)
        XCTAssertEqual(report.state, "locked")
        XCTAssertEqual(report.attachedKey, "Key")
        XCTAssertEqual(report.enrolledKeyCount, 1)
        XCTAssertEqual(report.enrolledKeyTiers, ["A"])
        XCTAssertEqual(report.blockedDomainCount, 1)
        XCTAssertEqual(report.blockedAppCount, 1)
        XCTAssertTrue(report.hostsPathWritable)
    }

    func testReportEmptyStateDoesNotThrow() {
        let report = Diagnostics.report(
            stateDirectory: directory,
            hostsPath: directory.appendingPathComponent("hosts").path,
            deviceSource: FixtureDeviceSource(devices: [])
        )

        XCTAssertEqual(report.state, "unlocked")
        XCTAssertNil(report.attachedKey)
        XCTAssertEqual(report.enrolledKeyCount, 0)
        XCTAssertEqual(report.blockedDomainCount, 0)
        XCTAssertEqual(report.blockedAppCount, 0)
    }
}
