import WebKit
import XCTest
@testable import MuseFleet

final class BrowserPoolTests: XCTestCase {
    @MainActor
    func testLRUEvictsPagesAtThreeSessionsAndPreservesNamedStores() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FleetStore(directory: directory)
        let notifications = NotificationCoordinator(store: store)
        let pool = BrowserPool(store: store, notifications: notifications)
        pool.suspendAll()
        let accounts = (0..<4).map { AccountProfile(name: "Fixture \($0)") }
        accounts.forEach { store.addAccount($0) }
        let first = pool.session(for: accounts[0])
        let second = pool.session(for: accounts[1])
        let third = pool.session(for: accounts[2])
        XCTAssertTrue(first.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(first.webView.configuration.websiteDataStore.identifier, accounts[0].id)
        XCTAssertTrue(pool.session(for: accounts[1]) === second)
        let fourth = pool.session(for: accounts[3])
        XCTAssertFalse(first.isAvailable)
        XCTAssertTrue(second.isAvailable)
        XCTAssertTrue(third.isAvailable)
        XCTAssertTrue(fourth.isAvailable)
        let identifiers = await WKWebsiteDataStore.allDataStoreIdentifiers
        XCTAssertTrue(identifiers.contains(accounts[0].id), "LRU eviction must preserve website data.")
        pool.keepOnly(accountID: accounts[1].id)
        XCTAssertTrue(second.isAvailable)
        XCTAssertFalse(third.isAvailable)
        XCTAssertFalse(fourth.isAvailable)
        XCTAssertEqual(second.observerStatus, .suspended)
        XCTAssertNil(second.lastCheckedAt)
        let provider: any NotificationProvider = second
        XCTAssertEqual(provider.source, .foregroundWeb)
        XCTAssertEqual(provider.capability.level, .blocked)
        pool.keepOnly(accountID: nil)
        for account in accounts { try await WebsiteDataStoreRemoval.remove(forIdentifier: account.id) }
    }

    @MainActor
    func testDeletionBlocksRecreationAndFailurePreservesAccountMetadata() async throws {
        enum FixtureFailure: Error { case denied }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FleetStore(directory: directory)
        var account = AccountProfile(name: "Deletion fixture")
        account.lastURL = URL(string: "https://muse.ai/fixture")
        account.lastVisitedAt = Date(timeIntervalSince1970: 123)
        store.addAccount(account)
        let started = expectation(description: "Removal has begun")
        var continuation: CheckedContinuation<Void, Error>?
        let pool = BrowserPool(store: store, notifications: NotificationCoordinator(store: store)) { id in
            XCTAssertEqual(id, account.id)
            try await withCheckedThrowingContinuation { value in
                continuation = value
                started.fulfill()
            }
        }
        pool.suspendAll()
        let original = pool.session(for: account)
        let removal = Task { try await pool.clearWebsiteData(accountID: account.id) }
        await fulfillment(of: [started], timeout: 5)
        XCTAssertFalse(original.isAvailable)
        XCTAssertTrue(pool.isClearingWebsiteData(accountID: account.id))
        let blocked = pool.session(for: account)
        XCTAssertFalse(blocked.isAvailable)
        XCTAssertNil(blocked.availableWebView)
        do {
            try await pool.clearWebsiteData(accountID: account.id)
            XCTFail("Concurrent removal must be rejected")
        } catch BrowserDataError.alreadyClearing { }
        continuation?.resume(throwing: FixtureFailure.denied)
        do { try await removal.value; XCTFail("Expected a removal failure") } catch FixtureFailure.denied { }
        XCTAssertEqual(store.account(id: account.id), account)
        XCTAssertFalse(pool.isClearingWebsiteData(accountID: account.id))
        XCTAssertTrue(blocked.isAvailable)
        pool.keepOnly(accountID: nil)
        try await WebsiteDataStoreRemoval.remove(forIdentifier: account.id)
    }

    @MainActor
    func testSuccessfulPoolDeletionRemovesOnlyVisitMetadataAndWebsiteStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FleetStore(directory: directory)
        var account = AccountProfile(name: "Success fixture")
        account.notes = "Keep local profile notes"
        account.lastURL = URL(string: "https://muse.ai/fixture")
        account.lastVisitedAt = Date(timeIntervalSince1970: 123)
        store.addAccount(account)
        let pool = BrowserPool(store: store, notifications: NotificationCoordinator(store: store))
        pool.suspendAll()
        let session = pool.session(for: account)
        try await pool.clearWebsiteData(accountID: account.id)
        XCTAssertFalse(session.isAvailable)
        let saved = try XCTUnwrap(store.account(id: account.id))
        XCTAssertEqual(saved.name, account.name)
        XCTAssertEqual(saved.notes, account.notes)
        XCTAssertNil(saved.lastURL)
        XCTAssertNil(saved.lastVisitedAt)
        let identifiers = await WKWebsiteDataStore.allDataStoreIdentifiers
        XCTAssertFalse(identifiers.contains(account.id))
    }

    @MainActor
    func testWebsiteStoreRemovalRetriesOnlyTheInUseError() async throws {
        let id = UUID()
        var attempts = 0
        try await WebsiteDataStoreRemoval.remove(forIdentifier: id) { receivedID in
            XCTAssertEqual(receivedID, id)
            attempts += 1
            if attempts == 1 {
                throw NSError(domain: "WKWebSiteDataStore", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Data store is in use"])
            }
        }
        XCTAssertEqual(attempts, 2)
    }
}
