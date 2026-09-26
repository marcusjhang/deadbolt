import XCTest
@testable import DeadboltCore

final class LockStateTests: XCTestCase {
    private var directory: URL!
    private var store: LockStore!
    private var registry: KeyRegistry!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadbolt-lock-tests-\(UUID().uuidString)", isDirectory: true)
        store = LockStore(directory: directory)
        registry = KeyRegistry(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testDefaultStateIsUnlocked() throws {
        XCTAssertEqual(try store.read(), .unlocked)
    }

    func testLockPersistsAcrossInstances() throws {
        try store.write(.locked)
        let fresh = LockStore(directory: directory)
        XCTAssertEqual(try fresh.read(), .locked)
    }

    func testUnlockRequiresMatchingAttachedKey() throws {
        let device = USBDeviceIdentity(
            vendorID: 1234, productID: 5678, serialNumber: "ABC123456789"
        )
        let key = KeyRecord(
            fingerprint: device.fingerprint,
            tier: .A,
            label: "Key",
            createdAt: Date()
        )
        try registry.enroll(key)

        XCTAssertTrue(LockMachine.canUnlock(devices: [device], keys: [key]))
        XCTAssertFalse(LockMachine.canUnlock(devices: [], keys: [key]))

        let other = USBDeviceIdentity(
            vendorID: 1234, productID: 5678, serialNumber: "DIFFERENT111"
        )
        XCTAssertFalse(LockMachine.canUnlock(devices: [other], keys: [key]))
    }

    func testAttachedKeyNamesWhichKeyMatches() throws {
        let device = USBDeviceIdentity(
            vendorID: 1234, productID: 5678, serialNumber: "ABC123456789"
        )
        let key = KeyRecord(
            fingerprint: device.fingerprint, tier: .A, label: "Spare Drive", createdAt: Date()
        )
        try registry.enroll(key)

        let attached = LockMachine.attachedKey(devices: [device], keys: try registry.load())
        XCTAssertEqual(attached?.label, "Spare Drive")
    }

    func testResetClearsState() throws {
        try store.write(.locked)
        try registry.enroll(KeyRecord(fingerprint: "fp", tier: .A, label: "K", createdAt: Date()))

        try store.remove()
        try registry.removeAll()

        XCTAssertEqual(try store.read(), .unlocked)
        XCTAssertTrue(try registry.load().isEmpty)
    }

    func testStateDirectoryEnvironmentOverride() {
        let dir = URL(fileURLWithPath: "/tmp/override", isDirectory: true)
        let resolved = StateDirectory.resolve(environment: ["DEADBOLT_STATE_DIR": dir.path])
        XCTAssertEqual(resolved.path, dir.path)
    }

    func testStateDirectoryDefaultsWhenUnset() {
        let resolved = StateDirectory.resolve(environment: [:])
        XCTAssertTrue(resolved.path.hasSuffix("Library/Application Support/Deadbolt"))
    }
}
