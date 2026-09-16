import XCTest
@testable import ShadeCore

final class AutoLockTests: XCTestCase {
    func testEarlierRoutePlusGrace() {
        XCTAssertEqual(AutoLockStatus.resolve(display: .after(600), screensaver: .after(300), password: .after(0)), .after(300))
        XCTAssertEqual(AutoLockStatus.resolve(display: .after(600), screensaver: .disabled, password: .after(300)), .after(900))
        XCTAssertEqual(AutoLockStatus.resolve(display: .after(600), screensaver: .after(1200), password: .after(30)), .after(630))
    }
    func testMissingRouteOrGraceNeverProducesInventedNumber() {
        XCTAssertEqual(AutoLockStatus.resolve(display: .after(600), screensaver: .unknown, password: .after(0)), .unknown)
        XCTAssertEqual(AutoLockStatus.resolve(display: .unknown, screensaver: .after(60), password: .after(0)), .unknown)
        XCTAssertEqual(AutoLockStatus.resolve(display: .after(600), screensaver: .disabled, password: .unknown), .unknown)
    }
    func testPartialSuppressionDoesNotMeanAllLockingPrevented() {
        XCTAssertEqual(AutoLockStatus.resolve(display: .prevented, screensaver: .after(60), password: .after(0)), .after(60))
        XCTAssertEqual(AutoLockStatus.resolve(display: .prevented, screensaver: .unknown, password: .after(0)), .unknown)
    }
    func testBothPreventedOrRemainingRouteDisabled() {
        XCTAssertEqual(AutoLockStatus.resolve(display: .prevented, screensaver: .prevented, password: .unknown), .prevented)
        XCTAssertEqual(AutoLockStatus.resolve(display: .prevented, screensaver: .disabled, password: .after(0)), .prevented)
    }
    func testConfirmedDisabled() {
        XCTAssertEqual(AutoLockStatus.resolve(display: .unknown, screensaver: .unknown, password: .disabled), .disabled)
        XCTAssertEqual(AutoLockStatus.resolve(display: .disabled, screensaver: .disabled, password: .unknown), .disabled)
    }
    func testTimerValidationAndUnknownAssertions() {
        XCTAssertEqual(LockTimer.seconds(nil), .unknown)
        XCTAssertEqual(LockTimer.seconds(-1), .unknown)
        XCTAssertEqual(LockTimer.seconds(Int.max), .unknown)
        XCTAssertEqual(LockTimer.seconds(0), .disabled)
        XCTAssertEqual(LockRoute(timer: .after(600), prevented: nil), .unknown)
        XCTAssertEqual(LockRoute(timer: .disabled, prevented: nil), .disabled)
        XCTAssertEqual(LockRoute(timer: .unknown, prevented: true), .prevented)
    }
    func testNoRoundingToMisleadingWholeMinutes() {
        XCTAssertEqual(AutoLockStatus.after(600).label, "Auto-Lock after 10 min")
        XCTAssertEqual(AutoLockStatus.after(630).label, "Auto-Lock after 10m 30s")
        XCTAssertEqual(AutoLockStatus.after(30).label, "Auto-Lock after 30 sec")
    }
}
