import CryptoKit
import Foundation
import WebKit

enum ObserverStatus: String {
    case unavailable = "Detection unavailable — Muse markup is not verified"
    case suspended = "Detection paused while inactive"
    case loading = "Waiting for verified page markers"
    case observing = "Observing this loaded page in the foreground"
    case failed = "Detection unavailable on this page"
}

struct BrowserObserverAdapter: Encodable {
    let id: String
    let origin: String
    let containerSelector: String
    let itemSelector: String
    let idAttribute: String
    let stateAttribute: String
    let streamingValue: String
    let completedValue: String

    // Fixture selectors live in BrowserTests. No authenticated Muse markup has been inspected.
    static let muse: BrowserObserverAdapter? = nil

    func source(engine: String) throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return "\(engine)\n;globalThis.MuseFleetObserver = globalThis.MuseFleetObserverEngine.install(\(json)); void 0;"
    }

    func eventID(itemID: String, conversationURL: URL) -> String {
        let routeHash = SHA256.hash(data: Data(conversationURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "\(id):\(routeHash):\(itemID):completed"
    }
}

struct BrowserObserverMessage: Decodable {
    let version: Int
    let kind: String
    let documentID: String
    let itemID: String?
    let conversationURL: String?

    static let maximumBytes = 4096

    static func decode(_ body: Any) -> BrowserObserverMessage? {
        guard let string = body as? String, string.utf8.count <= maximumBytes,
              let data = string.data(using: .utf8),
              let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              Set(fields.keys).isSubset(of: ["version", "kind", "documentID", "itemID", "conversationURL"]),
              let message = try? JSONDecoder().decode(Self.self, from: data),
              message.version == 1, UUID(uuidString: message.documentID) != nil else { return nil }
        switch message.kind {
        case "ready", "unavailable":
            guard message.itemID == nil, message.conversationURL == nil else { return nil }
        case "completed":
            guard let itemID = message.itemID, !itemID.isEmpty, itemID.utf8.count <= 128,
                  itemID.unicodeScalars.allSatisfy({
                      CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.").contains($0)
                  }), let rawURL = message.conversationURL, rawURL.utf8.count <= 2048 else { return nil }
        default:
            return nil
        }
        return message
    }

    static func hasTrustedOrigin(_ url: URL?, protocol scheme: String, host: String, port: Int,
                                 expectedOrigin: String, isMainFrame: Bool) -> Bool {
        guard isMainFrame, scheme == "https", port == 0 || port == 443,
              let url, URLPolicy.isMuse(url),
              let origin = URL(string: expectedOrigin), URLPolicy.isMuse(origin),
              host.lowercased() == origin.host?.lowercased(),
              url.host?.lowercased() == origin.host?.lowercased() else { return false }
        return true
    }
}

@MainActor
final class WeakBrowserScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(target: any WKScriptMessageHandler) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
