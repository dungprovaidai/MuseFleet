import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor @Observable
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var pendingRoute: NotificationRoute?
    var deliveryError: String?
    @ObservationIgnored private let store: FleetStore
    @ObservationIgnored private let center: UNUserNotificationCenter

    init(store: FleetStore, center: UNUserNotificationCenter = .current()) {
        self.store = store
        self.center = center
        super.init()
        center.delegate = self
    }

    func refreshAuthorization() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            deliveryError = nil
        } catch {
            deliveryError = "Notification permission could not be requested. Check iOS Settings."
        }
        await refreshAuthorization()
        syncBadge()
    }

    func receive(accountID: UUID, type: EventKind, preview: String?, conversationURL: URL?, eventID: String) {
        guard let account = store.account(id: accountID), !eventID.isEmpty,
              eventID.utf8.count <= 400 else { return }
        let id = accountID.uuidString + ":" + eventID
        let hidesPreview = store.settings.hideNotificationPreviews
        // The default privacy policy also avoids persisting message text in the inbox.
        let safePreview = hidesPreview ? nil : preview.map { String($0.prefix(400)) }
        let event = FleetEvent(id: id, accountID: accountID, accountName: account.name,
                               accountSymbol: account.symbol, accountColorHex: account.colorHex,
                               type: type, preview: safePreview,
                               conversationURL: URLPolicy.safeConversation(conversationURL))
        guard store.record(event) else { return }
        syncBadge()
        guard account.notificationsEnabled, !QuietHours.contains(Date(), settings: store.settings),
              [.authorized, .provisional, .ephemeral].contains(authorizationStatus) else { return }

        let content = UNMutableNotificationContent()
        content.title = hidesPreview ? "MuseFleet" : account.name
        content.body = hidesPreview ? "An account has an update. Open MuseFleet to view it." : (safePreview ?? type.title)
        content.threadIdentifier = accountID.uuidString
        content.categoryIdentifier = "MUSE_EVENT"
        content.badge = NSNumber(value: store.unreadCount())
        if store.settings.soundEnabled { content.sound = .default }
        content.userInfo = ["accountID": accountID.uuidString, "eventID": id]
        if let url = event.conversationURL { content.userInfo["conversationURL"] = url.absoluteString }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        Task {
            do {
                try await center.add(request)
                if self.store.account(id: accountID)?.notificationsEnabled != true ||
                    (self.store.settings.hideNotificationPreviews && !hidesPreview) {
                    self.center.removePendingNotificationRequests(withIdentifiers: [id])
                    self.center.removeDeliveredNotifications(withIdentifiers: [id])
                }
                deliveryError = nil
            } catch {
                deliveryError = "An update was saved to Inbox, but iOS could not display its notification."
            }
        }
        if store.settings.hapticsEnabled, UIApplication.shared.applicationState == .active {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func syncBadge() {
        Task { try? await center.setBadgeCount(store.unreadCount()) }
    }

    func removeNotifications(accountID: UUID) {
        Task {
            let delivered = await center.deliveredNotifications()
            let ids = delivered.filter { ($0.request.content.userInfo["accountID"] as? String) == accountID.uuidString }.map { $0.request.identifier }
            center.removeDeliveredNotifications(withIdentifiers: ids)
            let pending = await center.pendingNotificationRequests()
            let pendingIDs = pending.filter { ($0.content.userInfo["accountID"] as? String) == accountID.uuidString }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
            syncBadge()
        }
    }

    func clearDelivered(eventID: String) {
        center.removeDeliveredNotifications(withIdentifiers: [eventID])
        syncBadge()
    }

    func applyPrivacySettings() {
        if store.settings.hideNotificationPreviews {
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                          didReceive response: UNNotificationResponse,
                                          withCompletionHandler completionHandler: @escaping () -> Void) {
        let route = NotificationRoute.parse(response.notification.request.content.userInfo)
        Task { @MainActor in
            if let route, self.store.account(id: route.accountID) != nil {
                self.pendingRoute = route
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                          willPresent notification: UNNotification,
                                          withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            let allowed = !QuietHours.contains(Date(), settings: self.store.settings)
            var options: UNNotificationPresentationOptions = [.badge]
            if allowed {
                options.formUnion([.banner, .list])
                if self.store.settings.soundEnabled { options.insert(.sound) }
            }
            completionHandler(options)
        }
    }
}
