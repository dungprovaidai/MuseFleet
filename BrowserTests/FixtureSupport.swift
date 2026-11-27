import Network
import UIKit
import WebKit
import XCTest
@testable import MuseFleet

enum BrowserFixture {
    static func url(_ name: String, extension ext: String) throws -> URL {
        let bundle = Bundle(for: BrowserObserverFixtureTests.self)
        return try XCTUnwrap(bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: ext))
    }

    static func html(_ name: String) throws -> String {
        try String(contentsOf: url(name, extension: "html"), encoding: .utf8)
    }

    static func observerSource() throws -> String {
        let bundle = Bundle(for: BrowserObserverFixtureTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "CompletionObserver", withExtension: "js")
            ?? Bundle.main.url(forResource: "CompletionObserver", withExtension: "js"))
        return try String(contentsOf: url, encoding: .utf8)
    }
}

@MainActor
final class FixturePage: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var webView: WKWebView?
    var messages: [BrowserObserverMessage] = []
    private var navigationCompletion: ((Error?) -> Void)?
    private var messageWaiter: (String, XCTestExpectation)?
    private var window: UIWindow?
    private weak var previousKeyWindow: UIWindow?
    let contentWorld = WKContentWorld.world(name: "MuseFleet.Fixture.Observer")

    init(accountID: UUID, receivesObserverMessages: Bool = false) {
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: accountID)
        if receivesObserverMessages {
            configuration.userContentController.add(WeakBrowserScriptHandler(target: self),
                contentWorld: contentWorld, name: "museFleetObserver")
        }
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        view.navigationDelegate = self
        webView = view
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
            let window = UIWindow(windowScene: scene)
            let controller = UIViewController()
            controller.view = view
            window.rootViewController = controller
            self.window = window
            window.makeKeyAndVisible()
        }
    }

    func load(_ request: URLRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigationCompletion = { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
            webView?.load(request)
        }
    }

    func loadHTML(_ html: String, baseURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigationCompletion = { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
            // This is test-owned HTML with a synthetic HTTPS base, never a request to the Muse service.
            webView?.loadHTMLString(html, baseURL: baseURL)
        }
    }

    @discardableResult
    func evaluate(_ source: String, isolated: Bool = false) async throws -> Any {
        let view = try XCTUnwrap(webView)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any, Error>) in
            view.evaluateJavaScript(source, in: nil, in: isolated ? contentWorld : .page) { result in
                continuation.resume(with: result)
            }
        }
    }

    func expectMessage(_ kind: String, test: XCTestCase) -> XCTestExpectation {
        let expectation = test.expectation(description: "Fixture observer: \(kind)")
        messageWaiter = (kind, expectation)
        return expectation
    }

    func close() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "museFleetObserver", contentWorld: contentWorld)
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        webView = nil
        previousKeyWindow?.makeKey()
    }

    private func finishNavigation(_ error: Error?) {
        let completion = navigationCompletion
        navigationCompletion = nil
        completion?(error)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishNavigation(nil) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishNavigation(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishNavigation(error) }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let payload = BrowserObserverMessage.decode(message.body) else { return }
        messages.append(payload)
        if messageWaiter?.0 == payload.kind {
            messageWaiter?.1.fulfill()
            messageWaiter = nil
        }
    }
}

// Real loopback HTTP makes the storage tests exercise an actual origin and WebKit's persistent stores.
@MainActor
final class LocalFixtureServer {
    private let listener: NWListener
    private let body: Data
    private var connections: [NWConnection] = []
    private var startContinuation: CheckedContinuation<URL, Error>?

    init(html: String) throws {
        body = Data(html.utf8)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in self?.stateChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in self?.serve(connection) }
            }
            listener.start(queue: .main)
        }
    }

    func stop() {
        listener.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func stateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)/storage") {
                startContinuation?.resume(returning: url)
                startContinuation = nil
            }
        case .failed(let error):
            startContinuation?.resume(throwing: error)
            startContinuation = nil
        default: break
        }
    }

    private func serve(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        receiveRequest(connection, accumulated: Data())
    }

    private func receiveRequest(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                var request = accumulated
                if let data { request.append(data) }
                guard request.count <= 16384, error == nil else { connection.cancel(); return }
                if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                    let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(self.body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
                    var response = Data(headers.utf8)
                    response.append(self.body)
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                } else if complete {
                    connection.cancel()
                } else {
                    self.receiveRequest(connection, accumulated: request)
                }
            }
        }
    }
}
