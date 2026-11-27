import SwiftUI
import UserNotifications
import UIKit

@MainActor
struct SettingsView: View {
    @Environment(FleetStore.self) private var store
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(AppLock.self) private var appLock
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var requestingPermission = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "square.stack.3d.up.fill").font(.title)
                            .foregroundStyle(.white).frame(width: 60, height: 60)
                            .background(FleetStyle.accent.gradient, in: RoundedRectangle(cornerRadius: 19))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Make it your space").font(.headline)
                            Text("A few thoughtful defaults. Your choice from here.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Appearance") {
                    Picker("Theme", selection: setting(\.appearance)) {
                        Text("Follow system").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }
                .disabled(store.persistenceUnavailable)

                Section {
                    LabeledContent("Permission", value: authorizationLabel(notifications.authorizationStatus))
                    if notifications.authorizationStatus == .notDetermined {
                        Button {
                            requestingPermission = true
                            Task {
                                await notifications.requestAuthorization()
                                requestingPermission = false
                            }
                        } label: {
                            HStack {
                                Label("Allow notifications", systemImage: "bell.badge")
                                Spacer()
                                if requestingPermission { ProgressView() }
                            }
                        }
                        .disabled(requestingPermission)
                    } else {
                        Button("Open notification settings", systemImage: "arrow.up.forward.app") { openSystemSettings() }
                    }
                    Toggle("Sound", isOn: setting(\.soundEnabled))
                        .disabled(store.persistenceUnavailable)
                    Toggle("Haptics", isOn: setting(\.hapticsEnabled))
                        .disabled(store.persistenceUnavailable)
                    if let error = notifications.deliveryError {
                        Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.orange)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Permission allows iOS to display alerts from supported event sources. Check detection status below for what is currently available.")
                }

                Section {
                    Toggle("Quiet hours", isOn: setting(\.quietHoursEnabled))
                    if store.settings.quietHoursEnabled {
                        Picker("From", selection: setting(\.quietStartHour)) { hourOptions }
                        Picker("Until", selection: setting(\.quietEndHour)) { hourOptions }
                    }
                } header: {
                    Text("A little breathing room")
                } footer: {
                    Text(store.settings.quietHoursEnabled && store.settings.quietStartHour == store.settings.quietEndHour
                         ? "Matching start and end times silence alerts all day. Activity can still appear in Inbox."
                         : "Uses your device’s local time. Received events stay in Inbox while alerts are silenced.")
                }
                .disabled(store.persistenceUnavailable)

                Section {
                    Toggle("Hide message previews", isOn: setting(\.hideNotificationPreviews))
                    Toggle("Require device authentication", isOn: Binding(
                        get: { store.settings.appLockEnabled },
                        set: { enabled in Task { await appLock.confirmSettingChange(enabled: enabled, store: store) } }
                    ))
                        .accessibilityIdentifier("settings.appLock")
                        .disabled(appLock.isChangingSetting)
                    if appLock.isChangingSetting { ProgressView("Waiting for authentication…") }
                } header: {
                    Text("Privacy & access")
                } footer: {
                    Text("Hidden previews keep message text out of new notifications and saved events. App lock uses Face ID, Touch ID, or your device passcode.")
                }
                .disabled(store.persistenceUnavailable)

                Section("On this device") {
                    NavigationLink { StorageManagerView() } label: {
                        Label("Storage & website data", systemImage: "externaldrive")
                    }
                    NavigationLink { DetectionDiagnosticsView() } label: {
                        Label("Detection & delivery status", systemImage: "waveform.path.ecg")
                    }
                    NavigationLink { AboutFleetView() } label: {
                        Label("About MuseFleet", systemImage: "info.circle")
                    }
                }
                if let error = store.storageError {
                    Section("Storage needs attention") {
                        Text(error).foregroundStyle(.orange)
                        if !store.persistenceUnavailable { Button("Try saving again") { store.save() } }
                    }
                }
            }
            .navigationTitle("Settings")
            .task { await notifications.refreshAuthorization() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await notifications.refreshAuthorization() } }
            }
        }
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { value in
            guard !store.persistenceUnavailable else { return }
            store.settings[keyPath: keyPath] = value
            store.save()
        })
    }

    @ViewBuilder private var hourOptions: some View {
        ForEach(0..<24) { hour in
            Text(hourLabel(hour)).tag(hour)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour)) ?? .distantPast
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
    }
}

private func authorizationLabel(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: "Not requested"
    case .denied: "Off in iOS Settings"
    case .authorized: "Allowed"
    case .provisional: "Delivered quietly"
    case .ephemeral: "Temporarily allowed"
    @unknown default: "Unknown"
    }
}

@MainActor
private struct StorageManagerView: View {
    @Environment(FleetStore.self) private var store
    @Environment(BrowserPool.self) private var pool
    @State private var target: AccountProfile?
    @State private var clearingID: UUID?
    @State private var result: StorageResult?

    var body: some View {
        List {
            Section {
                LabeledContent("Account profiles", value: "\(store.accounts.count)")
                LabeledContent("Inbox events", value: "\(store.events.count)")
            } footer: {
                Text("Profiles and activity are saved on this device. Clearing website data signs an account out; it keeps the profile and its activity.")
            }
            Section("Website data by account") {
                if store.accounts.isEmpty { Text("No accounts yet.").foregroundStyle(.secondary) }
                ForEach(store.accounts.sorted { $0.sortOrder < $1.sortOrder }) { account in
                    VStack(alignment: .leading, spacing: 8) {
                        AccountListRow(account: account, unreadCount: 0)
                        Button(role: .destructive) { target = account } label: {
                            HStack {
                                Label(clearingID == account.id ? "Clearing…" : "Clear website data", systemImage: "trash")
                                Spacer()
                                if clearingID == account.id { ProgressView() }
                            }
                        }
                        .disabled(clearingID != nil || store.persistenceUnavailable)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Storage").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear website data?", isPresented: Binding(
            get: { target != nil }, set: { if !$0 { target = nil } }
        ), titleVisibility: .visible, presenting: target) { account in
            Button("Clear & sign out", role: .destructive) { Task { await clear(account) } }
            Button("Cancel", role: .cancel) { target = nil }
        } message: { account in
            Text("This signs \(account.name) out of its MuseFleet browser and clears its website storage. Your Muse account and conversations are not deleted.")
        }
        .alert(item: $result) { result in
            Alert(title: Text(result.title), message: Text(result.message), dismissButton: .default(Text("OK")))
        }
    }

    private func clear(_ account: AccountProfile) async {
        clearingID = account.id
        defer { clearingID = nil }
        do {
            try await pool.clearWebsiteData(accountID: account.id)
            result = StorageResult(title: "Website data cleared", message: "\(account.name) can sign in again when you open it.")
        } catch {
            result = StorageResult(title: "Could not clear website data", message: error.localizedDescription)
        }
    }
}

private struct StorageResult: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
private struct DetectionDiagnosticsView: View {
    @Environment(FleetStore.self) private var store
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                Label("Know what can reach you", systemImage: "waveform.path.ecg").font(.headline)
                Text("Available sources are listed below. Notification permission alone cannot detect changes in your Muse accounts.")
                    .font(.subheadline).foregroundStyle(.secondary)
                LabeledContent("iOS permission", value: authorizationLabel(notifications.authorizationStatus))
                LabeledContent("App state", value: scenePhase == .active ? "Foreground" : "Inactive")
                if let error = notifications.deliveryError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }
            Section("Event sources") {
                ForEach(NotificationCapabilities.all) { capability in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(capability.source.title).font(.headline)
                        Text(capability.level.rawValue.capitalized)
                            .font(.caption.weight(.semibold)).foregroundStyle(levelColor(capability.level))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(levelColor(capability.level).opacity(0.10), in: Capsule())
                        Text(capability.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 7)
                    .accessibilityElement(children: .combine)
                }
            }
            Section("What to expect") {
                Text("iOS suspends browser work in the background. MuseFleet does not provide continuous web monitoring.")
                Text("A maximum of three account pages stay loaded. Opening another account can unload an older page; its sign-in data remains separate and saved.")
                Text("No relay or remote push service is deployed by this app. A verified source and explicit setup would be required.")
            }
            if let error = store.storageError {
                Section("Storage") { Text(error).foregroundStyle(.orange) }
            }
        }
        .navigationTitle("Detection & delivery").navigationBarTitleDisplayMode(.inline)
        .task { await notifications.refreshAuthorization() }
    }

    private func levelColor(_ level: CapabilityLevel) -> Color {
        switch level {
        case .verified: .green
        case .documented: .blue
        case .unverified: .orange
        case .unsupported, .blocked: .secondary
        }
    }
}

private struct AboutFleetView: View {
    private var version: String {
        let release = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(release) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "square.stack.3d.up.fill").font(.largeTitle).foregroundStyle(FleetStyle.accent)
                    Text("MuseFleet").font(.largeTitle.bold())
                    Text("A calmer home for your Muse accounts.").foregroundStyle(.secondary)
                }
                .padding(.vertical, 14)
                LabeledContent("Version", value: version)
                Link(destination: URLPolicy.home) { Label("Visit the official Muse website", systemImage: "safari") }
            }
            Section("Your accounts, kept separate") {
                Text("MuseFleet is an independent companion and is not affiliated with Muse. Your conversations and subscription are managed on the official Muse website.")
                Text("Sign in on the website in each profile. MuseFleet never asks you to share passwords, verification codes, or browser credentials.")
            }
        }
        .navigationTitle("About").navigationBarTitleDisplayMode(.inline)
    }
}
