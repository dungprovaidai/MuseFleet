import XCTest

final class MuseFleetUITests: XCTestCase {
    func testFourTabsAndAccountCreationPersistAfterRelaunch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Accounts"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Accounts"].tap()
        let addButton = app.buttons["account.add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        let name = app.textFields["account.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let fixture = "UI fixture " + String(UUID().uuidString.prefix(8))
        name.tap()
        name.typeText(fixture)
        app.buttons["account.save"].tap()
        // The editor may open the new profile browser; dismiss it before checking metadata.
        let close = app.buttons["browser.close"]
        if close.waitForExistence(timeout: 3) { close.tap() }
        app.terminate()
        app.launch()
        app.tabBars.buttons["Accounts"].tap()
        XCTAssertTrue(app.staticTexts[fixture].waitForExistence(timeout: 5))
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.navigationBars["Inbox"].exists)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "MuseFleet simulator Settings"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
