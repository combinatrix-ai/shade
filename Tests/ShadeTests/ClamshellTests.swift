@testable import Shade
import XCTest

final class ClamshellTests: XCTestCase {
    func testAwakeHoldPreventsACSystemSleepForClamshellMode() {
        let arguments = AwakeHold.arguments(parentPID: 42)
        XCTAssertTrue(arguments.contains("-d"))
        XCTAssertTrue(arguments.contains("-i"))
        XCTAssertTrue(arguments.contains("-s"))
        XCTAssertTrue(arguments.contains("-u"))
        XCTAssertEqual(Array(arguments.suffix(2)), ["-w", "42"])
    }
}
