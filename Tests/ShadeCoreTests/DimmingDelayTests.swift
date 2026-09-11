import ShadeCore
import XCTest

final class DimmingDelayTests: XCTestCase {
    func testAllWholeMinuteSettingsSurviveReload() {
        for minutes in 1...60 {
            let seconds = Double(minutes * 60)
            XCTAssertEqual(DimmingDelay.restoredSeconds(seconds), seconds)
        }
    }

    func testMissingOutOfRangeAndNonMinuteSettingsUseOneMinute() {
        for saved in [0.0, 30, -60, 61, 90, 3601, 3660, .infinity, -.infinity, .nan] {
            XCTAssertEqual(DimmingDelay.restoredSeconds(saved), 60)
        }
    }
}
