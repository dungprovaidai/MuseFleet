import Observation
import UIKit
import WebKit

@MainActor @Observable
final class BrowserPool {
    private let store: FleetStore
    private let notifications: NotificationCoordinator
    @ObservationIgnored private let removeWebsiteData: @MainActor (UUID) async throws -> Void
    private var sessions: [UUID: BrowserSession] = [:]
    private var recency: [UUID] = []
    private var suspended = false
    private var clearing: Set<UUID> = []
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol?

    init(store: FleetStore, notifications: NotificationCoordinator,
         removeWebsiteData: @escaping @MainActor (UUID) async throws -> Void = { try await WebsiteDataStoreRemoval.remove(forIdentifier: $0) }) {
        self.store = store
        self.notifications = notifications
        self.removeWebsiteData = removeWebsiteData
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.keepOnly(accountID: self?.recency.last) }
        }
    }

    deinit {
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
    }

    func session(for account: AccountProfile) -> BrowserSession {
        recency.removeAll { $0 == account.id }
        recency.append(account.id)
        if let session = sessions[account.id] { return session }
        while sessions.count >= 3, let oldest = recency.first(where: { sessions[$0] != nil }) {
            remove(accountID: oldest)
        }
        let session = BrowserSession(account: account, store: store, notifications: notifications,
                                     suspended: suspended, clearingWebsiteData: clearing.contains(account.id))
        sessions[account.id] = session
        return session
    }

    // Eviction removes loaded pages, never the persistent per-account website store.
    func remove(accountID: UUID) {
        autoreleasepool { sessions.removeValue(forKey: accountID)?.dispose() }
        recency.removeAll { $0 == accountID }
    }

    func clearWebsiteData(accountID: UUID) async throws {
        guard clearing.insert(accountID).inserted else { throw BrowserDataError.alreadyClearing }
        remove(accountID: accountID)
        defer {
            clearing.remove(accountID)
            sessions[accountID]?.finishClearingWebsiteData(suspended: suspended)
        }
        // No replacement session constructs a WebView until this operation finishes.
        try await removeWebsiteData(accountID)
        if var account = store.account(id: accountID) {
            account.lastURL = nil
            account.lastVisitedAt = nil
            store.updateAccount(account)
        }
    }

    func isClearingWebsiteData(accountID: UUID) -> Bool { clearing.contains(accountID) }

    func suspendAll() {
        suspended = true
        for session in sessions.values { session.suspend() }
    }

    func resumeAll() {
        suspended = false
        for (id, session) in sessions where !clearing.contains(id) { session.resume() }
    }

    func keepOnly(accountID: UUID?) {
        for id in Array(sessions.keys) where id != accountID { remove(accountID: id) }
    }
}

enum BrowserDataError: LocalizedError {
    case alreadyClearing

    var errorDescription: String? { "Website data for this account is already being cleared." }
}

@MainActor
enum WebsiteDataStoreRemoval {
    static func remove(forIdentifier id: UUID) async throws {
        await clearData(forIdentifier: id)
        try await removeStore(forIdentifier: id)
    }

    private static func clearData(forIdentifier id: UUID) async {
        let store = WKWebsiteDataStore(forIdentifier: id)
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    static func removeStore(forIdentifier id: UUID,
                            operation: @MainActor (UUID) async throws -> Void = {
                                try await WKWebsiteDataStore.remove(forIdentifier: $0)
                            }) async throws {
        for delay in [100, 250, 500, 1_000] {
            do {
                try await operation(id)
                return
            } catch {
                let failure = error as NSError
                guard failure.domain == "WKWebSiteDataStore", failure.code == 1 else { throw error }
                try await Task.sleep(for: .milliseconds(Int64(delay)))
            }
        }
        try await operation(id)
    }
}
