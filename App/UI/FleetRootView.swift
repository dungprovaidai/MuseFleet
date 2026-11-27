import SwiftUI

@MainActor
struct FleetRootView: View {
    @Environment(FleetStore.self) private var store
    @Environment(NavigationState.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation

        TabView(selection: $navigation.selectedTab) {
            HomeView().tabItem { Label("Home", systemImage: "square.grid.2x2").accessibilityIdentifier("tab.home") }.tag(0)
            AccountsView().tabItem { Label("Accounts", systemImage: "person.2").accessibilityIdentifier("tab.accounts") }.tag(1)
            InboxView().tabItem { Label("Inbox", systemImage: "tray").accessibilityIdentifier("tab.inbox") }
                .badge(store.unreadCount()).tag(2)
            SettingsView().tabItem { Label("Settings", systemImage: "slider.horizontal.3").accessibilityIdentifier("tab.settings") }.tag(3)
        }
        .tint(FleetStyle.accent)
        .preferredColorScheme(colorScheme)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = store.storageError {
                StorageErrorBanner(message: message)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { navigation.selectedAccountID != nil },
            set: { if !$0 { navigation.closeBrowser() } }
        )) {
            BrowserScreen().preferredColorScheme(colorScheme)
        }
        .onChange(of: store.accounts.map(\.id)) { _, ids in
            if let selected = navigation.selectedAccountID, !ids.contains(selected) {
                navigation.closeBrowser()
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch store.settings.appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

@MainActor
struct StorageErrorBanner: View {
    @Environment(FleetStore.self) private var store
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(store.persistenceUnavailable ? "Saved data is unavailable" : "Changes could not be saved",
                  systemImage: "externaldrive.badge.exclamationmark")
                .font(.subheadline.bold())
            Text(message).font(.caption)
            if !store.persistenceUnavailable {
                Button("Try saving again") { store.save() }.font(.subheadline.bold())
            }
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.15))
        .accessibilityElement(children: .contain)
    }
}
