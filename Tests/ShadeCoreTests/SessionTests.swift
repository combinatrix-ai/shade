@testable import ShadeCore
import XCTest

final class SessionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1000)
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
