import XCTest
@testable import MuseFleet

@MainActor
final class FleetStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
    }

    func testIndependentProfilesSurviveRestartAndDeletingOnePreservesTheOther() {
        let store = FleetStore(directory: directory)
        let first = AccountProfile(name: "A")
        let second = AccountProfile(name: "B", lastURL: URL(string: "https://muse.ai/conversation/b"))
        store.addAccount(first)
        store.addAccount(second)
        XCTAssertNotEqual(first.id, second.id)
        store.deleteAccountMetadata(id: first.id)
        let restored = FleetStore(directory: directory)
        XCTAssertNil(restored.account(id: first.id))
        XCTAssertEqual(restored.account(id: second.id)?.lastURL, second.lastURL)
        XCTAssertEqual(restored.accounts.count, 1)
    }

    func testDuplicateEventStaysSuppressedAfterDeletionAndRestart() {
        let store = FleetStore(directory: directory)
        let account = AccountProfile(name: "A")
        store.addAccount(account)
        let event = fixtureEvent(account)
        XCTAssertTrue(store.record(event))
        XCTAssertFalse(store.record(event))
        XCTAssertEqual(store.unreadCount(), 1)
        store.deleteEvent(event)
        XCTAssertEqual(store.unreadCount(), 0)
        let restored = FleetStore(directory: directory)
        XCTAssertFalse(restored.record(event))
        XCTAssertTrue(restored.events.isEmpty)
    }

    func testReadStateAndAccountDeletionDoNotChangeOtherAccountEvents() {
        let store = FleetStore(directory: directory)
        let a = AccountProfile(name: "A")
        let b = AccountProfile(name: "B")
        store.addAccount(a)
        store.addAccount(b)
        let eventA = fixtureEvent(a)
        let eventB = fixtureEvent(b)
        XCTAssertTrue(store.record(eventA))
        XCTAssertTrue(store.record(eventB))
        store.markRead(eventA.id)
        XCTAssertEqual(store.unreadCount(accountID: a.id), 0)
        XCTAssertEqual(store.unreadCount(accountID: b.id), 1)
        store.deleteAccountMetadata(id: a.id)
        XCTAssertEqual(store.events.map(\.id), [eventB.id])
    }

    func testCorruptMetadataIsPreservedAndCannotBeOverwritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("fleet.json")
        let bytes = Data("corrupted snapshot".utf8)
        try bytes.write(to: file)
        let store = FleetStore(directory: directory)
        XCTAssertTrue(store.persistenceUnavailable)
        XCTAssertNotNil(store.storageError)
        store.addAccount(AccountProfile(name: "Cannot overwrite"))
        XCTAssertFalse(store.save())
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testAuthenticationCallbackIsNotPersisted() {
        let store = FleetStore(directory: directory)
        let account = AccountProfile(name: "A", lastURL: URL(string: "https://muse.ai/callback?code=private"))
        store.addAccount(account)
        XCTAssertNil(FleetStore(directory: directory).accounts.first?.lastURL)
    }

    func testEventSaveFailureDoesNotConsumeIDOrProduceFalseDeliverySuccess() throws {
        let store = FleetStore(directory: directory)
        let account = AccountProfile(name: "A")
        store.addAccount(account)
        let file = directory.appendingPathComponent("fleet.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        let event = fixtureEvent(account)
        XCTAssertFalse(store.record(event))
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertNotNil(store.storageError)
        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(store.record(event))
        XCTAssertEqual(store.events.count, 1)
    }

    private func fixtureEvent(_ account: AccountProfile) -> FleetEvent {
        FleetEvent(id: account.id.uuidString + ":fixture", accountID: account.id, accountName: account.name,
                   accountSymbol: account.symbol, accountColorHex: account.colorHex, type: .response)
    }
}
