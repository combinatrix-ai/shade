@testable import Shade
import ShadeCore
import XCTest
import IOKit.pwr_mgt

final class AutoLockMonitorTests: XCTestCase {
    func testAssertionsUseIOKitLevelAndDoNotConfuseSystemSleepWithLocking() {
        func assertion(_ type: String, level: Int = Int(kIOPMAssertionLevelOn), name: String = "test", timeout: Int = 0) -> [String: Any] {
            [kIOPMAssertionTypeKey: type, kIOPMAssertionLevelKey: level,
             kIOPMAssertionNameKey: name, kIOPMAssertionTimeoutKey: timeout]
        }
        for entries in [[], [assertion(kIOPMAssertionTypePreventUserIdleSystemSleep)],
                        [assertion("UserIsActive", name: "com.apple.iohideventsystem.queue.tickle", timeout: 600)],
                        [assertion(kIOPMAssertionTypePreventUserIdleDisplaySleep, level: 0)]] {
            let result = AutoLockMonitor.prevention(entries)
            XCTAssertFalse(result.display)
            XCTAssertEqual(result.screensaver, false)
        }
        let displayOnly = AutoLockMonitor.prevention([assertion(kIOPMAssertionTypePreventUserIdleDisplaySleep)])
        XCTAssertTrue(displayOnly.display)
        XCTAssertNil(displayOnly.screensaver)
        let explicit = AutoLockMonitor.prevention([
            assertion(kIOPMAssertionTypePreventUserIdleDisplaySleep),
            assertion("UserIsActive", name: "caffeinate command-line tool", timeout: 28800)
        ])
        XCTAssertTrue(explicit.display)
        XCTAssertEqual(explicit.screensaver, true)
        let unidentified = AutoLockMonitor.prevention([assertion("UserIsActive", name: "some other app", timeout: 600)])
        XCTAssertTrue(unidentified.display)
        XCTAssertNil(unidentified.screensaver)
        let shortPulse = AutoLockMonitor.prevention([assertion("UserIsActive", name: "caffeinate command-line tool", timeout: 5)])
        XCTAssertEqual(shortPulse.screensaver, false)
    }

    func testEffectivePasswordStatusParser() {
        XCTAssertEqual(AutoLockMonitor.parsePasswordStatus("sysadminctl[123] screenLock delay is immediate\n"), .after(0))
        XCTAssertEqual(AutoLockMonitor.parsePasswordStatus("screenLock delay is 300 seconds\n"), .after(300))
        XCTAssertEqual(AutoLockMonitor.parsePasswordStatus("screenLock is off\n"), .disabled)
        for value in ["", "permission denied", "screenLock delay is -1 seconds", "screenLock delay is 99999999999 seconds", "screenLock delay is 300 secondsOops"] {
            XCTAssertEqual(AutoLockMonitor.parsePasswordStatus(value), .unknown)
        }
    }
    func testRejectMalformedPreferenceValues() {
        XCTAssertNil(AutoLockMonitor.integer(true))
        XCTAssertNil(AutoLockMonitor.integer("600"))
        XCTAssertNil(AutoLockMonitor.integer(2.5))
        XCTAssertNil(AutoLockMonitor.integer(-1))
        XCTAssertNil(AutoLockMonitor.integer(Double.infinity))
        XCTAssertEqual(AutoLockMonitor.integer(600), 600)
    }
    func testDemoIsDeterministicAndDoesNotReadMachineState() {
        let name = "shade-lock-test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let model = AppModel(demo: true, defaults: defaults)
        defer { model.shutdown(); defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(model.autoLockStatus, .after(600))
        model.enable()
        XCTAssertEqual(model.autoLockStatus, .prevented)
        model.disable()
        XCTAssertEqual(model.autoLockStatus, .after(600))
    }
}
