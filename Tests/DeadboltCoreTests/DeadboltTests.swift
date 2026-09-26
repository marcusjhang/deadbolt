import XCTest
@testable import DeadboltCore

final class DeadboltTests: XCTestCase {
    func testVersionIsNotEmpty() {
        XCTAssertFalse(Deadbolt.version.isEmpty)
    }
}
