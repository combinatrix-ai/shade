@testable import Shade
import XCTest

final class DimmingTimerTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var model: AppModel!

    override func setUp() {
        suite = "shade-timer-tests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        model = AppModel(demo: true, defaults: defaults)
    }

    override func tearDown() {
        model.demo = true
        model.shutdown()
        model = nil
        defaults.removePersistentDomain(forName: suite)
    }

    func testConfirmRestartsCountdownEvenWhenChoosingSameDelay() {
        model.enable()
        model.editingDelay = true
        model.setDelay(minutes: 60)
        XCTAssertFalse(model.editingDelay)
        XCTAssertEqual(model.delay, 3600)
        XCTAssertEqual(model.title, "Dimming in 60:00")
        model.now = model.now.addingTimeInterval(47)
        XCTAssertEqual(model.title, "Dimming in 59:13")
        model.setDelay(minutes: 60)
        XCTAssertEqual(model.title, "Dimming in 60:00")
        model.setDelay(minutes: 1)
        XCTAssertEqual(model.title, "Dimming in 1:00")
    }

    func testInvalidMinutesCannotChangeSettingsOrCloseEditor() {
        model.enable()
        let phase = model.session.phase
        model.editingDelay = true
        for minutes in [0, -1, 61, Int.max] {
            model.setDelay(minutes: minutes)
            XCTAssertEqual(model.delay, 60)
            XCTAssertEqual(model.session.phase, phase)
            XCTAssertTrue(model.editingDelay)
        }
    }

    func testConfirmedMinutesPersistAndReload() {
        // setDelay only saves the setting and rearms a pending session. Keep all
        // setup, system services, and teardown in demo mode; use an isolated suite.
        for minutes in [1, 7, 30, 60] {
            model.demo = false
            model.setDelay(minutes: minutes)
            model.demo = true
            XCTAssertEqual(defaults.double(forKey: "delay"), Double(minutes * 60))
            let reloaded = AppModel(demo: true, defaults: defaults)
            XCTAssertEqual(reloaded.delay, Double(minutes * 60))
            reloaded.shutdown()
        }
    }

    func testSettingsChangeWhileOffOrDarkDoesNotStartOrRestore() {
        model.setDelay(minutes: 7)
        XCTAssertFalse(model.isOn)
        model.enable()
        XCTAssertEqual(model.title, "Dimming in 7:00")
        model.dim()
        model.setDelay(minutes: 15)
        XCTAssertTrue(model.isDark)
        model.primaryAction()
        XCTAssertEqual(model.title, "Dimming in 15:00")
    }
}
