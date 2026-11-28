import Foundation

enum BrowserNavigationPolicy {
    // The public Muse page uses first-party login. Add other hosts only after verifying a real login flow.
    static let verifiedLoginHosts: Set<String> = []

    static func allowsInWeb(_ url: URL) -> Bool {
        URLPolicy.isMuse(url) || (URLPolicy.isSafeExternal(url) &&
            verifiedLoginHosts.contains(url.host?.lowercased() ?? ""))
    }

    static func allowsBlobDownload(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "blob",
              let origin = URL(string: String(url.absoluteString.dropFirst(5))) else { return false }
        return URLPolicy.isMuse(origin)
    }

    static func canAskToOpenExternally(_ url: URL) -> Bool {
        guard url.absoluteString.utf8.count <= 4096,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil,
              let scheme = parts.scheme?.lowercased() else { return false }
        if scheme == "https" { return URLPolicy.isSafeExternal(url) }
        // App handoffs require the same explicit confirmation; executable/local URL schemes are blocked.
        let blocked = ["http", "javascript", "data", "file", "about", "blob", "applewebdata", "webkit", "ftp", "ws", "wss"]
        return !blocked.contains(scheme) &&
            !url.absoluteString.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    static func visitURL(_ url: URL?) -> URL? {
        guard let url, let safe = URLPolicy.safeConversation(url),
              var parts = URLComponents(url: safe, resolvingAgainstBaseURL: false) else { return nil }
        let authenticationSegments: Set<String> = ["auth", "oauth", "oauth2", "login", "signin", "sign-in", "signup", "callback", "authorize"]
        guard !safe.pathComponents.contains(where: { authenticationSegments.contains($0.lowercased()) }) else { return nil }
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }

    static func safeFilename(_ suggested: String) -> String {
        let lastComponent = suggested.replacingOccurrences(of: "\\", with: "/")
            .components(separatedBy: "/").last ?? ""
        let cleaned = lastComponent.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && $0 != ":"
        }.map(String.init).joined()
        let name = String(cleaned.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == "." || name == ".." ? "Download" : name
    }
}

enum BrowserNavigationFailure {
    static func message(domain: String, code: Int, policyBlocked: Bool = false) -> String {
        if domain == "WebKitErrorDomain", code == 102 {
            return policyBlocked
                ? "MuseFleet stopped this redirect because its website isn't on the verified Muse host list. Check for an Open outside prompt; if this happened during sign-in, share only the domain shown, not a link or code."
                : "WebKit interrupted this navigation (code 102), often when a redirect or download takes over. If the page stays blank, retry and share any external site domain shown; never send a sign-in link or code."
        }
        guard domain == NSURLErrorDomain else { return "Web content failed (WebKit error \(code))." }
        switch code {
        case NSURLErrorNotConnectedToInternet:
            return "You appear to be offline (network error \(code)). Check your connection and reload."
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid:
            return "The secure connection could not be verified (network error \(code)). Check device date/time and network filtering. Certificate checks remain enabled."
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return "The page requested an insecure connection (network error \(code)). MuseFleet will not fall back to HTTP."
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return "The Muse server could not be found (network error \(code)). Check DNS, VPN, or network filtering."
        case NSURLErrorCannotConnectToHost, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost:
            return "Muse could not be reached (network error \(code)). Try another network and reload."
        default:
            return "The page could not load (network error \(code)). Try reloading or return to Muse home."
        }
    }
}
