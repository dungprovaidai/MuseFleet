import WebKit
import XCTest
@testable import MuseFleet

final class BrowserObserverFixtureTests: XCTestCase {
    private let adapter = BrowserObserverAdapter(id: "local-fixture-v1", origin: "https://musefleet-fixture.invalid",
        containerSelector: "[data-fixture-conversation]", itemSelector: "[data-fixture-id]",
        idAttribute: "data-fixture-id", stateAttribute: "data-fixture-state",
        streamingValue: "streaming", completedValue: "complete")

    @MainActor
    func testHistoricalInitialMessagesAreBaselinedAndStreamingCompletionEmitsOnce() async throws {
        let id = UUID()
        let page = FixturePage(accountID: id, receivesObserverMessages: true)
        defer { page.close() }
        try await page.loadHTML(BrowserFixture.html("observer"), baseURL: URL(string: adapter.origin + "/conversation")!)
        let ready = page.expectMessage("ready", test: self)
        try await page.evaluate(adapter.source(engine: BrowserFixture.observerSource()), isolated: true)
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(page.messages.filter { $0.kind == "completed" }.count, 0)
        for token in 1...5 {
            try await page.evaluate("document.querySelector('[data-fixture-id=baseline-stream]').textContent = 'token \(token)';")
        }
        try await page.evaluate("""
            const oldItem = document.createElement('article');
            oldItem.setAttribute('data-fixture-id', 'lazy-history');
            oldItem.setAttribute('data-fixture-state', 'complete');
            document.querySelector('[data-fixture-conversation]').append(oldItem);
            """)
        try await page.evaluate("0;", isolated: true)
        // A text mutation is not an explicit terminal state, even if an arbitrary amount of time passes.
        XCTAssertEqual(page.messages.filter { $0.kind == "completed" }.count, 0)
        let completion = page.expectMessage("completed", test: self)
        try await page.evaluate("document.querySelector('[data-fixture-id=baseline-stream]').setAttribute('data-fixture-state', 'complete');")
        await fulfillment(of: [completion], timeout: 5)
        XCTAssertEqual(page.messages.filter { $0.kind == "completed" }.map(\.itemID), ["baseline-stream"])
        XCTAssertEqual(page.messages.first { $0.kind == "completed" }?.conversationURL, adapter.origin + "/conversation")
        try await page.evaluate("""
            const item = document.querySelector('[data-fixture-id=baseline-stream]');
            item.textContent = 'edited result';
            item.setAttribute('data-fixture-state', 'streaming');
            item.setAttribute('data-fixture-state', 'complete');
            """)
        try await page.evaluate("0;", isolated: true)
        XCTAssertEqual(page.messages.filter { $0.kind == "completed" }.count, 1)
        page.close()
        try await WKWebsiteDataStore.remove(forIdentifier: id)
    }

    @MainActor
    func testNewStreamNeverEmitsForTokensAndReinstalledObserverDoesNotReplayHistory() async throws {
        let id = UUID()
        let page = FixturePage(accountID: id, receivesObserverMessages: true)
        defer { page.close() }
        try await page.loadHTML(BrowserFixture.html("observer"), baseURL: URL(string: adapter.origin + "/conversation?fixture=1")!)
        let source = try adapter.source(engine: BrowserFixture.observerSource())
        let ready = page.expectMessage("ready", test: self)
        try await page.evaluate(source, isolated: true)
        await fulfillment(of: [ready], timeout: 5)
        try await page.evaluate("""
            const item = document.createElement('article');
            item.setAttribute('data-fixture-id', 'new-stream');
            item.setAttribute('data-fixture-state', 'streaming');
            document.querySelector('[data-fixture-conversation]').append(item);
            """)
        for token in 1...8 { try await page.evaluate("document.querySelector('[data-fixture-id=new-stream]').textContent = 'piece \(token)';") }
        XCTAssertTrue(page.messages.allSatisfy { $0.kind != "completed" })
        let completion = page.expectMessage("completed", test: self)
        try await page.evaluate("document.querySelector('[data-fixture-id=new-stream]').setAttribute('data-fixture-state', 'complete');")
        await fulfillment(of: [completion], timeout: 5)
        XCTAssertEqual(page.messages.last?.conversationURL, adapter.origin + "/conversation")
        try await page.evaluate("globalThis.MuseFleetObserver.stop(); void 0;", isolated: true)
        try await page.evaluate("document.querySelector('[data-fixture-id=baseline-stream]').setAttribute('data-fixture-state', 'complete');")
        let resumed = page.expectMessage("ready", test: self)
        try await page.evaluate(source, isolated: true)
        await fulfillment(of: [resumed], timeout: 5)
        XCTAssertEqual(page.messages.filter { $0.kind == "completed" }.count, 1)
        XCTAssertNil(BrowserObserverAdapter.muse, "The synthetic adapter cannot enable production Muse detection.")
        page.close()
        try await WKWebsiteDataStore.remove(forIdentifier: id)
    }

    @MainActor
    func testPageWorldCannotAccessIsolatedNativeHandler() async throws {
        let id = UUID()
        let page = FixturePage(accountID: id, receivesObserverMessages: true)
        defer { page.close() }
        try await page.loadHTML(BrowserFixture.html("observer"), baseURL: URL(string: adapter.origin + "/conversation")!)
        let visible = try await page.evaluate("Boolean(globalThis.webkit?.messageHandlers?.museFleetObserver)") as? Bool
        XCTAssertEqual(visible, false)
        page.close()
        try await WKWebsiteDataStore.remove(forIdentifier: id)
    }

    @MainActor
    func testFixtureCompletionCanBeRecordedForItsAccountAndDeduplicated() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FleetStore(directory: directory)
        let account = AccountProfile(name: "Synthetic notification fixture")
        store.addAccount(account)
        let coordinator = NotificationCoordinator(store: store)
        let page = FixturePage(accountID: account.id, receivesObserverMessages: true)
        defer { page.close() }
        try await page.loadHTML(BrowserFixture.html("observer"), baseURL: URL(string: adapter.origin + "/conversation")!)
        let ready = page.expectMessage("ready", test: self)
        try await page.evaluate(adapter.source(engine: BrowserFixture.observerSource()), isolated: true)
        await fulfillment(of: [ready], timeout: 5)
        let completion = page.expectMessage("completed", test: self)
        try await page.evaluate("document.querySelector('[data-fixture-id=baseline-stream]').setAttribute('data-fixture-state', 'complete');")
        await fulfillment(of: [completion], timeout: 5)
        let payload = try XCTUnwrap(page.messages.first { $0.kind == "completed" })
        // Test-only delivery exercises recording/deduplication, not iOS permission or notification delivery.
        // The fixture's .invalid URL is intentionally rejected by the production Muse URL policy.
        let url = try XCTUnwrap(payload.conversationURL.flatMap(URL.init(string:)))
        let eventID = adapter.eventID(itemID: try XCTUnwrap(payload.itemID), conversationURL: url)
        for _ in 0..<2 {
            coordinator.receive(accountID: account.id, type: .completed, preview: nil, conversationURL: url, eventID: eventID)
        }
        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.events.first?.accountID, account.id)
        XCTAssertEqual(store.events.first?.source, .foregroundWeb)
        XCTAssertNil(store.events.first?.preview)
        XCTAssertNil(store.events.first?.conversationURL)
        XCTAssertNotEqual(eventID, adapter.eventID(itemID: payload.itemID!,
            conversationURL: URL(string: adapter.origin + "/another-conversation")!))
        page.close()
        try await WKWebsiteDataStore.remove(forIdentifier: account.id)
    }
}
