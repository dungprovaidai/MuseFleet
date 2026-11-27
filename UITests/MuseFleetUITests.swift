import XCTest

@MainActor
final class MuseFleetUITests: XCTestCase {
    func testFourTabsAndAccountCreationPersistAfterRelaunch() {
        let app = XCUIApplication()
        app.launch()
        guard let accountTab = waitForHittableTab("Accounts", in: app, timeout: 20) else {
            XCTFail("Accounts tab did not become hittable.\n\(app.debugDescription)")
            return
        }
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
        guard let relaunchedAccountTab = waitForHittableTab("Accounts", in: app, timeout: 20) else {
            XCTFail("Accounts tab did not become hittable after relaunch.\n\(app.debugDescription)")
            return
        }
        relaunchedAccountTab.tap()
        XCTAssertTrue(app.staticTexts[fixture].waitForExistence(timeout: 5))
        guard let inboxTab = waitForHittableTab("Inbox", in: app, timeout: 10) else {
            XCTFail("Inbox tab did not become hittable.\n\(app.debugDescription)")
            return
        }
        inboxTab.tap()
        XCTAssertTrue(app.navigationBars["Inbox"].exists)
        guard let settingsTab = waitForHittableTab("Settings", in: app, timeout: 10) else {
            XCTFail("Settings tab did not become hittable.\n\(app.debugDescription)")
            return
        }
        settingsTab.tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "MuseFleet simulator Settings"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private func waitForHittableTab(_ label: String, in app: XCUIApplication,
                               timeout: TimeInterval) -> XCUIElement? {
    let tabs = app.tabBars.buttons.matching(NSPredicate(format: "label == %@", label))
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        let hittable = tabs.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        if hittable.count == 1 { return hittable[0] }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    } while Date() < deadline
    return nil
}
