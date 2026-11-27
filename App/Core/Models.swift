import Foundation

struct AccountProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "sparkles"
    var colorHex: String = "7568FA"
    var role: String = ""
    var notes: String = ""
    var project: String = ""
    var tags: [String] = []
    var group: String = ""
    var isFavorite: Bool = false
    var sortOrder: Int = 0
    var lastURL: URL?
    var lastVisitedAt: Date?
    var notificationsEnabled: Bool = true
    var avatarData: Data?
}

enum EventKind: String, Codable, CaseIterable, Identifiable {
    case response, completed, failed, attention, approval, question, artifact, progress, sessionExpired
    var id: String { rawValue }
    var title: String {
        switch self {
        case .response: "New response"
        case .completed: "Task completed"
        case .failed: "Task failed"
        case .attention: "Needs attention"
        case .approval: "Approval required"
        case .question: "Question"
        case .artifact: "Artifact ready"
        case .progress: "Progress update"
        case .sessionExpired: "Session expired"
        }
    }
    var symbol: String {
        switch self {
        case .response: "bubble.left.and.bubble.right"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.octagon"
        case .attention: "exclamationmark.bubble"
        case .approval: "hand.raised"
        case .question: "questionmark.bubble"
        case .artifact: "doc.badge.arrow.up"
        case .progress: "chart.line.uptrend.xyaxis"
        case .sessionExpired: "lock.trianglebadge.exclamationmark"
        }
    }
    var needsAttention: Bool { [.failed, .attention, .approval, .question, .sessionExpired].contains(self) }
}

enum NotificationSource: String, Codable, CaseIterable {
    case foregroundWeb, official, backgroundRefresh, externalChannel, remotePush
    var title: String {
        switch self {
        case .foregroundWeb: "Foreground web observer"
        case .official: "Official Muse integration"
        case .backgroundRefresh: "Background refresh"
        case .externalChannel: "External channel"
        case .remotePush: "Native remote push"
        }
    }
}

struct FleetEvent: Codable, Identifiable, Equatable {
    var id: String
    var accountID: UUID
    var accountName: String
    var accountSymbol: String
    var accountColorHex: String
    var type: EventKind
    var timestamp: Date = Date()
    var preview: String?
    var conversationURL: URL?
    var isRead: Bool = false
    var source: NotificationSource = .foregroundWeb
}

struct AppSettings: Codable, Equatable {
    var appLockEnabled = false
    var appearance = "system"
    var soundEnabled = true
    var hapticsEnabled = true
    var hideNotificationPreviews = true
    var quietHoursEnabled = false
    var quietStartHour = 22
    var quietEndHour = 8
}

struct NotificationRoute: Equatable {
    var accountID: UUID
    var url: URL?
    var eventID: String

    static func parse(_ userInfo: [AnyHashable: Any]) -> Self? {
        guard let value = userInfo["accountID"] as? String,
              let accountID = UUID(uuidString: value),
              let eventID = userInfo["eventID"] as? String,
              !eventID.isEmpty, eventID.utf8.count <= 512 else { return nil }
        let candidate = (userInfo["conversationURL"] as? String).flatMap(URL.init(string:))
        return Self(accountID: accountID, url: URLPolicy.safeConversation(candidate), eventID: eventID)
    }
}

enum QuietHours {
    static func contains(_ date: Date, settings: AppSettings, calendar: Calendar = .current) -> Bool {
        guard settings.quietHoursEnabled else { return false }
        let start = min(23, max(0, settings.quietStartHour))
        let end = min(23, max(0, settings.quietEndHour))
        let hour = calendar.component(.hour, from: date)
        if start == end { return true }
        return start < end ? (start..<end).contains(hour) : hour >= start || hour < end
    }
}
