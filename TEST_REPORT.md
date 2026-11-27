# Test report

Date: 2026-11-28. Local environment: Windows with Python, Node, Git and authenticated GitHub CLI; no local Apple tools or physical iPhone. Apple execution evidence below comes from authorized standard public GitHub Actions runners.

## Evidence so far

| Check | Status | Evidence / meaning |
|---|---|---|
| Official Muse home/login form | VERIFIED public HTTP response | Research notes; no credentials submitted |
| Original app icon | PASS local generator check | 1024×1024 RGB PNG, no alpha |
| IPA pipeline Python tests | PASS, 28 tests on Windows | ZIP/Mach-O/plist rejection fixtures, signing fail-closed/prefix/extraction regressions, input validation, project generation and cost guards; no Apple binaries built locally |
| Observer JavaScript tests | PASS, 9 Node tests on Windows | Synthetic fixture only: baseline history, explicit lifecycle, no per-token emissions, origin/frame rejection, resume and malformed adapter handling |
| Swift syntax | PASS, tree-sitter parse; simulator compile also passed | The compile is real Xcode evidence; tree-sitter alone cannot resolve Apple APIs or types |
| Hosted unit tests | PASS: 30 passed, one skipped, zero failures | Run 46061676530 at ed45ea3; XCTest reports 31 total. Includes core, browser and notification policy tests |
| WebKit isolation PoC | PASS on simulator with local fixture | Two named stores isolate cookie/local storage, retain it across WebView recreation and delete only the chosen store; no live Muse accounts |
| Foreground notification observer PoC | PASS on simulator with synthetic markup | Baseline history, streaming completion once, deduplication and page-world separation; does not establish production Muse selectors |
| Local notification scheduling PoC | SKIPPED on simulator | System permission was not granted; no native delivery success is inferred |
| XCUITest UI smoke | FAILED; corrected retry RUNNING | Latest completed run rejected an unsupported `isHittable` query predicate before profile creation; run 46063990154 uses direct resolved-element checks |
| iOS simulator application/test bundles | PASS compile | Xcode 26.3 / iOS Simulator 26.2 on iPhone SE (3rd generation); iOS 17 runtime remains untested |
| arm64 device build / archive / IPA | NOT REACHED | UI test failure prevented the packaging step; no IPA exists yet |
| Two real Muse accounts | BLOCKED | User-controlled iPhone login needed |
| Background / locked / force quit delivery | BLOCKED | No verified production event source, Apple device or APNs setup |
| Signed IPA / remote push | BLOCKED | No supplied signing credentials or upstream source |

Written tests are not passed tests. Synthetic fixture data is limited to tests and never seeded into the production app. A scheduled local request is not evidence of an arriving Muse notification or physical-device APNs delivery.

## Actions evidence

- [46059671694](https://github.com/dungprovaidai/MuseFleet/actions/runs/46059671694), source `2db9744`: 31 unit tests, one skipped, zero failures; UI smoke failed on a noninteractive tab match. Device build and IPA upload skipped.
- [46061676530](https://github.com/dungprovaidai/MuseFleet/actions/runs/46061676530), source `ed45ea3`: same unit result; UI smoke failed with `Invalid key path isHittable specified in predicate format string (XCTElementQueryInvalidPredicate)`. Logs and `.xcresult` artifacts were downloaded; no complete UI flow or Settings screenshot was verified.
- [46063990154](https://github.com/dungprovaidai/MuseFleet/actions/runs/46063990154), source `2147858`: retry running. The test queries system tab labels, evaluates `.isHittable` on resolved elements and requires a unique interactive button. Failure diagnostics retain the accessibility hierarchy; the workflow also exports failed test attachments. Tests still gate IPA creation.

## Physical iPhone checklist

Record device model, iOS version, build SHA, installation method and signing method. Use account aliases in reports and never attach tokens, OTPs or private chat screenshots.

1. **Install:** verify IPA SHA-256, signing method and provisioning eligibility. Launch; inspect four tabs and empty states in light/dark modes.
2. **Account A:** add a profile; complete the official Muse login yourself. Send a harmless distinguishable message. Record the displayed account alias.
3. **Account B:** add a second UUID; confirm it starts logged out. Log into another Muse account. Confirm A's message/history is absent from B.
4. **Isolation:** alternate A/B rapidly; verify identities/history independently. Rename A, reorder and favorite profiles. Restart the app and verify both sessions within Muse's expiry rules.
5. **Deletion:** delete A with website-data removal enabled. Verify B's session/history persists. Re-create a profile with a new UUID and confirm A's session is not inherited. Test metadata-only deletion separately on disposable accounts.
6. **Browser:** back/forward, reload/stop, restored safe URL, keyboard, selection/copy, image/document upload, document download/share, external HTTPS links and approved login popups. Test download cancellation, duplicate filename, offline/retry and server TLS failure handling.
7. **Memory:** open enough disposable profiles to evict old WebViews; verify storage persists. Simulate web-content termination/memory pressure with Xcode, recover safely and confirm observer history is not replayed.
8. **App lock:** enable through successful device-owner authentication. Background/lock/reopen; verify curtain in App Switcher, no access before unlock, cancellation remains locked and passcode fallback works. Try changing lock state with cancellation. Tap a native notification while locked and confirm routing waits.
9. **Permission:** deny notifications, then enable in Settings. Known valid events should still reach Inbox when native permission is denied. Check badges, preview hidden/shown, sound, haptics, quiet-hours boundaries and Focus interactions.
10. **Observer:** only after a reviewed real Muse adapter exists, baseline old history, send a new user message, stream an assistant response and verify one response event at the correct completion transition. Separately verify task complete/failure, approval, question, artifact, important progress and session expiry. Test side chats and concurrent tasks. Website markup changes must show detection unavailable.
11. **Other account:** keep A loaded, switch to B and obtain an actual A response. Verify event/account identity and document whether A was retained in RAM. Evicted profiles must not claim active observation.
12. **Routing:** tap events for A and B, safe conversation URL and missing URL; mark read and update badge. Delete a profile before tapping an old notification. Foreign origins and malformed IDs must never open an unsafe in-app route.
13. **Background:** repeat an actual upstream-driven event while backgrounded, screen locked and app force quit. Record trigger/arrival/tap results separately. Without a verified upstream these tests remain BLOCKED, not PASS.
14. **Accessibility:** largest Dynamic Type, VoiceOver labels/actions, contrast, safe areas, landscape and iPad layout if distributed for iPad.
15. **Cleanup:** remove disposable profiles, website data, test downloads and delivered TEST ONLY notifications. No sensitive screenshots are saved by default.

## Required delivery evidence

A successful complete macOS Actions run, exact commit, passing UI `.xcresult`, actual simulator screenshot files, IPA validation JSON, SHA-256 and signing status must be added after execution. Failed runs already produced `.xcresult` artifacts, but no completed IPA or checksum has been verified. Physical-device results remain separate.

## Source review corrections

Review found authentication re-entry after interruptions, a stale activation task resuming browser work after backgrounding, missing foreground sound presentation and pending-notification privacy races. Source now guards an already-unlocked session, rejects stale authentication generations, rechecks active scene state after awaits, honors sound settings, invalidates pending delivery tasks and rejects stale private foreground presentation. A separate privacy window covers native modal presentation; its snapshot/VoiceOver behavior still requires physical-device verification. App-lock changes now authenticate before updating the saved preference.
