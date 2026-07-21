import XCTest

final class PullDownUITests: XCTestCase {
    @MainActor
    func testMainDownloadFlowIsKeyboardAndAccessibilityReachable() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.windows["PullDown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Download"].exists)
        XCTAssertTrue(app.toolbars.buttons["Open Downloads folder"].exists)

        if #available(macOS 14.0, *) {
            try app.performAccessibilityAudit()
        }
    }
}
