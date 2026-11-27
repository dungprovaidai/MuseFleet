import XCTest

final class MuseFleetUITests: XCTestCase {
    func testFourTabsAndAccountCreationPersistAfterRelaunch() {
        let app = XCUIApplication()
        app.launch()
        let accountTab = app.tabBars.buttons.matching(identifier: "tab.accounts")
            .matching(NSPredicate(format: "isHittable == true")).firstMatch
        XCTAssertTrue(accountTab.waitForExistence(timeout: 20), app.debugDescription)
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
        XCTAssertTrue(accountTab.waitForExistence(timeout: 20), app.debugDescription)
        accountTab.tap()
        XCTAssertTrue(app.staticTexts[fixture].waitForExistence(timeout: 5))
        let inboxTab = app.tabBars.buttons.matching(identifier: "tab.inbox")
            .matching(NSPredicate(format: "isHittable == true")).firstMatch
        XCTAssertTrue(inboxTab.waitForExistence(timeout: 10), app.debugDescription)
        inboxTab.tap()
        XCTAssertTrue(app.navigationBars["Inbox"].exists)
        let settingsTab = app.tabBars.buttons.matching(identifier: "tab.settings")
            .matching(NSPredicate(format: "isHittable == true")).firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), app.debugDescription)
        settingsTab.tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "MuseFleet simulator Settings"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
