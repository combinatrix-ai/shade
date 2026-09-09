@testable import ShadeCore
import XCTest

final class SessionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1000)
    func testDeadlineAndRestoreDoNotAutomaticallyRedim() {
        var s = Session()
        s.enable(now: now, delay: 60)
        XCTAssertFalse(s.isDue(now: now.addingTimeInterval(59.9)))
        XCTAssertTrue(s.isDue(now: now.addingTimeInterval(60)))
        s.didDim(); s.didRestore()
        XCTAssertEqual(s.phase, .visible)
        XCTAssertTrue(s.isOn)
        XCTAssertFalse(s.isDue(now: now.addingTimeInterval(600)))
    }

    func testReservationRestartsCountdownAndOffCannotDim() {
        var s = Session()
        s.enable(now: now, delay: 60)
        s.reserve(now: now.addingTimeInterval(30), delay: 60)
        XCTAssertEqual(s.remaining(now: now.addingTimeInterval(60)), 30)
        s.disable(); s.didDim(); s.reserve(now: now, delay: 60)
        XCTAssertEqual(s.phase, .off)
    }
}
