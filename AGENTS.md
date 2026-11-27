# MuseFleet engineering contract

Native iOS 17+ SwiftUI application; no runtime third-party dependencies. Never collect Muse passwords, OTPs, cookies or tokens. Each account must use `WKWebsiteDataStore(forIdentifier: account.id)`. Never use the default data store or copy cookies between accounts. Use the official HTTPS Muse website; no private APIs or authentication bypass.

## Collaboration

Work in the assigned branch/worktree. Do not edit another agent's files. Commit your work and report the commit hash, checks actually performed and unresolved issues. Read applicable skill instructions before use. Windows has no Xcode; never report an Apple build or device test as passed without execution evidence.

## Shared interfaces

- `AccountProfile`: Codable, Identifiable value type. `id: UUID`, `name: String`, `symbol: String`, `colorHex: String`, `role: String`, `notes: String`, `project: String`, `tags: [String]`, `group: String`, `isFavorite: Bool`, `sortOrder: Int`, `lastURL: URL?`, `lastVisitedAt: Date?`, `notificationsEnabled: Bool`, `avatarData: Data?`.
- `FleetEvent`: Codable, Identifiable value type. `id: String`, `accountID: UUID`, `type: EventKind`, `timestamp: Date`, `preview: String?`, `conversationURL: URL?`, `isRead: Bool`, `source: NotificationSource`. Snapshot account name/symbol/color at creation.
- `@MainActor @Observable final class FleetStore`: persisted `accounts`, `events`, `settings`; `save()`, `addAccount(_:)`, `updateAccount(_:)`, `deleteAccountMetadata(id:)`, `record(_:) -> Bool`, `markRead(_:)`, `markAllRead()`, `deleteEvent(_:)`, `account(id:)`, `unreadCount(accountID: UUID? = nil)`.
- `URLPolicy`: `static let home: URL`, `static func isMuse(_ url: URL) -> Bool`, `static func safeConversation(_ url: URL?) -> URL?`, `static func isSafeExternal(_ url: URL) -> Bool`. Exact verified host allowlist, HTTPS only, no credentials or nonstandard port.
- Browser API: `@MainActor @Observable final class BrowserPool`, `init(store: FleetStore, notifications: NotificationCoordinator)`, `func session(for account: AccountProfile) -> BrowserSession`, `func remove(accountID: UUID)`, `func clearWebsiteData(accountID: UUID) async throws`, `func suspendAll()`, `func resumeAll()`, `func keepOnly(accountID: UUID?)`. BrowserSession exposes `webView`, `canGoBack`, `canGoForward`, `isLoading`, `estimatedProgress`, `errorMessage`, `observerStatus`, `popupWebView: WKWebView?`, `downloadedFile: URL?`; `load(_ url: URL)`, `reload()`, `stop()`, `closePopup()`. `BrowserWebView(session:)` SwiftUI representable. `ObserverStatus` uses raw string values for UI. BrowserPool keeps at most three loaded sessions and persists data stores outside cache; background suspension stops detection. Notifications from browser use `NotificationCoordinator.receive(accountID:type:preview:conversationURL:eventID:)` on main actor.
- `@MainActor @Observable final class NotificationCoordinator`: `init(store:)`, `authorizationStatus: UNAuthorizationStatus`, `refreshAuthorization() async`, `requestAuthorization() async`, `receive(accountID: UUID, type: EventKind, preview: String?, conversationURL: URL?, eventID: String)`, `syncBadge()`, `pendingRoute: NotificationRoute?`. Route contains `accountID: UUID`, `url: URL?`, `eventID: String`. Native notifications use UUID account routing and validated HTTPS URLs. No production fake event source.
- `EventKind`: `response`, `completed`, `failed`, `attention`, `approval`, `question`, `artifact`, `progress`, `sessionExpired`; `NotificationSource`: `foregroundWeb`, `official`, `backgroundRefresh`, `externalChannel`, `remotePush`.
- `AppSettings`: Codable settings for app lock, appearance (`system/light/dark`), sound, haptics, preview privacy (default hidden), quiet hours enabled/start/end (hour 0...23).

## Assigned areas

- Lead: App/Core/Models.swift, FleetStore.swift, URLPolicy.swift, Security/, Notifications/, Resources/, integration and final docs.
- Browser engineer: App/Browser/**, BrowserTests/** (lead integrates tests).
- UI engineer: App/UI/** only. Use the interfaces above. UI gets FleetStore/BrowserPool/NotificationCoordinator from environment and account selection through a shared `@Observable NavigationState` defined in UI.
- DevOps engineer: project.yml, MuseFleet.xcodeproj/**, .github/**, scripts/**, Config/**, BUILD_IPA.md, Tests/Pipeline/**. Generate real deterministic Xcode project if XcodeGen unavailable locally.
- Research: research_notes/** and reports/** only, separate topic files.

## Quality gates

Use XCTest for data persistence, routing, deduplication, quiet hours and WKWebsiteDataStore isolation with a local fixture. Website-specific observer selectors remain unavailable until verified against actual Muse markup. Synthetic fixtures prove only fixture behavior. Do not claim 24/7 monitoring, background WebView polling, official Muse webhooks or APNs delivery without evidence. No relay deployment or costs without user permission. No screenshots or login details in logs. IPA must contain an actual arm64 Mach-O application binary; never create a placeholder IPA.
