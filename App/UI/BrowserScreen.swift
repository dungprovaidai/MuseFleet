import SwiftUI
import WebKit

@MainActor
struct BrowserScreen: View {
    @Environment(FleetStore.self) private var store
    @Environment(BrowserPool.self) private var pool
    @Environment(NavigationState.self) private var navigation
    @State private var switchingAccounts = false
    @State private var loadedBrowser: LoadedBrowser?

    var body: some View {
        Group {
            if let id = navigation.selectedAccountID, let account = store.account(id: id) {
                if let loadedBrowser, loadedBrowser.accountID == id {
                    AccountBrowserView(account: account, session: loadedBrowser.session,
                                       switchingAccounts: $switchingAccounts)
                        .id(account.id)
                } else {
                    ProgressView("Opening \(account.name)…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                EmptyFleetView(symbol: "person.crop.circle.badge.questionmark", title: "Account unavailable",
                               message: "This profile may have been deleted.", actionTitle: "Back to MuseFleet") {
                    navigation.closeBrowser()
                }
            }
        }
        .background(FleetStyle.canvas)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = store.storageError { StorageErrorBanner(message: error) }
        }
        .sheet(isPresented: $switchingAccounts) { BrowserAccountSwitcher() }
        .task(id: navigation.selectedAccountID) {
            guard let id = navigation.selectedAccountID, let account = store.account(id: id) else {
                loadedBrowser = nil
                return
            }
            loadedBrowser = LoadedBrowser(accountID: id, session: pool.session(for: account))
        }
    }
}

private struct LoadedBrowser {
    let accountID: UUID
    let session: BrowserSession
}

@MainActor
private struct AccountBrowserView: View {
    @Environment(FleetStore.self) private var store
    @Environment(NavigationState.self) private var navigation
    @Environment(\.openURL) private var openURL
    let account: AccountProfile
    let session: BrowserSession
    @Binding var switchingAccounts: Bool
    @State private var immersive = false
    @State private var showingInfo = false
    @State private var share: SharePayload?
    @State private var copiedLink = false

    private var currentURL: URL? {
        URLPolicy.safeConversation(session.availableWebView?.url)
    }

    private var shareableDownload: URL? {
        guard let url = session.downloadedFile, url.isFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var body: some View {
        VStack(spacing: 0) {
            if !immersive { header }
            if session.isLoading {
                ProgressView(value: min(1, max(0, session.estimatedProgress)))
                    .tint(Color(hex: account.colorHex))
                    .accessibilityLabel("Loading Muse")
            }
            if let error = session.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label("The page could not load", systemImage: "wifi.exclamationmark").font(.subheadline.bold())
                    Text(error).font(.caption).textSelection(.enabled)
                    Button("Try again", systemImage: "arrow.clockwise") {
                        session.reload()
                    }
                    .buttonStyle(.bordered)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12))
            }
            page
                .accessibilityIdentifier("browser.web")
                .overlay(alignment: .topTrailing) {
                    if immersive {
                        Button { immersive = false } label: {
                            Label("Show controls", systemImage: "arrow.down.right.and.arrow.up.left")
                                .font(.subheadline.weight(.semibold)).padding(12)
                                .background(.regularMaterial, in: Capsule())
                        }
                        .padding(12)
                    }
                }
            if !immersive {
                if let download = shareableDownload {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc").foregroundStyle(FleetStyle.accent)
                        Text(download.lastPathComponent).font(.caption).lineLimit(2)
                        Spacer()
                        Button("Share download") { share = SharePayload(items: [download]) }.font(.subheadline.bold())
                    }
                    .padding(12).background(FleetStyle.surface)
                }
                controls
            }
        }
        .background(FleetStyle.surface)
        .onAppear {
            if session.isAvailable && session.availableWebView?.url == nil && !session.isLoading {
                session.load(URLPolicy.safeConversation(account.lastURL) ?? URLPolicy.home)
            }
        }
        .sheet(isPresented: $showingInfo) { browserInfo }
        .sheet(item: $share) { ActivitySheet(items: $0.items).presentationDetents([.medium, .large]) }
        .sheet(isPresented: Binding(
            get: { session.popupWebView != nil },
            set: { if !$0 { session.closePopup() } }
        )) {
            if let popup = session.popupWebView { BrowserPopupView(webView: popup, session: session) }
        }
        .onChange(of: currentURL) { _, _ in copiedLink = false }
    }

    @ViewBuilder private var page: some View {
        if session.popupWebView == nil {
            BrowserWebView(session: session)
        } else {
            // The shared browser wrapper hosts popups inline; release it while this sheet owns the popup.
            VStack(spacing: 14) {
                Image(systemName: "macwindow.on.rectangle").font(.largeTitle).foregroundStyle(FleetStyle.accent)
                Text("A website window is open").font(.headline)
                Button("Close web window", action: session.closePopup).buttonStyle(.bordered)
            }
            .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button("Close browser", systemImage: "chevron.down") { navigation.closeBrowser() }
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("browser.close")
            Button { switchingAccounts = true } label: {
                HStack(spacing: 10) {
                    AccountAvatar(account: account, size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.name).font(.subheadline.bold()).lineLimit(1)
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill").font(.system(size: 9))
                            Text(session.availableWebView?.url?.host ?? URLPolicy.home.host ?? "Muse")
                                .font(.caption2).lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.bold()).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(account.name), switch account")
            .accessibilityIdentifier("browser.switchAccount")
            Menu {
                Button("Share link", systemImage: "square.and.arrow.up") {
                    if let currentURL { share = SharePayload(items: [currentURL]) }
                }.disabled(currentURL == nil)
                Button(copiedLink ? "Link copied" : "Copy link", systemImage: copiedLink ? "checkmark" : "link") {
                    if let currentURL { UIPasteboard.general.url = currentURL; copiedLink = true }
                }.disabled(currentURL == nil)
                Button("Open in Safari", systemImage: "safari") {
                    if let currentURL { openURL(currentURL) }
                }.disabled(currentURL == nil)
                Divider()
                Button("Hide browser controls", systemImage: "arrow.up.left.and.arrow.down.right") { immersive = true }
                if let previous = navigation.previousAccountID, let profile = store.account(id: previous) {
                    Button("Back to \(profile.name)", systemImage: "arrow.left.arrow.right") { navigation.switchToPrevious() }
                }
                Button("Browser information", systemImage: "info.circle") { showingInfo = true }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Browser actions")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.bar)
    }

    private var controls: some View {
        HStack {
            Button("Back", systemImage: "chevron.left") { session.availableWebView?.goBack() }
                .disabled(!session.canGoBack)
            Spacer(minLength: 8)
            Button("Forward", systemImage: "chevron.right") { session.availableWebView?.goForward() }
                .disabled(!session.canGoForward)
            Spacer(minLength: 8)
            Button("Muse home", systemImage: "house") { session.load(URLPolicy.home) }
            Spacer(minLength: 8)
            Button(session.isLoading ? "Stop loading" : "Reload", systemImage: session.isLoading ? "xmark" : "arrow.clockwise") {
                if session.isLoading { session.stop() } else { session.reload() }
            }
            Spacer(minLength: 8)
            Button("Switch account", systemImage: "person.2") { switchingAccounts = true }
        }
        .labelStyle(.iconOnly).font(.body.weight(.medium))
        .buttonStyle(BrowserControlStyle())
        .padding(.horizontal, 18).padding(.vertical, 5)
        .background(.bar)
    }

    private var browserInfo: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        AccountAvatar(account: account)
                        Text(account.name).font(.headline)
                    }
                    LabeledContent("Detection status", value: session.observerStatus.rawValue)
                }
                Section("Sign-in") {
                    Text("Sign in directly on the official Muse website. Each profile keeps a separate website sign-in.")
                    Text("Some sign-in providers may not support an embedded browser. Safari uses a separate sign-in; opening Safari does not sign this profile in.")
                }
                Section("Activity and background limits") {
                    Text("Detection needs verified support for the Muse website. Permission to send notifications does not provide an event source.")
                    Text("Web activity pauses in the background. Only a verified external integration could deliver updates while this app is suspended; none is set up here.")
                    Text("Up to three account pages can stay loaded at once. Other profiles keep their website data and reload when opened.")
                }
                Section("Privacy") {
                    Text("MuseFleet never asks for your Muse password or verification codes. Use the website’s sign-in page.")
                }
            }
            .navigationTitle("This browser").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingInfo = false } } }
        }
    }
}

private struct BrowserControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 44, minHeight: 44)
            .background(configuration.isPressed ? FleetStyle.accent.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12))
    }
}

@MainActor
private struct BrowserAccountSwitcher: View {
    @Environment(FleetStore.self) private var store
    @Environment(NavigationState.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var accounts: [AccountProfile] {
        store.accounts.filter {
            search.isEmpty || [$0.name, $0.project, $0.group].joined(separator: " ").localizedStandardContains(search)
        }.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return $0.sortOrder < $1.sortOrder
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty, let previousID = navigation.previousAccountID,
                   let previous = store.account(id: previousID), previousID != navigation.selectedAccountID {
                    Section("Previous account") { accountButton(previous) }
                }
                Section("All accounts") {
                    ForEach(accounts) { accountButton($0) }
                }
                if accounts.isEmpty { Text("No matching accounts.").foregroundStyle(.secondary) }
            }
            .searchable(text: $search, prompt: "Find an account")
            .navigationTitle("Switch account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func accountButton(_ account: AccountProfile) -> some View {
        Button {
            navigation.switchTo(account)
            dismiss()
        } label: {
            HStack {
                AccountListRow(account: account, unreadCount: store.unreadCount(accountID: account.id))
                if navigation.selectedAccountID == account.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(FleetStyle.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(navigation.selectedAccountID == account.id ? "Current account" : "")
    }
}

@MainActor
private struct BrowserPopupView: View {
    @Environment(\.openURL) private var openURL
    let webView: WKWebView
    let session: BrowserSession
    @State private var currentURL: URL?
    @State private var urlObservation: NSKeyValueObservation?

    var body: some View {
        NavigationStack {
            PopupWebView(webView: webView)
                .safeAreaInset(edge: .bottom) {
                    Text("Complete sign-in on the website. Some providers require a browser they support.")
                        .font(.caption).foregroundStyle(.secondary).padding().frame(maxWidth: .infinity)
                        .background(.bar)
                }
                .navigationTitle(currentURL?.host ?? "Web window").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close", action: session.closePopup) }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Open in Safari", systemImage: "safari") {
                            if let currentURL, URLPolicy.isSafeExternal(currentURL) { openURL(currentURL) }
                        }
                        .labelStyle(.iconOnly)
                        .disabled(currentURL.map { !URLPolicy.isSafeExternal($0) } ?? true)
                    }
                }
        }
        .onAppear {
            urlObservation = webView.observe(\.url, options: [.initial, .new]) { view, _ in
                let url = view.url
                Task { @MainActor in currentURL = url }
            }
        }
        .onDisappear {
            urlObservation?.invalidate()
            urlObservation = nil
        }
        .modifier(PopupSessionPrompts(session: session))
    }
}

@MainActor
private struct PopupSessionPrompts: ViewModifier {
    let session: BrowserSession

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Open outside MuseFleet?", isPresented: Binding(
                get: { session.pendingExternalURL != nil },
                set: { if !$0 { session.cancelExternalOpen() } }
            ), titleVisibility: .visible, presenting: session.pendingExternalURL) { _ in
                Button("Open link") { session.confirmExternalOpen() }
                Button("Cancel", role: .cancel) { session.cancelExternalOpen() }
            } message: { url in
                Text("This opens \(url.host ?? "another app") outside this account’s browser. Safari and other apps use their own sign-in.")
            }
            .alert(session.javaScriptDialog?.host ?? "Website", isPresented: Binding(
                get: { session.javaScriptDialog != nil },
                set: { if !$0 { session.resolveJavaScriptDialog(confirmed: false) } }
            ), presenting: session.javaScriptDialog) { dialog in
                Button("OK") { session.resolveJavaScriptDialog(confirmed: true) }
                if dialog.isConfirmation {
                    Button("Cancel", role: .cancel) { session.resolveJavaScriptDialog(confirmed: false) }
                }
            } message: { dialog in
                Text(dialog.message)
            }
    }
}

private struct PopupWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
