import SwiftUI
import WebKit

@MainActor
struct BrowserWebView: UIViewRepresentable {
    var session: BrowserSession

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    func makeUIView(context: Context) -> BrowserContainerView {
        let view = BrowserContainerView()
        context.coordinator.container = view
        view.onAttached = { [weak coordinator = context.coordinator] in coordinator?.presentPendingDialog() }
        view.onClosePopup = { [weak coordinator = context.coordinator] in coordinator?.session.closePopup() }
        view.onReload = { [weak coordinator = context.coordinator] in coordinator?.session.reload() }
        return view
    }

    func updateUIView(_ view: BrowserContainerView, context: Context) {
        if context.coordinator.session !== session { context.coordinator.dismissPresentation() }
        context.coordinator.session = session
        view.show(session.isAvailable ? session.displayedWebView : nil,
                  popup: session.popupWebView != nil, needsReload: session.needsReload,
                  message: session.errorMessage)
        // Reading pending values here also registers them with SwiftUI's Observation tracking.
        _ = session.pendingExternalURL
        _ = session.javaScriptDialog
        context.coordinator.presentPendingDialog()
    }

    static func dismantleUIView(_ view: BrowserContainerView, coordinator: Coordinator) {
        coordinator.dismissPresentation()
        view.show(nil, popup: false, needsReload: false, message: nil)
    }

    @MainActor
    final class Coordinator: NSObject {
        var session: BrowserSession
        weak var container: BrowserContainerView?
        private weak var alert: UIAlertController?
        private var presentationID: String?

        init(session: BrowserSession) { self.session = session }

        func dismissPresentation() {
            alert?.dismiss(animated: false)
            alert = nil
            presentationID = nil
        }

        func presentPendingDialog() {
            let pendingID = session.pendingExternalURL.map { "external:\($0.absoluteString)" }
                ?? session.javaScriptDialog?.id.uuidString
            guard session.isAvailable, let pendingID else { dismissPresentation(); return }
            if alert != nil {
                if presentationID != pendingID { dismissPresentation() } else { return }
            }
            guard let root = container?.window?.rootViewController else { return }
            var presenter = root
            while let presented = presenter.presentedViewController { presenter = presented }
            guard !presenter.isBeingDismissed, !(presenter is UIAlertController),
                  presenter.viewIfLoaded?.window != nil else { return }
            let controller: UIAlertController
            let currentSession = session
            if let url = session.pendingExternalURL {
                let destination = url.host ?? "\(url.scheme ?? "another") app"
                controller = UIAlertController(title: "Open outside MuseFleet?",
                    message: "Continue in \(destination)? The other app uses its own sign-in session.", preferredStyle: .alert)
                controller.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak currentSession] _ in
                    currentSession?.cancelExternalOpen()
                })
                controller.addAction(UIAlertAction(title: "Open", style: .default) { [weak currentSession] _ in
                    currentSession?.confirmExternalOpen()
                })
            } else if let dialog = session.javaScriptDialog {
                controller = UIAlertController(title: "Message from \(dialog.host)",
                                               message: dialog.message, preferredStyle: .alert)
                if dialog.isConfirmation {
                    controller.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak currentSession] _ in
                        currentSession?.resolveJavaScriptDialog(confirmed: false)
                    })
                }
                controller.addAction(UIAlertAction(title: "OK", style: .default) { [weak currentSession] _ in
                    currentSession?.resolveJavaScriptDialog(confirmed: true)
                })
            } else { return }
            alert = controller
            presentationID = pendingID
            presenter.present(controller, animated: true)
        }
    }
}

@MainActor
final class BrowserContainerView: UIView {
    var onAttached: (() -> Void)?
    var onClosePopup: (() -> Void)?
    var onReload: (() -> Void)?
    private weak var hostedWebView: WKWebView?
    private var webConstraints: [NSLayoutConstraint] = []
    private let popupBar = UIStackView()
    private let recovery = UIStackView()
    private let recoveryLabel = UILabel()
    private let reloadButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        let title = UILabel()
        title.text = "Muse account window"
        title.font = .preferredFont(forTextStyle: .headline)
        title.adjustsFontForContentSizeCategory = true
        let close = UIButton(type: .system)
        close.setTitle("Close", for: .normal)
        close.accessibilityLabel = "Close account window"
        close.addTarget(self, action: #selector(closePopup), for: .touchUpInside)
        popupBar.axis = .horizontal
        popupBar.spacing = 12
        popupBar.isLayoutMarginsRelativeArrangement = true
        popupBar.directionalLayoutMargins = .init(top: 4, leading: 16, bottom: 4, trailing: 16)
        popupBar.addArrangedSubview(title)
        popupBar.addArrangedSubview(close)
        popupBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(popupBar)
        recovery.axis = .vertical
        recovery.spacing = 16
        recovery.alignment = .center
        recoveryLabel.font = .preferredFont(forTextStyle: .body)
        recoveryLabel.adjustsFontForContentSizeCategory = true
        recoveryLabel.textAlignment = .center
        recoveryLabel.numberOfLines = 0
        reloadButton.setTitle("Reload", for: .normal)
        reloadButton.addTarget(self, action: #selector(reload), for: .touchUpInside)
        recovery.addArrangedSubview(recoveryLabel)
        recovery.addArrangedSubview(reloadButton)
        recovery.translatesAutoresizingMaskIntoConstraints = false
        addSubview(recovery)
        NSLayoutConstraint.activate([
            popupBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            popupBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            popupBar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            popupBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            recovery.centerXAnchor.constraint(equalTo: centerXAnchor),
            recovery.centerYAnchor.constraint(equalTo: centerYAnchor),
            recovery.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            recovery.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onAttached?() }
    }

    func show(_ webView: WKWebView?, popup: Bool, needsReload: Bool, message: String?) {
        popupBar.isHidden = !popup
        if hostedWebView !== webView || webConstraints.isEmpty {
            NSLayoutConstraint.deactivate(webConstraints)
            hostedWebView?.removeFromSuperview()
            hostedWebView = webView
            webConstraints = []
            if let webView {
                webView.translatesAutoresizingMaskIntoConstraints = false
                insertSubview(webView, at: 0)
                webConstraints = [
                    webView.leadingAnchor.constraint(equalTo: leadingAnchor),
                    webView.trailingAnchor.constraint(equalTo: trailingAnchor),
                    webView.bottomAnchor.constraint(equalTo: bottomAnchor)
                ]
            }
        }
        // The active view can remain identical while its popup chrome changes.
        if let webView, webConstraints.count >= 3 {
            if webConstraints.count == 4 { webConstraints.removeLast().isActive = false }
            webConstraints.append(webView.topAnchor.constraint(equalTo: popup ? popupBar.bottomAnchor : topAnchor))
            NSLayoutConstraint.activate(webConstraints)
        }
        recovery.isHidden = webView != nil && !needsReload
        reloadButton.isHidden = webView == nil
        recoveryLabel.text = message ?? (webView == nil ? "This account is closing or clearing its website data." : "Reload to continue.")
        webView?.isHidden = needsReload
        bringSubviewToFront(recovery)
        bringSubviewToFront(popupBar)
    }

    @objc private func closePopup() { onClosePopup?() }
    @objc private func reload() { onReload?() }
}
