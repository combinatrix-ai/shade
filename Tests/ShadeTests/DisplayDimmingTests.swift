@testable import Shade
import XCTest

final class DisplayDimmingTests: XCTestCase {
    func testPhysicalDisplayClassificationExcludesVirtualOutputs() {
        XCTAssertTrue(Brightness.isPhysicalDisplay(isBuiltin: true, vendor: 0, model: 0))
        XCTAssertTrue(Brightness.isPhysicalDisplay(isBuiltin: false, vendor: 2533, model: 4224))
        XCTAssertFalse(Brightness.isPhysicalDisplay(isBuiltin: false, vendor: 0, model: 4224))
        XCTAssertFalse(Brightness.isPhysicalDisplay(isBuiltin: false, vendor: 2533, model: 0))
    }
}
