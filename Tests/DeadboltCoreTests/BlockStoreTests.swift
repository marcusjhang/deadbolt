import XCTest
@testable import DeadboltCore

final class BlockStoreTests: XCTestCase {
    private var directory: URL!
    private var store: BlockStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadbolt-block-tests-\(UUID().uuidString)", isDirectory: true)
        store = BlockStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testEmptyBlockList() throws {
        let list = try store.load()
        XCTAssertTrue(list.domains.isEmpty)
        XCTAssertTrue(list.apps.isEmpty)
    }

    func testAddAndRemoveDomain() throws {
        try store.addDomain("news.ycombinator.com")
        XCTAssertEqual(try store.load().domains, ["news.ycombinator.com"])

        try store.removeDomain("news.ycombinator.com")
        XCTAssertTrue(try store.load().domains.isEmpty)
    }

    func testAddAndRemoveApp() throws {
        try store.addApp("com.apple.Safari")
        XCTAssertEqual(try store.load().apps, ["com.apple.Safari"])

        try store.removeApp("com.apple.Safari")
        XCTAssertTrue(try store.load().apps.isEmpty)
    }

    func testAddDomainIsDeduplicatedAndNormalized() throws {
        try store.addDomain("  News.Ycombinator.COM ")
        try store.addDomain("news.ycombinator.com")
        XCTAssertEqual(try store.load().domains, ["news.ycombinator.com"])
    }

    func testAddAppIsDeduplicated() throws {
        try store.addApp("com.apple.Safari")
        try store.addApp("com.apple.Safari")
        XCTAssertEqual(try store.load().apps, ["com.apple.Safari"])
    }

    func testPersistsAcrossInstances() throws {
        try store.addDomain("example.com")
        try store.addApp("com.example.App")

        let fresh = BlockStore(directory: directory)
        let list = try fresh.load()
        XCTAssertEqual(list.domains, ["example.com"])
        XCTAssertEqual(list.apps, ["com.example.App"])
    }
}
