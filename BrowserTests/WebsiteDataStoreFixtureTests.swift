import WebKit
import XCTest
@testable import MuseFleet

final class WebsiteDataStoreFixtureTests: XCTestCase {
    @MainActor
    func testTwoNamedStoresIsolatePersistAndDeleteLocalFixtureData() async throws {
        let server = try LocalFixtureServer(html: BrowserFixture.html("storage"))
        let url = try await server.start()
        defer { server.stop() }
        let firstID = UUID()
        let secondID = UUID()
        let first = FixturePage(accountID: firstID)
        let second = FixturePage(accountID: secondID)
        defer { first.close(); second.close() }
        try await first.load(URLRequest(url: url))
        try await second.load(URLRequest(url: url))
        XCTAssertEqual(first.webView?.configuration.websiteDataStore.identifier, firstID)
        XCTAssertEqual(second.webView?.configuration.websiteDataStore.identifier, secondID)
        // These are synthetic sentinels, never an account's actual authentication data.
        try await first.evaluate("localStorage.setItem('fixture', 'first'); document.cookie = 'fixture=first; Max-Age=3600; Path=/; SameSite=Lax';")
        let initiallyEmpty = try await second.evaluate("localStorage.getItem('fixture') === null && document.cookie === ''") as? Bool
        XCTAssertEqual(initiallyEmpty, true)
        try await second.evaluate("localStorage.setItem('fixture', 'second'); document.cookie = 'fixture=second; Max-Age=3600; Path=/; SameSite=Lax';")
        let firstStillIsolated = try await first.evaluate("localStorage.getItem('fixture') === 'first' && document.cookie === 'fixture=first'") as? Bool
        XCTAssertEqual(firstStillIsolated, true)
        // Wait for WebKit's data-record API to complete before releasing the original views.
        _ = await first.webView?.configuration.websiteDataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        _ = await second.webView?.configuration.websiteDataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        first.close()
        second.close()
        let reopenedFirst = FixturePage(accountID: firstID)
        let reopenedSecond = FixturePage(accountID: secondID)
        defer { reopenedFirst.close(); reopenedSecond.close() }
        try await reopenedFirst.load(URLRequest(url: url))
        try await reopenedSecond.load(URLRequest(url: url))
        let persistedFirst = try await reopenedFirst.evaluate("localStorage.getItem('fixture') === 'first' && document.cookie === 'fixture=first'") as? Bool
        let persistedSecond = try await reopenedSecond.evaluate("localStorage.getItem('fixture') === 'second' && document.cookie === 'fixture=second'") as? Bool
        XCTAssertEqual(persistedFirst, true)
        XCTAssertEqual(persistedSecond, true)
        reopenedFirst.close()
        try await WKWebsiteDataStore.remove(forIdentifier: firstID)
        let identifiersAfterDeletion = await WKWebsiteDataStore.allDataStoreIdentifiers
        XCTAssertFalse(identifiersAfterDeletion.contains(firstID))
        XCTAssertTrue(identifiersAfterDeletion.contains(secondID))
        let freshFirst = FixturePage(accountID: firstID)
        defer { freshFirst.close() }
        try await freshFirst.load(URLRequest(url: url))
        let removed = try await freshFirst.evaluate("localStorage.getItem('fixture') === null && document.cookie === ''") as? Bool
        let untouched = try await reopenedSecond.evaluate("localStorage.getItem('fixture') === 'second' && document.cookie === 'fixture=second'") as? Bool
        XCTAssertEqual(removed, true)
        XCTAssertEqual(untouched, true)
        freshFirst.close()
        reopenedSecond.close()
        try await WKWebsiteDataStore.remove(forIdentifier: firstID)
        try await WKWebsiteDataStore.remove(forIdentifier: secondID)
    }
}
