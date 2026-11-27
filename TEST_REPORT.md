# Test report

Date: 2026-11-28. Environment: Windows; Python, Node, Git and authenticated GitHub CLI available. Swift compiler, Xcode, iOS Simulator and physical iPhone unavailable locally.

## Evidence so far

| Check | Status | Evidence / meaning |
|---|---|---|
| Official Muse home/login form | VERIFIED public HTTP response | Research notes; no credentials submitted |
| Original app icon | PASS local generator check | 1024×1024 RGB PNG, no alpha |
| IPA pipeline Python tests | PASS, 28 tests on Windows | ZIP/Mach-O/plist rejection fixtures, signing fail-closed/prefix/extraction regressions, input validation, project generation and cost guards; no Apple binaries built locally |
| Observer JavaScript tests | PASS, 9 Node tests on Windows | Synthetic fixture only: baseline history, explicit lifecycle, no per-token emissions, origin/frame rejection, resume and malformed adapter handling |
| Swift syntax | PASS, tree-sitter parse of 31 files | Syntax only; cannot resolve Apple APIs, actor isolation or types |
| Core Swift tests | WRITTEN, NOT RUN | Persistence, deletion, deduplication, denial, safe routes, quiet hours, corruption preservation |
| WebKit isolation PoC | PENDING Apple execution | Uses synthetic local website state, not live Muse accounts |
| Foreground notification observer PoC | PENDING fixture execution | Does not establish production Muse selectors |
| Local notification scheduling PoC | WRITTEN, NOT RUN | Requires granted system permission; otherwise explicit skip |
| XCUITest UI smoke | WRITTEN, NOT RUN | Tabs, profile creation, restart persistence, simulator screenshot attachment |
| iOS build / archive / IPA | IN PROGRESS | First authorized standard public Actions run: https://github.com/dungprovaidai/MuseFleet/actions/runs/46052949212 at f05a5d4 |
| Two real Muse accounts | BLOCKED | User-controlled iPhone login needed |
| Background / locked / force quit delivery | BLOCKED | No verified production event source, Apple device or APNs setup |
| Signed IPA / remote push | BLOCKED | No supplied signing credentials or upstream source |

Written tests are not passed tests. Synthetic fixture data is limited to tests and never seeded into the production app. A scheduled local request is not evidence of an arriving Muse notification or physical-device APNs delivery.

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

A successful macOS Actions URL, exact commit, xcresult artifacts, actual simulator screenshot files, IPA validation JSON, SHA-256 and signing status must be added after execution. Physical-device results remain separate. No current entry claims those artifacts exist.

## Source review corrections

Review found authentication re-entry after interruptions, a stale activation task resuming browser work after backgrounding, missing foreground sound presentation and pending-notification privacy races. Source now guards an already-unlocked session, rejects stale authentication generations, rechecks active scene state after awaits, honors sound settings, invalidates pending delivery tasks and rejects stale private foreground presentation. A separate privacy window covers native modal presentation; its snapshot/VoiceOver behavior still requires physical-device verification. App-lock changes now authenticate before updating the saved preference.
