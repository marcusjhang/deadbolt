import XCTest
@testable import DeadboltCore

final class TimedLockTests: XCTestCase {
    private var directory: URL!
    private var store: LockStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deadbolt-timed-tests-\(UUID().uuidString)", isDirectory: true)
        store = LockStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func date(_ string: String) -> Date {
        Clock.parseRFC3339(string)!
    }

    // MARK: - Clock

    func testClockParsesRFC3339WithAndWithoutFraction() {
        XCTAssertEqual(
            Clock.parseRFC3339("2026-01-01T00:00:00Z"),
            date("2026-01-01T00:00:00Z")
        )
        XCTAssertEqual(
            Clock.parseRFC3339("2026-01-01T00:00:00.000Z"),
            date("2026-01-01T00:00:00Z")
        )
    }

    func testClockHonorsDeadboltNowOverride() {
        let now = Clock.now(environment: ["DEADBOLT_NOW": "2026-01-01T00:00:00Z"])
        XCTAssertEqual(now, date("2026-01-01T00:00:00Z"))
    }

    // MARK: - LockStore lockedUntil persistence

    func testLockStorePersistsLockedUntil() throws {
        let until = date("2026-01-01T00:30:00Z")
        try store.write(.locked, lockedUntil: until)

        let snapshot = try LockStore(directory: directory).readSnapshot()
        XCTAssertEqual(snapshot.state, .locked)
        XCTAssertEqual(snapshot.lockedUntil, until)
    }

    func testLockStoreWithoutLockedUntilHasNone() throws {
        try store.write(.locked)
        let snapshot = try store.readSnapshot()
        XCTAssertEqual(snapshot.state, .locked)
        XCTAssertNil(snapshot.lockedUntil)
    }

    // MARK: - LockMachine timed lock

    func testTimedLockActiveWhileBeforeDeadline() {
        let until = date("2026-01-01T00:30:00Z")
        XCTAssertTrue(LockMachine.timedLockActive(lockedUntil: until, now: date("2026-01-01T00:00:00Z")))
        XCTAssertFalse(LockMachine.timedLockActive(lockedUntil: until, now: date("2026-01-01T00:30:00Z")))
        XCTAssertFalse(LockMachine.timedLockActive(lockedUntil: until, now: date("2026-01-01T00:31:00Z")))
        XCTAssertFalse(LockMachine.timedLockActive(lockedUntil: nil, now: date("2026-01-01T00:00:00Z")))
    }

    func testRemainingMinutesRoundsUpAndNilWhenElapsed() {
        let until = date("2026-01-01T00:30:00Z")
        XCTAssertEqual(LockMachine.remainingMinutes(lockedUntil: until, now: date("2026-01-01T00:00:00Z")), 30)
        XCTAssertEqual(LockMachine.remainingMinutes(lockedUntil: until, now: date("2026-01-01T00:29:01Z")), 1)
        XCTAssertNil(LockMachine.remainingMinutes(lockedUntil: until, now: date("2026-01-01T00:30:00Z")))
        XCTAssertNil(LockMachine.remainingMinutes(lockedUntil: nil, now: date("2026-01-01T00:00:00Z")))
    }

    func testCanUnlockGatedByTimedLock() {
        let device = USBDeviceIdentity(
            vendorID: 1234, productID: 5678, serialNumber: "ABC123456789"
        )
        let key = KeyRecord(fingerprint: device.fingerprint, tier: .A, label: "Key", createdAt: Date())
        let until = date("2026-01-01T00:30:00Z")

        XCTAssertFalse(
            LockMachine.canUnlock(
                devices: [device], keys: [key],
                lockedUntil: until, now: date("2026-01-01T00:00:00Z")
            )
        )
        XCTAssertTrue(
            LockMachine.canUnlock(
                devices: [device], keys: [key],
                lockedUntil: until, now: date("2026-01-01T00:31:00Z")
            )
        )
        XCTAssertFalse(
            LockMachine.canUnlock(
                devices: [], keys: [key],
                lockedUntil: until, now: date("2026-01-01T00:31:00Z")
            )
        )
    }

    // MARK: - ConfigStore

    func testConfigLockOnKeyRemovalDefaultsOff() throws {
        XCTAssertFalse(try ConfigStore(directory: directory).lockOnKeyRemoval())
    }

    func testConfigSetLockOnKeyRemovalPersistsAcrossInstances() throws {
        try ConfigStore(directory: directory).setLockOnKeyRemoval(true)
        XCTAssertTrue(try ConfigStore(directory: directory).lockOnKeyRemoval())
    }

    // MARK: - Watch

    func testWatchLocksOnKeyRemovalWhenEnabled() {
        XCTAssertEqual(
            Watch.nextState(current: .unlocked, lockOnKeyRemoval: true, attachedKey: false),
            .locked
        )
        XCTAssertEqual(
            Watch.nextState(current: .unlocked, lockOnKeyRemoval: true, attachedKey: true),
            .unlocked
        )
        XCTAssertEqual(
            Watch.nextState(current: .unlocked, lockOnKeyRemoval: false, attachedKey: false),
            .unlocked
        )
        XCTAssertEqual(
            Watch.nextState(current: .locked, lockOnKeyRemoval: true, attachedKey: false),
            .locked
        )
    }

    // MARK: - Controller refresh honors lockOnKeyRemoval

    func testControllerRefreshLocksWhenKeyRemovedAndSettingEnabled() throws {
        let device = USBDeviceIdentity(
            vendorID: 1234, productID: 5678, serialNumber: "ABC123456789"
        )
        let key = KeyRecord(fingerprint: device.fingerprint, tier: .A, label: "Key", createdAt: Date())
        try KeyRegistry(directory: directory).enroll(key)
        try ConfigStore(directory: directory).setLockOnKeyRemoval(true)
        let hostsPath = directory.appendingPathComponent("hosts").path

        let controller = DeadboltController(
            stateDirectory: directory,
            hostsPath: hostsPath,
            deviceSource: FixtureDeviceSource(devices: []),
            terminator: FakeAppTerminator(running: [])
        )

        XCTAssertEqual(controller.currentState(), .unlocked)
        let model = controller.refresh()
        XCTAssertEqual(model.state, .locked)
        XCTAssertEqual(controller.currentState(), .locked)
    }
}
