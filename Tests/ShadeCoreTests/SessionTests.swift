@testable import ShadeCore
import XCTest

final class SessionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1000)
    func testCountdownNeverExceedsDelayWithAStaleDisplayClock() {
        var s = Session()
        s.enable(now: now, delay: 60)
        XCTAssertEqual(s.remaining(now: now.addingTimeInterval(-0.25)), 60)
        s.reserve(now: now.addingTimeInterval(0.01), delay: 60)
        XCTAssertEqual(s.remaining(now: now), 60)
        XCTAssertEqual(s.remaining(now: now.addingTimeInterval(1.01)), 59)
        s.didDim()
        s.didRestore(now: now.addingTimeInterval(10), delay: 30)
        XCTAssertEqual(s.remaining(now: now.addingTimeInterval(9.75)), 30)
        XCTAssertEqual(s.remaining(now: now.addingTimeInterval(41)), 0)
    }

    func testChangingDelayRestartsFromConfirmationTime() {
        var s = Session()
        s.enable(now: now, delay: 60)
        let confirmation = now.addingTimeInterval(47)
        s.reserve(now: confirmation, delay: 3600)
        XCTAssertEqual(s.remaining(now: confirmation), 3600)
        XCTAssertFalse(s.isDue(now: now.addingTimeInterval(60)))
        XCTAssertTrue(s.isDue(now: confirmation.addingTimeInterval(3600)))

        let shorter = confirmation.addingTimeInterval(100)
        s.reserve(now: shorter, delay: 60)
        XCTAssertEqual(s.remaining(now: shorter), 60)
        XCTAssertFalse(s.isDue(now: shorter.addingTimeInterval(59)))
        XCTAssertTrue(s.isDue(now: shorter.addingTimeInterval(60)))
    }

    func testRestoreAutomaticallyRearmsFullDelay() {
        var s = Session()
        s.enable(now: now, delay: 60)
        XCTAssertFalse(s.isDue(now: now.addingTimeInterval(59.9)))
        XCTAssertTrue(s.isDue(now: now.addingTimeInterval(60)))
        s.didDim(); s.didRestore(now: now.addingTimeInterval(70), delay: 60)
        XCTAssertEqual(s.remaining(now: now.addingTimeInterval(70)), 60)
        XCTAssertTrue(s.isOn)
        XCTAssertFalse(s.isDue(now: now.addingTimeInterval(129)))
        XCTAssertTrue(s.isDue(now: now.addingTimeInterval(130)))
    }

    func testReservationRestartsCountdownAndOffCannotDim() {
        var s = Session()
        s.enable(now: now, delay: 60)
        s.reserve(now: now.addingTimeInterval(30), delay: 60)
        XCTAssertEqual(s.remaining(now: now.addingTimeInterval(60)), 30)
        s.disable(); s.didDim(); s.reserve(now: now, delay: 60)
        XCTAssertEqual(s.phase, .off)
    }

    func testInputCannotWakeDarkSessionAndRestoreCannotEnableOffSession() {
        var s = Session()
        s.didRestore(now: now, delay: 60)
        XCTAssertEqual(s.phase, .off)
        s.enable(now: now, delay: 60)
        s.didDim()
        s.reserve(now: now.addingTimeInterval(90), delay: 60)
        XCTAssertEqual(s.phase, .dark)
        XCTAssertFalse(s.isDue(now: now.addingTimeInterval(200)))
    }

    func testWakeRequiresPhysicalActivityAndOptIn() {
        var s = Session()
        XCTAssertEqual(s.activityResponse(detected: true, wakeOnTouch: true), .none)
        s.enable(now: now, delay: 60)
        XCTAssertEqual(s.activityResponse(detected: true, wakeOnTouch: false), .postpone)
        s.didDim()
        XCTAssertEqual(s.activityResponse(detected: false, wakeOnTouch: true), .none)
        XCTAssertEqual(s.activityResponse(detected: true, wakeOnTouch: false), .none)
        XCTAssertEqual(s.activityResponse(detected: true, wakeOnTouch: true), .restore)
        s.didRestore(now: now.addingTimeInterval(90), delay: 60)
        XCTAssertEqual(s.remaining(now: now.addingTimeInterval(90)), 60)
        XCTAssertTrue(s.isDue(now: now.addingTimeInterval(150)))
    }
}
