import Foundation

enum CapabilityLevel: String, Codable { case verified = "VERIFIED", documented = "DOCUMENTED", unverified = "UNVERIFIED", unsupported = "UNSUPPORTED", blocked = "BLOCKED" }

struct NotificationCapability: Identifiable {
    var id: NotificationSource { source }
    var source: NotificationSource
    var level: CapabilityLevel
    var detail: String
}

@MainActor
protocol NotificationProvider: AnyObject {
    var source: NotificationSource { get }
    var capability: NotificationCapability { get }
    var lastCheckedAt: Date? { get }
    func start()
    func stop()
}

enum NotificationCapabilities {
    static let all: [NotificationCapability] = [
        .init(source: .foregroundWeb, level: .blocked, detail: "Detection unavailable: Muse's authenticated message markup has not been verified. Only loaded accounts can ever be observed while this app is active."),
        .init(source: .official, level: .unverified, detail: "No official Muse event integration has been connected or verified."),
        .init(source: .backgroundRefresh, level: .unsupported, detail: "No authorized background data source. iOS does not keep web views running continuously."),
        .init(source: .externalChannel, level: .unverified, detail: "An external channel needs official Muse support and explicit setup. Messages in other apps are not MuseFleet native notifications."),
        .init(source: .remotePush, level: .blocked, detail: "Requires a verified event source, consented relay, APNs credentials and a compatible signed app. Nothing is deployed.")
    ]
}
