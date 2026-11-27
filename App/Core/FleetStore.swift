import Foundation
import Observation
import OSLog

@MainActor @Observable
final class FleetStore {
    private(set) var accounts: [AccountProfile] = []
    private(set) var events: [FleetEvent] = []
    var settings = AppSettings()
    private(set) var storageError: String?
    private(set) var persistenceUnavailable = false
    @ObservationIgnored private var seenEventIDs: Set<String> = []
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let logger = Logger(subsystem: "com.dungprovaidai.musefleet", category: "Storage")

    private struct Snapshot: Codable {
        var version = 1
        var accounts: [AccountProfile]
        var events: [FleetEvent]
        var settings: AppSettings
        var seenEventIDs: Set<String>
    }

    init(directory: URL? = nil) {
        let base = directory ?? URL.applicationSupportDirectory.appendingPathComponent("MuseFleet", isDirectory: true)
        fileURL = base.appendingPathComponent("fleet.json")
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            var resource = base
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try resource.setResourceValues(values)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
            guard snapshot.version == 1,
                  Set(snapshot.accounts.map(\.id)).count == snapshot.accounts.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            accounts = snapshot.accounts.map { account in
                var safe = account
                safe.lastURL = URLPolicy.safeConversation(account.lastURL)
                return safe
            }
            events = snapshot.events.map { event in
                var safe = event
                safe.conversationURL = URLPolicy.safeConversation(event.conversationURL)
                return safe
            }
            settings = snapshot.settings
            seenEventIDs = snapshot.seenEventIDs.union(events.map(\.id))
        } catch {
            persistenceUnavailable = true
            storageError = "Saved data could not be opened. It has been preserved. Restart after unlocking your device; do not delete the app to recover it."
            logger.error("Metadata open failed; existing file preserved.")
        }
    }

    @discardableResult func save() -> Bool {
        guard !persistenceUnavailable else { return false }
        do {
            let snapshot = Snapshot(accounts: accounts, events: events, settings: settings, seenEventIDs: seenEventIDs)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            storageError = nil
            return true
        } catch {
            storageError = "Changes could not be saved. Free device storage and try again. Existing saved data has been preserved."
            logger.error("Metadata save failed.")
            return false
        }
    }

    func addAccount(_ account: AccountProfile) {
        guard !persistenceUnavailable, self.account(id: account.id) == nil else { return }
        var account = account
        account.name = String(account.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !account.name.isEmpty else { return }
        account.sortOrder = accounts.count
        account.lastURL = URLPolicy.safeConversation(account.lastURL)
        accounts.append(account)
        save()
    }

    func updateAccount(_ account: AccountProfile) {
        guard !persistenceUnavailable, let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        var account = account
        account.name = String(account.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !account.name.isEmpty else { return }
        account.lastURL = URLPolicy.safeConversation(account.lastURL)
        accounts[index] = account
        save()
    }

    func deleteAccountMetadata(id: UUID) {
        guard !persistenceUnavailable else { return }
        accounts.removeAll { $0.id == id }
        events.removeAll { $0.accountID == id }
        save()
    }

    @discardableResult func record(_ event: FleetEvent) -> Bool {
        guard !persistenceUnavailable, account(id: event.accountID) != nil,
              !event.id.isEmpty, event.id.utf8.count <= 512,
              !seenEventIDs.contains(event.id) else { return false }
        var event = event
        event.preview = event.preview.map { String($0.prefix(400)) }
        event.conversationURL = URLPolicy.safeConversation(event.conversationURL)
        seenEventIDs.insert(event.id)
        events.insert(event, at: 0)
        guard save() else {
            events.removeAll { $0.id == event.id }
            seenEventIDs.remove(event.id)
            return false
        }
        return true
    }

    func markRead(_ eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }), !persistenceUnavailable else { return }
        events[index].isRead = true
        save()
    }

    func markRead(_ event: FleetEvent) { markRead(event.id) }

    func markAllRead() {
        guard !persistenceUnavailable else { return }
        for index in events.indices { events[index].isRead = true }
        save()
    }

    func deleteEvent(_ event: FleetEvent) {
        guard !persistenceUnavailable else { return }
        events.removeAll { $0.id == event.id }
        save()
    }

    func account(id: UUID) -> AccountProfile? { accounts.first { $0.id == id } }

    func unreadCount(accountID: UUID? = nil) -> Int {
        events.filter { !$0.isRead && (accountID == nil || $0.accountID == accountID) }.count
    }
}
