import XCTest
import UserNotifications
@testable import MuseFleet

final class NotificationPolicyTests: XCTestCase {
    func testDeepLinkRejectsForeignOriginAndMalformedAccount() {
        let id = UUID()
        let route = NotificationRoute.parse(["accountID": id.uuidString, "eventID": "fixture", "conversationURL": "https://muse.ai.evil.example/conversation/1"])
        XCTAssertEqual(route?.accountID, id)
        XCTAssertNil(route?.url)
        XCTAssertNil(NotificationRoute.parse(["accountID": "not-a-uuid", "eventID": "fixture"]))
        XCTAssertNil(NotificationRoute.parse(["accountID": id.uuidString, "eventID": ""]))
        let valid = NotificationRoute.parse(["accountID": id.uuidString, "eventID": "fixture", "conversationURL": "https://muse.ai/conversation/1"])
        XCTAssertEqual(valid?.url?.host, "muse.ai")
    }

    func testURLBoundaryRejectsCredentialURLsAndUnsafeSchemes() {
        let rejected = ["http://muse.ai/", "https://muse.ai.evil.example/", "https://evil.example/?next=https://muse.ai",
                        "https://user:secret@muse.ai/", "file:///etc/passwd", "javascript:alert(1)",
                        "https://muse.ai:8443/", "https://muse.ai/callback?access_token=private", "https://muse.ai/#token=private"]
        for value in rejected {
            XCTAssertNil(URLPolicy.safeConversation(URL(string: value)), value)
        }
        XCTAssertNotNil(URLPolicy.safeConversation(URL(string: "https://muse.ai/conversation/123")))
    }

    func testQuietHoursWrapMidnightAndRespectEndBoundary() throws {
        var settings = AppSettings()
        settings.quietHoursEnabled = true
        settings.quietStartHour = 22
        settings.quietEndHour = 8
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for (hour, expected) in [(21, false), (22, true), (0, true), (7, true), (8, false)] {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 28, hour: hour)))
            XCTAssertEqual(QuietHours.contains(date, settings: settings, calendar: calendar), expected)
        }
        settings.quietEndHour = 22
        XCTAssertTrue(QuietHours.contains(Date(), settings: settings, calendar: calendar))
        settings.quietHoursEnabled = false
        XCTAssertFalse(QuietHours.contains(Date(), settings: settings, calendar: calendar))
    }
}

@MainActor
final class NotificationCoordinatorTests: XCTestCase {
    func testEnablingPrivacyBeforeQueuedSubmissionNeverSubmitsOldPreview() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FleetStore(directory: directory)
        let account = AccountProfile(name: "Private fixture")
        store.addAccount(account)
        store.settings.hideNotificationPreviews = false
        store.settings.hapticsEnabled = false
        let staleSubmission = expectation(description: "A stale private request is never submitted")
        staleSubmission.isInverted = true
        let coordinator = NotificationCoordinator(store: store, deliver: { _ in staleSubmission.fulfill() })
        coordinator.authorizationStatus = .authorized
        coordinator.receive(accountID: account.id, type: .response, preview: "Private test content",
                            conversationURL: nil, eventID: "privacy-race")
        // Change the setting synchronously before SwiftUI's onChange can invalidate tasks.
        store.settings.hideNotificationPreviews = true
        await fulfillment(of: [staleSubmission], timeout: 0.2)
        XCTAssertEqual(store.events.count, 1)
    }

    func testDeletingAccountBeforeQueuedSubmissionNeverSubmitsAlert() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FleetStore(directory: directory)
        let account = AccountProfile(name: "Deleted fixture")
        store.addAccount(account)
        store.settings.hapticsEnabled = false
        let staleSubmission = expectation(description: "A deleted account never submits an alert")
        staleSubmission.isInverted = true
        let coordinator = NotificationCoordinator(store: store, deliver: { _ in staleSubmission.fulfill() })
        coordinator.authorizationStatus = .authorized
        coordinator.receive(accountID: account.id, type: .response, preview: nil, conversationURL: nil, eventID: "deleted-race")
        store.deleteAccountMetadata(id: account.id)
        await fulfillment(of: [staleSubmission], timeout: 0.2)
        XCTAssertTrue(store.events.isEmpty)
    }

    func testDeniedPermissionStillRecordsOneEventAndHidesPreview() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FleetStore(directory: directory)
        let account = AccountProfile(name: "Fixture account")
        store.addAccount(account)
        let coordinator = NotificationCoordinator(store: store)
        coordinator.authorizationStatus = .denied
        for _ in 0..<2 {
            coordinator.receive(accountID: account.id, type: .response, preview: "Private fixture text",
                                conversationURL: URL(string: "https://attacker.example/"), eventID: "response-1")
        }
        XCTAssertEqual(store.events.count, 1)
        XCTAssertNil(store.events.first?.preview)
        XCTAssertNil(store.events.first?.conversationURL)
        XCTAssertEqual(store.unreadCount(accountID: account.id), 1)
        coordinator.receive(accountID: UUID(), type: .completed, preview: nil, conversationURL: nil, eventID: "unknown")
        XCTAssertEqual(store.events.count, 1)
    }

    func testLocalNotificationDeliveryProofOfConceptRequiresSystemPermission() async throws {
        // This fixture tests the iOS delivery API, not Muse detection or background monitoring.
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else {
            throw XCTSkip("Grant notifications on the test device to execute this local-delivery PoC. No Muse event source is implied.")
        }
        let identifier = "musefleet-local-poc-" + UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = "MuseFleet TEST ONLY"
        content.body = "Local delivery proof of concept. This is not a Muse response."
        try await center.add(UNNotificationRequest(identifier: identifier, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 30, repeats: false)))
        let pending = await center.pendingNotificationRequests()
        XCTAssertTrue(pending.contains { $0.identifier == identifier })
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
