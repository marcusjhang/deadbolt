import XCTest
@testable import DeadboltCore

final class KeyRegistryTests: XCTestCase {
    private var directory: URL!
    private var registry: KeyRegistry!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadbolt-tests-\(UUID().uuidString)", isDirectory: true)
        registry = KeyRegistry(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func tierA(_ serial: String = "ABC123456789", location: String? = nil) -> USBDeviceIdentity {
        USBDeviceIdentity(
            vendorID: 1234, productID: 5678, serialNumber: serial, location: location
        )
    }

    func testFingerprintStableAcrossLocationOnly() {
        let a = tierA(location: "0x14000000")
        let b = tierA(location: "0x34000000")
        XCTAssertEqual(a.fingerprint, b.fingerprint)
    }

    func testFingerprintIgnoresNameAndRemovable() {
        let base = USBDeviceIdentity(
            vendorID: 1, productID: 2, serialNumber: "UNIQUESERIAL",
            isRemovable: true, name: "Before"
        )
        let changed = USBDeviceIdentity(
            vendorID: 1, productID: 2, serialNumber: "UNIQUESERIAL",
            isRemovable: false, name: "After"
        )
        XCTAssertEqual(base.fingerprint, changed.fingerprint)
    }

    func testFingerprintDiffersWhenIdentityChanges() {
        let a = tierA("ABC123456789")
        let b = tierA("XYZ987654321")
        XCTAssertNotEqual(a.fingerprint, b.fingerprint)
    }

    func testEnrollWritesRecordWithAllFields() throws {
        let record = KeyRecord(
            fingerprint: tierA().fingerprint,
            tier: .A,
            label: "My Key",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try registry.enroll(record)

        let keys = try registry.load()
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].fingerprint, record.fingerprint)
        XCTAssertEqual(keys[0].tier, .A)
        XCTAssertEqual(keys[0].label, "My Key")
        XCTAssertEqual(keys[0].createdAt, record.createdAt)

        let data = try Data(contentsOf: registry.keysFileURL)
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"fingerprint\""))
        XCTAssertTrue(text.contains("\"tier\""))
        XCTAssertTrue(text.contains("\"label\""))
        XCTAssertTrue(text.contains("\"createdAt\""))
    }

    func testEnrollmentPolicyRefusesTierE() {
        let device = USBDeviceIdentity(serialNumber: "000000000")
        XCTAssertThrowsError(try EnrollmentPolicy.validate(device, allowWeak: false, allowInternal: false)) {
            XCTAssertEqual($0 as? EnrollmentError, .refusedIdentity)
        }
    }

    func testEnrollmentPolicyRequiresAllowWeakForTierD() {
        let device = USBDeviceIdentity(
            vendorID: 1, productID: 2, vendorName: "Acme", productName: "Widget"
        )
        XCTAssertThrowsError(try EnrollmentPolicy.validate(device, allowWeak: false, allowInternal: false)) {
            XCTAssertEqual($0 as? EnrollmentError, .weakKeyRequiresAllowWeak)
        }
        XCTAssertNoThrow(try EnrollmentPolicy.validate(device, allowWeak: true, allowInternal: false))
    }

    func testEnrollmentPolicyRequiresAllowInternalForNonRemovable() {
        let device = USBDeviceIdentity(
            vendorID: 1, productID: 2, serialNumber: "FIXED123456", isRemovable: false
        )
        XCTAssertThrowsError(try EnrollmentPolicy.validate(device, allowWeak: false, allowInternal: false)) {
            XCTAssertEqual($0 as? EnrollmentError, .nonRemovableRequiresAllowInternal)
        }
        XCTAssertNoThrow(try EnrollmentPolicy.validate(device, allowWeak: false, allowInternal: true))
    }

    func testUnenrollByLabelAndByFingerprint() throws {
        try registry.enroll(KeyRecord(fingerprint: "fp-a", tier: .A, label: "Key One", createdAt: Date()))
        XCTAssertEqual(try registry.unenroll("KEY one"), 1)
        XCTAssertTrue(try registry.load().isEmpty)

        try registry.enroll(KeyRecord(fingerprint: "fp-b", tier: .B, label: "Key Two", createdAt: Date()))
        XCTAssertEqual(try registry.unenroll("fp-b"), 1)
        XCTAssertTrue(try registry.load().isEmpty)
    }

    func testUnenrollUnknownReturnsZero() throws {
        XCTAssertEqual(try registry.unenroll("nope"), 0)
    }

    func testLoadPersistsAcrossRegistryInstances() throws {
        try registry.enroll(KeyRecord(fingerprint: "fp-a", tier: .A, label: "K", createdAt: Date()))
        let fresh = KeyRegistry(directory: directory)
        XCTAssertEqual(try fresh.load().count, 1)
    }

    func testEnrollReplacesExistingKey() throws {
        let first = KeyRecord(fingerprint: "fp-a", tier: .A, label: "First", createdAt: Date())
        let second = KeyRecord(fingerprint: "fp-b", tier: .B, label: "Second", createdAt: Date())
        try registry.enroll(first)
        try registry.enroll(second)

        let keys = try registry.load()
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].fingerprint, "fp-b")
        XCTAssertEqual(keys[0].label, "Second")
    }

    func testEnrollSuitableDevicePersistsExactlyOneKeyRoundTrip() throws {
        let device = USBDeviceIdentity(vendorID: 1234, productID: 5678, serialNumber: "ABC123456789")
        try EnrollmentPolicy.validate(device, allowWeak: false, allowInternal: false)
        let record = KeyRecord(
            fingerprint: device.fingerprint,
            tier: device.tier,
            label: "My Key",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try registry.enroll(record)

        let fresh = KeyRegistry(directory: directory)
        let keys = try fresh.load()
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys[0].fingerprint, device.fingerprint)
        XCTAssertEqual(keys[0].tier, .A)
        XCTAssertEqual(keys[0].label, "My Key")
    }

    func testIsRemovableStorageRules() {
        XCTAssertTrue(isRemovableStorage(mediaRemovable: true, deviceInternal: false, deviceProtocol: "USB"))
        XCTAssertFalse(isRemovableStorage(mediaRemovable: true, deviceInternal: true, deviceProtocol: "SATA"))
        XCTAssertFalse(isRemovableStorage(mediaRemovable: false, deviceInternal: false, deviceProtocol: "USB"))
        XCTAssertFalse(isRemovableStorage(mediaRemovable: true, deviceInternal: false, deviceProtocol: "DMG"))
        XCTAssertFalse(isRemovableStorage(mediaRemovable: true, deviceInternal: false, deviceProtocol: "Disk Image"))
    }
}
