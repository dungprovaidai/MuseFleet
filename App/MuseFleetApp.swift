import SwiftUI
import UIKit

@main
@MainActor
struct MuseFleetApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: FleetStore
    @State private var notifications: NotificationCoordinator
    @State private var browsers: BrowserPool
    @State private var navigation = NavigationState()
    @State private var appLock = AppLock()

    init() {
        let store = FleetStore()
        store.settings.appLockEnabled = KeychainLock.enabled()
        let notifications = NotificationCoordinator(store: store)
        _store = State(initialValue: store)
        _notifications = State(initialValue: notifications)
        _browsers = State(initialValue: BrowserPool(store: store, notifications: notifications))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                FleetRootView()
                    .environment(store)
                    .environment(notifications)
                    .environment(browsers)
                    .environment(navigation)
                    .environment(appLock)
                    .privacySensitive()
                    .allowsHitTesting(!appLock.isLocked && scenePhase == .active)
                    .accessibilityHidden(appLock.isLocked || scenePhase != .active)
                if appLock.isLocked || scenePhase != .active {
                    privacyCurtain
                        .zIndex(100)
                }
            }
            .preferredColorScheme(store.settings.appearance == "dark" ? .dark : store.settings.appearance == "light" ? .light : nil)
            .task {
                await notifications.refreshAuthorization()
                await appLock.unlock(enabled: KeychainLock.enabled())
                if !appLock.isLocked { browsers.resumeAll(); consumeNotificationRoute() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    browsers.suspendAll()
                    appLock.lock(enabled: KeychainLock.enabled())
                    store.save()
                } else if phase == .active {
                    Task {
                        await notifications.refreshAuthorization()
                        await appLock.unlock(enabled: KeychainLock.enabled())
                        if !appLock.isLocked { browsers.resumeAll(); consumeNotificationRoute() }
                    }
                } else {
                    browsers.suspendAll()
                }
            }
            .onChange(of: notifications.pendingRoute) { _, _ in consumeNotificationRoute() }
            .onChange(of: appLock.isLocked) { _, locked in
                if !locked { browsers.resumeAll(); consumeNotificationRoute() }
            }
            .onChange(of: store.settings.appLockEnabled) { _, enabled in
                guard enabled != KeychainLock.enabled() else { return }
                Task { await appLock.confirmSettingChange(enabled: enabled, store: store) }
            }
            .onChange(of: store.settings.hideNotificationPreviews) { _, _ in notifications.applyPrivacySettings() }
            .onChange(of: store.events) { _, _ in notifications.syncBadge() }
            .onChange(of: store.accounts.map(\.id)) { old, new in
                for id in old where !new.contains(id) {
                    browsers.remove(accountID: id)
                    notifications.removeNotifications(accountID: id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                browsers.keepOnly(accountID: navigation.selectedAccountID)
            }
            .alert("App lock", isPresented: Binding(
                get: { appLock.errorMessage != nil && !appLock.isLocked },
                set: { if !$0 { appLock.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { appLock.errorMessage = nil }
            } message: {
                Text(appLock.errorMessage ?? "")
            }
        }
    }

    private var privacyCurtain: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("MuseFleet").font(.largeTitle.bold())
                if appLock.isLocked && scenePhase == .active {
                    Text("Your accounts are locked").foregroundStyle(.secondary)
                    Button {
                        Task { await appLock.unlock(enabled: KeychainLock.enabled()) }
                    } label: {
                        Label("Unlock", systemImage: "lock.open")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(appLock.isAuthenticating)
                    if let error = appLock.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
            }
            .padding(32)
        }
    }

    private func consumeNotificationRoute() {
        guard scenePhase == .active, !appLock.isLocked,
              let route = notifications.pendingRoute,
              var account = store.account(id: route.accountID) else { return }
        let url = URLPolicy.safeConversation(route.url) ?? URLPolicy.home
        account.lastURL = url
        store.updateAccount(account)
        browsers.session(for: account).load(url)
        navigation.openAccount(account.id)
        store.markRead(route.eventID)
        notifications.clearDelivered(eventID: route.eventID)
        notifications.pendingRoute = nil
    }
}
