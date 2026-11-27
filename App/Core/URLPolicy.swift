import Foundation

enum URLPolicy {
    static let home = URL(string: "https://muse.ai/")!
    private static let museHosts: Set<String> = ["muse.ai", "www.muse.ai"]

    static func isMuse(_ url: URL) -> Bool {
        isHTTPS(url) && museHosts.contains(url.host?.lowercased() ?? "")
    }

    static func safeConversation(_ url: URL?) -> URL? {
        guard let url, isMuse(url), url.absoluteString.utf8.count <= 4096 else { return nil }
        // shortcut: query-based chat links need a verified format before we can persist them without risking auth callback data.
        guard url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    static func isSafeExternal(_ url: URL) -> Bool { isHTTPS(url) }

    private static func isHTTPS(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == "https" && components.host != nil &&
            components.user == nil && components.password == nil &&
            (components.port == nil || components.port == 443)
    }
}
