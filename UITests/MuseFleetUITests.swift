import XCTest

final class MuseFleetUITests: XCTestCase {
    func testFourTabsAndAccountCreationPersistAfterRelaunch() {
        let app = XCUIApplication()
        app.launch()
        let tabBar = app.tabBars.element(boundBy: 0)
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))
        let accountTab = tabBar.buttons["tab.accounts"]
        XCTAssertTrue(accountTab.waitForExistence(timeout: 10))
        XCTAssertTrue(accountTab.isHittable)
        accountTab.tap()
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
        accountTab.tap()
        XCTAssertTrue(app.staticTexts[fixture].waitForExistence(timeout: 5))
        tabBar.buttons["tab.inbox"].tap()
        XCTAssertTrue(app.navigationBars["Inbox"].exists)
        tabBar.buttons["tab.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "MuseFleet simulator Settings"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
