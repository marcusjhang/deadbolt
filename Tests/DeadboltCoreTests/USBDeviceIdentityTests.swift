import XCTest
@testable import DeadboltCore

final class USBDeviceIdentityTests: XCTestCase {
    func testTierA_uniqueSerialPlusVIDPID() {
        let device = USBDeviceIdentity(
            vendorID: 0x1234,
            productID: 0x5678,
            serialNumber: "A1:B2:C3:D4:E5:F6"
        )
        XCTAssertEqual(device.tier, .A)
        XCTAssertFalse(device.assessment.refused)
    }

    func testTierB_volumeUUIDOnly() {
        let device = USBDeviceIdentity(
            volumeUUID: "11111111-2222-3333-4444-555555555555"
        )
        XCTAssertEqual(device.tier, .B)
        XCTAssertFalse(device.assessment.refused)
    }

    func testTierC_containerIDPlusVIDPID() {
        let device = USBDeviceIdentity(
            vendorID: 0x1234,
            productID: 0x5678,
            containerID: "C0FFEE1234"
        )
        XCTAssertEqual(device.tier, .C)
        XCTAssertFalse(device.assessment.refused)
    }

    func testTierD_vendorProductStrings() {
        let device = USBDeviceIdentity(
            vendorID: 0x1234,
            productID: 0x5678,
            vendorName: "Acme",
            productName: "Widget"
        )
        XCTAssertEqual(device.tier, .D)
        XCTAssertFalse(device.assessment.refused)
    }

    func testTierE_placeholderSerialOnly() {
        let device = USBDeviceIdentity(serialNumber: "000000000")
        XCTAssertEqual(device.tier, .E)
        XCTAssertTrue(device.assessment.refused)
    }

    func testMissingIdentityIsRefused() {
        let empty = USBDeviceIdentity()
        XCTAssertEqual(empty.tier, .E)
        XCTAssertTrue(empty.assessment.refused)
    }

    func testVidPidWithoutUsableIdentityIsRefused() {
        let device = USBDeviceIdentity(vendorID: 0x1234, productID: 0x5678)
        XCTAssertEqual(device.tier, .E)
        XCTAssertTrue(device.assessment.refused)
    }

    func testAllZerosSerialIsPlaceholder() {
        XCTAssertTrue(isPlaceholderSerial("000000000"))
        XCTAssertNil(USBDeviceIdentity(
            vendorID: 0x1234, productID: 0x5678, serialNumber: "000000000"
        ).usableSerial)
    }

    func testRepeatedCharacterSerialIsPlaceholder() {
        XCTAssertTrue(isPlaceholderSerial("AAAAAAA"))
        XCTAssertTrue(isPlaceholderSerial("1111111"))
    }

    func testShortSerialIsPlaceholder() {
        XCTAssertTrue(isPlaceholderSerial("123"))
        XCTAssertTrue(isPlaceholderSerial("ab"))
        XCTAssertTrue(isPlaceholderSerial("A"))
    }

    func testSerialEqualToVendorIDIsPlaceholder() {
        XCTAssertTrue(isPlaceholderSerial("1234", vendorID: 1234, productID: 9999))
    }

    func testSerialEqualToProductIDIsPlaceholder() {
        XCTAssertTrue(isPlaceholderSerial("5678", vendorID: 9999, productID: 5678))
    }

    func testSerialEqualToVIDOrPIDNeverContributesToTierA() {
        let device = USBDeviceIdentity(
            vendorID: 1234,
            productID: 5678,
            serialNumber: "1234"
        )
        XCTAssertNotEqual(device.tier, .A)
        XCTAssertEqual(device.tier, .E)
    }

    func testLocationDoesNotAffectTier() {
        let a = USBDeviceIdentity(
            vendorID: 0x1234, productID: 0x5678,
            serialNumber: "REAL123456", location: "0x14000000"
        )
        let b = USBDeviceIdentity(
            vendorID: 0x1234, productID: 0x5678,
            serialNumber: "REAL123456", location: "0x34000000"
        )
        XCTAssertEqual(a.tier, b.tier)
        XCTAssertEqual(a.assessment, b.assessment)
    }

    func testAssessmentReasonIsNonEmpty() {
        for tier in IdentityTier.allCases {
            let device = device(for: tier)
            XCTAssertFalse(device.assessment.reason.isEmpty)
        }
    }

    func testFixtureSourceComputesAllTiers() throws {
        let json = """
        [
          {"vendorID": 1234, "productID": 5678, "serialNumber": "ABC123456789", "name": "Key A"},
          {"volumeUUID": "11111111-2222-3333-4444-555555555555", "name": "Key B"},
          {"vendorID": 1234, "productID": 5678, "containerID": "C0FFEE", "name": "Key C"},
          {"vendorID": 1234, "productID": 5678, "vendorName": "Acme", "productName": "Widget", "name": "Key D"},
          {"serialNumber": "000000000", "name": "Key E"}
        ]
        """
        let source = try FixtureDeviceSource(jsonData: Data(json.utf8))
        let devices = try source.listDevices()
        XCTAssertEqual(devices.count, 5)
        XCTAssertEqual(devices.map(\.tier), [.A, .B, .C, .D, .E])
    }

    func testFixtureSourceDecodesIsRemovableDefault() throws {
        let json = #"[{"serialNumber": "ABC12345", "name": "Key"}]"#
        let source = try FixtureDeviceSource(jsonData: Data(json.utf8))
        let devices = try source.listDevices()
        XCTAssertEqual(devices.first?.isRemovable, true)
    }

    private func device(for tier: IdentityTier) -> USBDeviceIdentity {
        switch tier {
        case .A:
            return USBDeviceIdentity(vendorID: 0x1, productID: 0x2, serialNumber: "UNIQUESERIAL")
        case .B:
            return USBDeviceIdentity(volumeUUID: "11111111-2222-3333-4444-555555555555")
        case .C:
            return USBDeviceIdentity(vendorID: 0x1, productID: 0x2, containerID: "CID")
        case .D:
            return USBDeviceIdentity(vendorID: 0x1, productID: 0x2, vendorName: "V", productName: "P")
        case .E:
            return USBDeviceIdentity(serialNumber: "0000")
        }
    }
}
