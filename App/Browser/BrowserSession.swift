import Observation
import UIKit
import WebKit

@MainActor @Observable
final class BrowserSession: NSObject, NotificationProvider {
    let accountID: UUID
    private var ownedWebView: WKWebView?
    var isAvailable: Bool { ownedWebView != nil && !disposed && !clearingWebsiteData }
    var availableWebView: WKWebView? { isAvailable ? ownedWebView : nil }
    var webView: WKWebView {
        guard let ownedWebView else { preconditionFailure("Use BrowserWebView while the account is closing or clearing data.") }
        return ownedWebView
    }
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var estimatedProgress = 0.0
    private(set) var errorMessage: String?
    private(set) var observerStatus: ObserverStatus = .unavailable
    private(set) var popupWebView: WKWebView?
    var downloadedFile: URL?
    private(set) var pendingExternalURL: URL?
    private(set) var javaScriptDialog: BrowserJavaScriptDialog?
    private(set) var needsReload = false
    private(set) var lastCheckedAt: Date?

    let source: NotificationSource = .foregroundWeb
    var capability: NotificationCapability {
        NotificationCapability(source: source, level: .blocked,
            detail: adapter == nil
                ? "Muse's authenticated completion markers are unverified. Detection is unavailable."
                : "Only verified markers on loaded pages in the active app can be observed. No background delivery is configured.")
    }

    @ObservationIgnored private let store: FleetStore
    @ObservationIgnored private let notifications: NotificationCoordinator
    @ObservationIgnored private let adapter = BrowserObserverAdapter.muse
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var popupObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var downloads: [ObjectIdentifier: DownloadRecord] = [:]
    @ObservationIgnored private var suspended: Bool
    @ObservationIgnored private var clearingWebsiteData: Bool
    @ObservationIgnored private var disposed = false
    @ObservationIgnored private var detectionEnabled = true
    @ObservationIgnored private var deferredURL: URL?
    @ObservationIgnored private var blockedMainFrameNavigation = false
    @ObservationIgnored private var blockedMainFrameHost: String?
    @ObservationIgnored private var observerSource: String?
    @ObservationIgnored private var observerDocumentID: String?
    @ObservationIgnored private var receivedEventIDs: Set<String> = []
    private static let observerWorld = WKContentWorld.world(name: "MuseFleet.Observer")
    private static let handlerName = "museFleetObserver"

    var displayedWebView: WKWebView { popupWebView ?? webView }

    init(account: AccountProfile, store: FleetStore, notifications: NotificationCoordinator,
         suspended: Bool = false, clearingWebsiteData: Bool = false) {
        accountID = account.id
        self.store = store
        self.notifications = notifications
        self.suspended = suspended
        self.clearingWebsiteData = clearingWebsiteData
        super.init()
        if !clearingWebsiteData { createWebView() }
        let initialURL = URLPolicy.safeConversation(account.lastURL) ?? URLPolicy.home
        if suspended || clearingWebsiteData {
            deferredURL = initialURL
            observerStatus = .suspended
        } else {
            load(initialURL)
        }
    }

    func load(_ url: URL) {
        guard !disposed else { return }
        guard BrowserNavigationPolicy.allowsInWeb(url) else {
            askToOpenExternally(url)
            return
        }
        guard !suspended, !clearingWebsiteData else { deferredURL = url; return }
        guard isAvailable else { return }
        pendingExternalURL = nil
        resolveJavaScriptDialog(confirmed: false)
        closePopup()
        errorMessage = nil
        blockedMainFrameNavigation = false
        blockedMainFrameHost = nil
        needsReload = false
        detectionEnabled = true
        installObserverScript()
        webView.load(URLRequest(url: url))
    }

    func reload() {
        guard isAvailable, !suspended else { return }
        pendingExternalURL = nil
        resolveJavaScriptDialog(confirmed: false)
        errorMessage = nil
        blockedMainFrameNavigation = false
        blockedMainFrameHost = nil
        needsReload = false
        detectionEnabled = true
        installObserverScript()
        if let url = displayedWebView.url, BrowserNavigationPolicy.allowsInWeb(url) {
            displayedWebView.reload()
        } else {
            load(URLPolicy.safeConversation(store.account(id: accountID)?.lastURL) ?? URLPolicy.home)
        }
    }

    func start() {
        guard isAvailable, !suspended else { return }
        detectionEnabled = true
        installObserverScript()
        guard let observerSource, URLPolicy.isMuse(webView.url ?? URLPolicy.home), webView.url != nil else { return }
        webView.evaluateJavaScript(observerSource, in: nil, in: Self.observerWorld) { [weak self] result in
            if case .failure = result { self?.observerStatus = .failed }
        }
    }

    func stop() {
        ownedWebView?.stopLoading()
        popupWebView?.stopLoading()
        detectionEnabled = false
        stopObserver()
        synchronizeState()
    }

    func closePopup() {
        guard let popup = popupWebView else { return }
        resolveJavaScriptDialog(confirmed: false)
        popup.stopLoading()
        popup.navigationDelegate = nil
        popup.uiDelegate = nil
        detach(popup)
        popupObservations.removeAll()
        popupWebView = nil
        needsReload = false
        synchronizeState()
    }

    func suspend() {
        suspended = true
        pendingExternalURL = nil
        resolveJavaScriptDialog(confirmed: false)
        stop()
        ownedWebView?.setAllMediaPlaybackSuspended(true, completionHandler: {})
        popupWebView?.setAllMediaPlaybackSuspended(true, completionHandler: {})
    }

    func resume() {
        guard isAvailable else { return }
        suspended = false
        webView.setAllMediaPlaybackSuspended(false, completionHandler: {})
        popupWebView?.setAllMediaPlaybackSuspended(false, completionHandler: {})
        if let deferredURL {
            self.deferredURL = nil
            load(deferredURL)
        } else {
            start()
        }
    }

    func finishClearingWebsiteData(suspended: Bool) {
        guard !disposed else { return }
        self.suspended = suspended
        clearingWebsiteData = false
        createWebView()
        let url = URLPolicy.safeConversation(store.account(id: accountID)?.lastURL) ?? URLPolicy.home
        if suspended { deferredURL = url } else { load(url) }
    }

    func dispose() {
        guard !disposed else { return }
        suspend()
        closePopup()
        disposed = true
        for record in downloads.values {
            record.download.delegate = nil
            record.download.cancel { _ in }
        }
        downloads.removeAll()
        observations.removeAll()
        if let view = ownedWebView {
            view.navigationDelegate = nil
            view.uiDelegate = nil
            let controller = view.configuration.userContentController
            controller.removeAllUserScripts()
            controller.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: Self.observerWorld)
            detach(view)
        }
        // Releasing the view lets identifier-based store removal succeed even if SwiftUI retains this session.
        ownedWebView = nil
    }

    func confirmExternalOpen() {
        guard let url = pendingExternalURL, !suspended, isAvailable,
              BrowserNavigationPolicy.canAskToOpenExternally(url) else {
            pendingExternalURL = nil
            return
        }
        pendingExternalURL = nil
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            guard !success else { return }
            Task { @MainActor [weak self] in self?.errorMessage = "No app could open this link." }
        }
    }

    func cancelExternalOpen() { pendingExternalURL = nil }

    func resolveJavaScriptDialog(confirmed: Bool) {
        let dialog = javaScriptDialog
        javaScriptDialog = nil
        dialog?.completion(confirmed)
    }

    private func createWebView() {
        guard ownedWebView == nil, !disposed, !clearingWebsiteData else { return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: accountID)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        ownedWebView = view
        configure(view)
        observations = observe(view)
        if adapter != nil {
            configuration.userContentController.add(WeakBrowserScriptHandler(target: self),
                contentWorld: Self.observerWorld, name: Self.handlerName)
        }
    }

    private func configure(_ view: WKWebView) {
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        // WebKit's native input[type=file] picker stays enabled; no upload interception or UA override.
        view.allowsLinkPreview = false
    }

    private func detach(_ view: WKWebView) {
        if let container = view.superview as? BrowserContainerView {
            container.show(nil, popup: false, needsReload: false, message: nil)
        } else { view.removeFromSuperview() }
    }

    private func observe(_ view: WKWebView) -> [NSKeyValueObservation] {
        let update: (WKWebView, NSKeyValueObservedChange<Bool>) -> Void = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.synchronizeState() }
        }
        return [view.observe(\.canGoBack, options: [.initial, .new], changeHandler: update),
                view.observe(\.canGoForward, options: [.initial, .new], changeHandler: update),
                view.observe(\.isLoading, options: [.initial, .new], changeHandler: update),
                view.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.synchronizeState() }
                },
                view.observe(\.url, options: [.new]) { [weak self, weak view] _, _ in
                    Task { @MainActor [weak self, weak view] in
                        guard let self, let view, view === self.ownedWebView else { return }
                        self.rememberVisit(view.url)
                    }
                }]
    }

    private func synchronizeState() {
        guard let view = popupWebView ?? ownedWebView else {
            canGoBack = false
            canGoForward = false
            isLoading = false
            estimatedProgress = 0
            return
        }
        canGoBack = view.canGoBack
        canGoForward = view.canGoForward
        isLoading = view.isLoading
        estimatedProgress = view.estimatedProgress
    }

    private func rememberVisit(_ url: URL?) {
        guard !disposed, !clearingWebsiteData, let url = BrowserNavigationPolicy.visitURL(url),
              var account = store.account(id: accountID) else { return }
        account.lastURL = url
        account.lastVisitedAt = Date()
        store.updateAccount(account)
    }

    private func askToOpenExternally(_ url: URL) {
        guard !suspended, !clearingWebsiteData, !disposed else { return }
        guard BrowserNavigationPolicy.canAskToOpenExternally(url) else {
            errorMessage = "This link is blocked. Only secure websites and confirmed app links can open."
            return
        }
        guard pendingExternalURL == nil else { return }
        pendingExternalURL = url
    }

    private func installObserverScript() {
        guard let webView = ownedWebView else { observerStatus = .suspended; return }
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        observerDocumentID = nil
        guard !suspended, detectionEnabled, !clearingWebsiteData else { observerStatus = .suspended; return }
        guard let adapter else { observerStatus = .unavailable; return }
        do {
            guard let url = Bundle.main.url(forResource: "CompletionObserver", withExtension: "js") else {
                observerStatus = .failed
                return
            }
            let engine = try String(contentsOf: url, encoding: .utf8)
            let source = try adapter.source(engine: engine)
            observerSource = source
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd,
                forMainFrameOnly: true, in: Self.observerWorld))
            observerStatus = .loading
        } catch { observerStatus = .failed }
    }

    private func stopObserver() {
        observerDocumentID = nil
        observerStatus = .suspended
        guard let webView = ownedWebView else { return }
        webView.configuration.userContentController.removeAllUserScripts()
        if adapter != nil {
            webView.evaluateJavaScript("globalThis.MuseFleetObserver?.stop();", in: nil,
                                      in: Self.observerWorld) { _ in }
        }
    }

    private func navigationFailed(_ error: Error, in view: WKWebView) {
        guard !disposed else { return }
        let failure = error as NSError
        guard view === displayedWebView else { return }
        if failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled {
            blockedMainFrameNavigation = false
            blockedMainFrameHost = nil
            return
        }
        // Localized errors can contain authentication URLs; expose only the category, code, and sanitized host.
        errorMessage = BrowserNavigationFailure.message(domain: failure.domain, code: failure.code,
                                                        policyBlocked: blockedMainFrameNavigation,
                                                        blockedHost: blockedMainFrameHost)
        blockedMainFrameNavigation = false
        blockedMainFrameHost = nil
        if view === ownedWebView { observerStatus = adapter == nil ? .unavailable : .failed }
        synchronizeState()
    }

    private func attach(_ download: WKDownload) {
        guard !disposed, !suspended, !clearingWebsiteData else { download.cancel { _ in }; return }
        downloads[ObjectIdentifier(download)] = DownloadRecord(download: download, destination: nil)
        download.delegate = self
    }

    private struct DownloadRecord {
        let download: WKDownload
        var destination: URL?
    }
}

extension BrowserSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !disposed, !suspended, !clearingWebsiteData, let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if BrowserNavigationPolicy.allowsInWeb(url) {
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
        } else if BrowserNavigationPolicy.allowsBlobDownload(url),
                  let current = webView.url, URLPolicy.isMuse(current) {
            decisionHandler(.download)
        } else if url.absoluteString == "about:blank",
                  webView === popupWebView || (navigationAction.targetFrame == nil &&
                    navigationAction.sourceFrame.request.url.map(BrowserNavigationPolicy.allowsInWeb) == true) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if navigationAction.targetFrame?.isMainFrame != false {
                blockedMainFrameNavigation = true
                blockedMainFrameHost = BrowserNavigationPolicy.displayHost(url)
                askToOpenExternally(url)
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard !disposed, !suspended, !clearingWebsiteData, let url = navigationResponse.response.url,
              BrowserNavigationPolicy.allowsInWeb(url) || BrowserNavigationPolicy.allowsBlobDownload(url) ||
                (webView === popupWebView && url.absoluteString == "about:blank") else {
            decisionHandler(.cancel)
            if navigationResponse.isForMainFrame, let url = navigationResponse.response.url {
                blockedMainFrameNavigation = true
                blockedMainFrameHost = BrowserNavigationPolicy.displayHost(url)
                askToOpenExternally(url)
            }
            return
        }
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard !disposed else { return }
        blockedMainFrameNavigation = false
        blockedMainFrameHost = nil
        errorMessage = nil
        needsReload = false
        if webView === self.webView {
            observerDocumentID = nil
            observerStatus = adapter == nil ? .unavailable : .loading
        }
        synchronizeState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !disposed else { return }
        synchronizeState()
        if webView === self.webView { rememberVisit(webView.url) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error, in: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error, in: webView)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !disposed else { return }
        if webView === self.webView {
            stopObserver()
            observerStatus = adapter == nil ? .unavailable : .failed
        }
        if webView === displayedWebView {
            needsReload = true
            errorMessage = "Web content stopped to free memory. Reload to continue."
            synchronizeState()
        }
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                          ? .performDefaultHandling : .rejectProtectionSpace, nil)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { attach(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { attach(download) }
}

extension BrowserSession: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard !disposed, !suspended, !clearingWebsiteData,
              navigationAction.targetFrame == nil, popupWebView == nil,
              let source = navigationAction.sourceFrame.request.url,
              BrowserNavigationPolicy.allowsInWeb(source), let url = navigationAction.request.url else { return nil }
        guard BrowserNavigationPolicy.allowsInWeb(url) || url.absoluteString == "about:blank" else {
            askToOpenExternally(url)
            return nil
        }
        // Preserve WebKit's supplied configuration, rejecting any mismatched account store before use.
        let parentStore = self.webView.configuration.websiteDataStore
        guard configuration.websiteDataStore.identifier == accountID, parentStore.identifier == accountID else { return nil }
        configuration.websiteDataStore = parentStore
        let popup = WKWebView(frame: .zero, configuration: configuration)
        configure(popup)
        popupWebView = popup
        popupObservations = observe(popup)
        synchronizeState()
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === popupWebView { closePopup() }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        showJavaScriptDialog(message: message, frame: frame, isConfirmation: false) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        showJavaScriptDialog(message: message, frame: frame, isConfirmation: true, completion: completionHandler)
    }

    private func showJavaScriptDialog(message: String, frame: WKFrameInfo, isConfirmation: Bool,
                                      completion: @escaping (Bool) -> Void) {
        guard !disposed, !suspended, javaScriptDialog == nil, frame.isMainFrame,
              let url = frame.request.url, BrowserNavigationPolicy.allowsInWeb(url) else { completion(false); return }
        javaScriptDialog = BrowserJavaScriptDialog(host: url.host ?? "Website", message: String(message.prefix(2000)),
                                                   isConfirmation: isConfirmation, completion: completion)
    }
}

extension BrowserSession: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !disposed, !suspended, !clearingWebsiteData, detectionEnabled,
              UIApplication.shared.applicationState == .active,
              message.name == Self.handlerName, message.world.name == Self.observerWorld.name,
              message.webView === webView,
              let adapter, let currentURL = webView.url, URLPolicy.isMuse(currentURL),
              currentURL.host?.lowercased() == URL(string: adapter.origin)?.host?.lowercased(),
              BrowserObserverMessage.hasTrustedOrigin(message.frameInfo.request.url,
                protocol: message.frameInfo.securityOrigin.protocol, host: message.frameInfo.securityOrigin.host,
                port: message.frameInfo.securityOrigin.port, expectedOrigin: adapter.origin,
                isMainFrame: message.frameInfo.isMainFrame),
              let payload = BrowserObserverMessage.decode(message.body) else { return }
        switch payload.kind {
        case "ready":
            observerDocumentID = payload.documentID
            observerStatus = .observing
            lastCheckedAt = Date()
        case "unavailable":
            observerDocumentID = nil
            observerStatus = .failed
        case "completed":
            guard observerStatus == .observing, payload.documentID == observerDocumentID,
                  let itemID = payload.itemID, let rawURL = payload.conversationURL,
                  let url = URLPolicy.safeConversation(URL(string: rawURL)),
                  url.host?.lowercased() == currentURL.host?.lowercased(),
                  BrowserNavigationPolicy.visitURL(currentURL) == url else { return }
            let eventID = adapter.eventID(itemID: itemID, conversationURL: url)
            guard receivedEventIDs.count < 2000 else {
                stopObserver()
                observerStatus = .failed
                return
            }
            guard receivedEventIDs.insert(eventID).inserted else { return }
            lastCheckedAt = Date()
            notifications.receive(accountID: accountID, type: .completed, preview: nil,
                                  conversationURL: url, eventID: eventID)
        default: break
        }
    }
}

extension BrowserSession: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let key = ObjectIdentifier(download)
        guard downloads[key] != nil, !disposed, !suspended, let url = response.url,
              BrowserNavigationPolicy.allowsInWeb(url) || BrowserNavigationPolicy.allowsBlobDownload(url) else {
            completionHandler(nil)
            return
        }
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MuseFleet-downloads", isDirectory: true)
                .appendingPathComponent(accountID.uuidString, isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.complete])
            let destination = directory.appendingPathComponent(BrowserNavigationPolicy.safeFilename(suggestedFilename))
            downloads[key]?.destination = destination
            completionHandler(destination)
        } catch {
            errorMessage = "The download could not be saved. Check available storage and retry."
            completionHandler(nil)
        }
    }

    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                  decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
        guard !disposed, !suspended, !clearingWebsiteData,
              let url = request.url, BrowserNavigationPolicy.allowsInWeb(url) else {
            decisionHandler(.cancel)
            errorMessage = "This download redirected outside verified Muse hosts. Open its link in your browser to continue."
            if let url = request.url { askToOpenExternally(url) }
            return
        }
        decisionHandler(.allow)
    }

    func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                          ? .performDefaultHandling : .rejectProtectionSpace, nil)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let record = downloads.removeValue(forKey: ObjectIdentifier(download)),
              let destination = record.destination, FileManager.default.fileExists(atPath: destination.path) else { return }
        downloadedFile = destination
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let destination = downloads.removeValue(forKey: ObjectIdentifier(download))?.destination {
            try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
        }
        guard !disposed else { return }
        errorMessage = "The download did not finish. Retry from the page."
    }
}

struct BrowserJavaScriptDialog: Identifiable {
    let id = UUID()
    let host: String
    let message: String
    let isConfirmation: Bool
    let completion: (Bool) -> Void
}
