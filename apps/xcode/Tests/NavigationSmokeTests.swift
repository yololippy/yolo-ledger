import XCTest

@MainActor
final class NavigationSmokeTests: XCTestCase {
    func testFourDestinationsAreReachable() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["暂无账单"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "01-bills")

        navigate(app, destination: "details", title: "明细")
        XCTAssertTrue(app.staticTexts["暂无明细"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "02-details")

        navigate(app, destination: "books", title: "账本")
        XCTAssertTrue(app.staticTexts["暂无账本"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "03-books")

        navigate(app, destination: "settings", title: "设置")
        XCTAssertTrue(app.staticTexts["settings.placeholder"].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "04-settings")

        navigate(app, destination: "bills", title: "账单")
        XCTAssertTrue(app.staticTexts["暂无账单"].waitForExistence(timeout: 10))
    }

    private func navigate(_ app: XCUIApplication, destination: String, title: String) {
        #if os(macOS)
        let item = app.descendants(matching: .any)
            .matching(identifier: "navigation.\(destination)").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.click()
        #else
        let item = app.tabBars.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        #endif
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
