# Browser checks

All HTML and completion markers in this directory are synthetic, local fixtures. They are not Muse selectors or evidence that Muse events, login, conversation URLs, remote push, background monitoring, or downloads work on the live service. `BrowserObserverAdapter.muse` is deliberately `nil`; `lastCheckedAt` stays `nil` until an authenticated, verified adapter actually inspects a page. Text changes and streaming silence never imply an asynchronous task completed.

The generic engine emits only an observed in-progress → explicit completed transition, including an item already in progress during the initial baseline. First-seen completed items stay silent, even when appended after startup, because they may be lazily loaded history. Terminal-only insert notifications would need a separately verified site cursor or equivalent evidence. Resuming, replacing a conversation container, or changing routes establishes a fresh baseline.

Run the engine state-machine checks anywhere with Node 18+:

```text
node --test BrowserTests/observer-engine.test.cjs
```

The XCTest files require a hosted iOS 17+ test target, `@testable import MuseFleet`, and a real WebKit runtime. Add `BrowserTests/**/*.swift` to the test target, `BrowserTests/Fixtures/*.html` to its resources, and `App/Browser/CompletionObserver.js` to the application's Copy Bundle Resources phase (optionally also the test bundle). The fixture loader handles flattened resources and a `Fixtures` folder. Loopback HTTP is used only by the storage test; if the test host's ATS configuration blocks it, permit local networking in the test host, not broad HTTP access in production navigation policy.

The WebKit tests cover separate named persistent stores, re-opening their fixture cookie/local-storage data, identifier deletion, preservation of the other account, LRU eviction, deletion races/failure metadata preservation, isolated script handler visibility, initial history baselines, and streaming completion de-duplication. Persistence here means closing/recreating WebViews; force-quit/relaunch and physical-device disk durability still need an Apple run.

Browser integration additions:

- `BrowserSession` conforms to the real `NotificationProvider` protocol and exposes `.foregroundWeb`, blocked capability, and truthful `lastCheckedAt`.
- `isAvailable` / `availableWebView` protect toolbar access during eviction/deletion. The required nonoptional `webView` is valid only for an available session. `BrowserWebView(session:)` handles unavailable sessions and releases its hosted view synchronously during deletion.
- `displayedWebView` returns the active popup or main WebView, so optional back/forward toolbar actions can target the visible page. Native popup close and process-termination reload controls are supplied by `BrowserWebView`.
- `pendingExternalURL`, `confirmExternalOpen()`, and `cancelExternalOpen()` drive an explicit confirmation inside `BrowserWebView` before `UIApplication.open`; unknown HTTPS hosts never enter an account WebView. Only Muse hosts in the shared `URLPolicy` are allowed in-web; no third-party login hosts are verified yet. Custom schemes are confirmed as app handoffs, never loaded in WebKit.
- `downloadedFile` is a completed, protected temporary file for the owning UI's `ShareLink` or activity sheet. Downloads use `WKDownload` and that account's WebKit session; no cookie extraction or separate URLSession download exists. CDN redirects outside verified Muse hosts fail closed and can be opened externally after confirmation.
- `clearWebsiteData(accountID:)` evicts pages, blocks replacement WebViews while `WKWebsiteDataStore.remove(forIdentifier:)` runs, propagates errors, and clears only visit metadata on success. The caller deletes account metadata only after awaiting success. `remove(accountID:)` / `keepOnly` preserve persistent stores. A `removeWebsiteData` initializer closure exists only to exercise the failure/race test.

Any UI that hosts `popupWebView` in its own sheet must dismiss it and release its strong `WKWebView` reference before identifier deletion. The browser releases its own views and inline host synchronously, but cannot release references owned by another view. Apple's API may throw while such a reference remains; account metadata is preserved so the user can close that window and retry.

Native `<input type=file>` upload is left to WebKit's system picker on iOS 17. There is no UA override, credential/OTP/input collection, generic body-text observer, or production fixture adapter. Sign-in popups use WebKit's supplied configuration pinned to the exact parent store. JavaScript text prompts retain WebKit's cancellation default rather than introducing a native credential field.

Pending Apple execution: build/type-check, all XCTest cases, native file picker, popup OAuth/OTP/WebAuthn behavior, process termination recovery, download/share behavior, real device memory/background transitions, and authenticated Muse flows. Windows has no Xcode or Swift SDK, so written XCTest coverage must not be reported as passed.
