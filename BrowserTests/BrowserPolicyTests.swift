import XCTest
@testable import MuseFleet

final class BrowserPolicyTests: XCTestCase {
    func testNavigationFailureShowsSafeCodeAndKeepsTLSChecksEnabled() throws {
        let secure = BrowserNavigationFailure.message(domain: NSURLErrorDomain,
                                                       code: NSURLErrorServerCertificateUntrusted)
        XCTAssertTrue(secure.contains("network error -1202"))
        XCTAssertTrue(secure.contains("Certificate checks remain enabled"))
        XCTAssertFalse(secure.contains("https://"))

        XCTAssertTrue(BrowserNavigationFailure.message(domain: NSURLErrorDomain,
                                                       code: NSURLErrorCannotFindHost).contains("DNS"))
        XCTAssertTrue(BrowserNavigationFailure.message(domain: "WebKitErrorDomain", code: 4)
            .contains("WebKit error 4"))
        let interrupted = BrowserNavigationFailure.message(domain: "WebKitErrorDomain", code: 102)
        XCTAssertTrue(interrupted.contains("redirect or download"))
        XCTAssertFalse(interrupted.contains("verified Muse host list"))
        let destination = URL(string: "https://auth.meta.com/oidc?code=fixture-secret")!
        let blockedHost = try XCTUnwrap(BrowserNavigationPolicy.displayHost(destination))
        let blocked = BrowserNavigationFailure.message(domain: "WebKitErrorDomain", code: 102,
                                                       policyBlocked: true, blockedHost: blockedHost)
        XCTAssertTrue(blocked.contains("verified Muse/auth host list"))
        XCTAssertTrue(blocked.contains("auth.meta.com"))
        XCTAssertFalse(blocked.contains("fixture-secret"))
        XCTAssertFalse(blocked.contains("/oidc"))
    }

    func testOnlyExactHTTPSMuseHostsStayInWeb() {
        XCTAssertTrue(BrowserNavigationPolicy.allowsInWeb(URL(string: "https://muse.ai/")!))
        XCTAssertTrue(BrowserNavigationPolicy.allowsInWeb(URL(string: "https://www.muse.ai/")!))
        XCTAssertTrue(BrowserNavigationPolicy.allowsInWeb(URL(string: "https://auth.meta.com/oidc")!))
        XCTAssertTrue(BrowserNavigationPolicy.allowsInWeb(URL(string: "https://auth.muse.ai/")!))
        XCTAssertTrue(BrowserNavigationPolicy.allowsInWeb(URL(string: "https://www.facebook.com/auth_platform/continue")!))
        XCTAssertTrue(BrowserNavigationPolicy.allowsInWeb(URL(string: "https://www.instagram.com/auth_platform/continue")!))
        for value in ["http://muse.ai/", "https://muse.ai.attacker.test/", "https://attacker.test/?muse.ai",
                      "https://muse.ai:8443/", "https://user:secret@muse.ai/", "https://accounts.google.com/",
                      "https://auth.meta.com.attacker.test/oidc", "http://auth.meta.com/oidc",
                      "https://auth.meta.com:8443/oidc", "https://accountscenter.meta.com/auth_platform/",
                      "https://auth.muse.ai.attacker.test/", "http://auth.muse.ai/",
                      "https://auth.muse.ai:8443/", "https://user:secret@auth.muse.ai/",
                      "https://www.facebook.com/profile.php", "https://m.facebook.com/auth_platform/continue"] {
            XCTAssertFalse(BrowserNavigationPolicy.allowsInWeb(URL(string: value)!), value)
        }
        XCTAssertEqual(BrowserNavigationPolicy.verifiedLoginHosts,
                       ["auth.meta.com", "auth.muse.ai", "www.facebook.com", "www.instagram.com"])
        XCTAssertEqual(BrowserNavigationPolicy.displayHost(URL(string: "https://auth.meta.com/oidc?code=secret")),
                       "auth.meta.com")
        XCTAssertNil(BrowserNavigationPolicy.displayHost(URL(string: "data:text/html,secret")))
    }

    func testExternalNavigationCanOnlyBeRequestedForSecureWebsitesOrAppHandoffs() {
        for value in ["https://example.com/", "mailto:test@example.com", "tel:123", "exampleapp://continue"] {
            XCTAssertTrue(BrowserNavigationPolicy.canAskToOpenExternally(URL(string: value)!))
        }
        for value in ["javascript:alert(1)", "data:text/html,hi", "file:///tmp/private", "http://example.com/",
                      "https://user:secret@example.com/", "https://example.com:8443/", "about:blank"] {
            XCTAssertFalse(BrowserNavigationPolicy.canAskToOpenExternally(URL(string: value)!))
        }
    }

    func testBlobDownloadsMustEmbedAnExactMuseHTTPSOrigin() {
        XCTAssertTrue(BrowserNavigationPolicy.allowsBlobDownload(URL(string: "blob:https://muse.ai/fixture")!))
        XCTAssertFalse(BrowserNavigationPolicy.allowsBlobDownload(URL(string: "blob:https://muse.ai.attacker.test/fixture")!))
        XCTAssertFalse(BrowserNavigationPolicy.allowsBlobDownload(URL(string: "blob:http://muse.ai/fixture")!))
        XCTAssertFalse(BrowserNavigationPolicy.allowsBlobDownload(URL(string: "blob:null/fixture")!))
    }

    func testVisitPersistenceRejectsQueriesAndAuthenticationCallbacks() {
        XCTAssertNil(BrowserNavigationPolicy.visitURL(URL(string: "https://muse.ai/fixture?view=1")))
        XCTAssertNil(BrowserNavigationPolicy.visitURL(URL(string: "https://muse.ai/?code=fixture")))
        XCTAssertNil(BrowserNavigationPolicy.visitURL(URL(string: "https://muse.ai/#fixture")))
        XCTAssertNil(BrowserNavigationPolicy.visitURL(URL(string: "https://muse.ai/auth/callback/fixture")))
        XCTAssertNil(BrowserNavigationPolicy.visitURL(URL(string: "https://example.com/")))
    }

    func testDownloadFilenamesCannotEscapeTheirUniqueDirectory() {
        XCTAssertEqual(BrowserNavigationPolicy.safeFilename("../../fixture.txt"), "fixture.txt")
        XCTAssertEqual(BrowserNavigationPolicy.safeFilename("..\\..\\fixture.txt"), "fixture.txt")
        XCTAssertEqual(BrowserNavigationPolicy.safeFilename(".."), "Download")
        XCTAssertEqual(BrowserNavigationPolicy.safeFilename("\n"), "Download")
        XCTAssertLessThanOrEqual(BrowserNavigationPolicy.safeFilename(String(repeating: "a", count: 300)).count, 120)
    }

    func testObserverTrustBoundaryRejectsSubframesLookalikesAndNonHTTPS() {
        func trusted(_ url: String, scheme: String = "https", host: String = "muse.ai",
                     port: Int = 443, main: Bool = true) -> Bool {
            BrowserObserverMessage.hasTrustedOrigin(URL(string: url), protocol: scheme, host: host,
                port: port, expectedOrigin: "https://muse.ai", isMainFrame: main)
        }
        XCTAssertTrue(trusted("https://muse.ai/fixture"))
        XCTAssertTrue(trusted("https://muse.ai/fixture", port: 0))
        XCTAssertFalse(trusted("https://muse.ai/fixture", main: false))
        XCTAssertFalse(trusted("http://muse.ai/fixture", scheme: "http"))
        XCTAssertFalse(trusted("https://muse.ai.attacker.test/fixture", host: "muse.ai.attacker.test"))
        XCTAssertFalse(trusted("https://muse.ai/fixture", port: 8443))
    }

    func testObserverMessageLimitsAndNoProductionAdapter() {
        let doc = UUID().uuidString
        let valid = "{\"version\":1,\"kind\":\"completed\",\"documentID\":\"\(doc)\",\"itemID\":\"fixture-1\",\"conversationURL\":\"https://muse.ai/fixture\"}"
        XCTAssertNotNil(BrowserObserverMessage.decode(valid))
        XCTAssertNil(BrowserObserverMessage.decode(String(repeating: "x", count: 4097)))
        XCTAssertNil(BrowserObserverMessage.decode(["kind": "completed"]))
        XCTAssertNil(BrowserObserverMessage.decode(valid.replacingOccurrences(of: "fixture-1", with: "bad/item")))
        XCTAssertNil(BrowserObserverMessage.decode(valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")))
        XCTAssertNil(BrowserObserverMessage.decode(valid.dropLast() + ",\"preview\":\"unexpected\"}"))
        XCTAssertNil(BrowserObserverAdapter.muse)
    }
}
