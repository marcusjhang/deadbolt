import XCTest
@testable import DeadboltCore

final class MenuBarModelTests: XCTestCase {
    private var directory: URL!
    private var registry: KeyRegistry!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadbolt-menubar-tests-\(UUID().uuidString)", isDirectory: true)
        registry = KeyRegistry(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func key(_ device: USBDeviceIdentity, label: String) -> KeyRecord {
        KeyRecord(
            fingerprint: device.fingerprint,
            tier: device.tier,
            label: label,
            createdAt: Date()
        )
    }

    func testSymbolNameReflectsLockState() {
        let locked = MenuBarModel(state: .locked, devices: [], keys: [])
        XCTAssertEqual(locked.symbolName, "lock.fill")

        let unlocked = MenuBarModel(state: .unlocked, devices: [], keys: [])
        XCTAssertEqual(unlocked.symbolName, "lock.open")
    }

    func testTitleAndStatusText() {
        let model = MenuBarModel(state: .locked, devices: [], keys: [])
        XCTAssertEqual(model.title, "Deadbolt")
        XCTAssertEqual(model.statusText, "Locked")

        let unlocked = MenuBarModel(state: .unlocked, devices: [], keys: [])
        XCTAssertEqual(unlocked.statusText, "Unlocked")
    }

    func testUnlockEnabledOnlyWhenEnrolledKeyAttached() {
        let device = USBDeviceIdentity(
            vendorID: 1234, productID: 5678, serialNumber: "ABC123456789"
        )
        let other = USBDeviceIdentity(
            vendorID: 1234, productID: 5678, serialNumber: "DIFFERENT111"
        )
        let key = self.key(device, label: "Key")

        let attached = MenuBarModel(state: .locked, devices: [device], keys: [key])
        XCTAssertTrue(attached.unlockEnabled)

        let mismatch = MenuBarModel(state: .locked, devices: [other], keys: [key])
        XCTAssertFalse(mismatch.unlockEnabled)

        let absent = MenuBarModel(state: .locked, devices: [], keys: [key])
        XCTAssertFalse(absent.unlockEnabled)
    }

    func testAttachedKeyDescriptionNamesKeyOrNone() {
        let device = USBDeviceIdentity(
            vendorID: 1234, productID: 5678, serialNumber: "ABC123456789"
        )
        let key = self.key(device, label: "Spare Drive")

        let attached = MenuBarModel(state: .locked, devices: [device], keys: [key])
        XCTAssertEqual(attached.attachedKey?.label, "Spare Drive")
        XCTAssertEqual(attached.attachedKeyDescription, "Spare Drive")

        let absent = MenuBarModel(state: .locked, devices: [], keys: [key])
        XCTAssertNil(absent.attachedKey)
        XCTAssertEqual(absent.attachedKeyDescription, "none")
    }

    func testEnrolledKeysListedWithTiers() {
        let device = USBDeviceIdentity(
            vendorID: 1234, productID: 5678, serialNumber: "ABC123456789"
        )
        let key = self.key(device, label: "Key")

        let model = MenuBarModel(state: .unlocked, devices: [], keys: [key])
        XCTAssertEqual(model.enrolledKeys.count, 1)
        XCTAssertEqual(model.enrolledKeys.first?.label, "Key")
        XCTAssertEqual(model.enrolledKeys.first?.tier, .A)
    }

    func testEmptyStateDirectoryReportsUnlockedAndEmptyWithoutThrowing() throws {
        let source = FixtureDeviceSource(devices: [])
        let model = MenuBarModel(
            deviceSource: source,
            registry: registry,
            state: try LockStore(directory: directory).read()
        )

        XCTAssertEqual(model.state, .unlocked)
        XCTAssertNil(model.attachedKey)
        XCTAssertEqual(model.attachedKeyDescription, "none")
        XCTAssertTrue(model.enrolledKeys.isEmpty)
        XCTAssertFalse(model.unlockEnabled)
    }
}
