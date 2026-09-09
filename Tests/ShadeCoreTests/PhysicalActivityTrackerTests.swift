@testable import ShadeCore
import XCTest

final class PhysicalActivityTrackerTests: XCTestCase {
    func testDimmingClickTailIsIgnoredEvenWhenPolledAfterGracePeriod() {
        var tracker = PhysicalActivityTracker()
        XCTAssertFalse(tracker.sample(idle: 0, uptime: 100))
        tracker.suppress(until: 101)
        // Mouse-up / residual movement belongs to the gesture that dimmed.
        XCTAssertFalse(tracker.sample(idle: 0, uptime: 100.2))
        // A delayed poll must not reinterpret input from inside the grace period.
        XCTAssertFalse(tracker.sample(idle: 0.7, uptime: 101.5))
        XCTAssertFalse(tracker.sample(idle: 1.2, uptime: 102))
        XCTAssertTrue(tracker.sample(idle: 0, uptime: 102.1))
    }

    func testContinuousMotionCanWakeAfterGraceAndLaterDimmingRearmsIt() {
        var tracker = PhysicalActivityTracker()
        XCTAssertFalse(tracker.sample(idle: 10, uptime: 100))
        tracker.suppress(until: 101)
        XCTAssertFalse(tracker.sample(idle: 0, uptime: 100.9))
        XCTAssertTrue(tracker.sample(idle: 0, uptime: 101.1))
        tracker.suppress(until: 103)
        XCTAssertFalse(tracker.sample(idle: 0, uptime: 102.5))
        XCTAssertTrue(tracker.sample(idle: 0, uptime: 103.1))
    }

    func testIdleClockNoiseDoesNotCountAsInput() {
        var tracker = PhysicalActivityTracker()
        XCTAssertFalse(tracker.sample(idle: 10, uptime: 100))
        XCTAssertFalse(tracker.sample(idle: 10.48, uptime: 100.5))
        XCTAssertTrue(tracker.sample(idle: 0, uptime: 101))
    }
}
