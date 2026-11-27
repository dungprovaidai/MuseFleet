import XCTest
@testable import MuseFleet

final class BrowserPolicyTests: XCTestCase {
    func testOnlyExactHTTPSMuseHostsStayInWeb() {
        XCTAssertTrue(BrowserNavigationPolicy.allowsInWeb(URL(string: "https://muse.ai/")!))
        for value in ["http://muse.ai/", "https://muse.ai.attacker.test/", "https://attacker.test/?muse.ai",
                      "https://muse.ai:8443/", "https://user:secret@muse.ai/", "https://accounts.google.com/"] {
            XCTAssertFalse(BrowserNavigationPolicy.allowsInWeb(URL(string: value)!), value)
        }
        XCTAssertTrue(BrowserNavigationPolicy.verifiedLoginHosts.isEmpty)
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

    func testVisitPersistenceOmitsQueryAndNeverStoresAuthenticationCallbacks() {
        XCTAssertEqual(BrowserNavigationPolicy.visitURL(URL(string: "https://muse.ai/fixture?view=1"))?.absoluteString,
                       "https://muse.ai/fixture")
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
