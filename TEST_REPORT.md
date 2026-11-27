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
| Hosted unit tests | PASS: 31 passed, one skipped, zero failures | Run 46065778744 at 222c8c0; XCTest reports 32 total, including successful isolated Keychain create/read/delete coverage |
| WebKit isolation PoC | PASS on simulator with local fixture | Two named stores isolate cookie/local storage, retain it across WebView recreation and delete only the chosen store; no live Muse accounts |
| Foreground notification observer PoC | PASS on simulator with synthetic markup | Baseline history, streaming completion once, deduplication and page-world separation; does not establish production Muse selectors |
| Local notification scheduling PoC | SKIPPED on simulator | System permission was not granted; no native delivery success is inferred |
| XCUITest UI smoke | PASS: one test, zero failures | Profile creation, persistence after relaunch and Accounts/Inbox/Settings navigation; actual Settings screenshot exported and inspected |
| iOS simulator application/test bundles | PASS compile | Xcode 26.3 / iOS Simulator 26.2 on iPhone SE (3rd generation); iOS 17 runtime remains untested |
| arm64 device build / IPA | PASS, unsigned 0.1.0 (7) | Real 4,135,976-byte arm64 iOS Mach-O executable; minimum iOS 17.0; 1,000,442-byte IPA validated on macOS and structurally revalidated on Windows; no signed archive or installation claimed |
| Two real Muse accounts | BLOCKED | User-controlled iPhone login needed |
| Background / locked / force quit delivery | BLOCKED | No verified production event source, Apple device or APNs setup |
| Signed IPA / remote push | BLOCKED | No supplied signing credentials or upstream source |

Written tests are not passed tests. Synthetic fixture data is limited to tests and never seeded into the production app. A scheduled local request is not evidence of an arriving Muse notification or physical-device APNs delivery.

## Actions evidence

- [46059671694](https://github.com/dungprovaidai/MuseFleet/actions/runs/46059671694), source `2db9744`: 31 unit tests, one skipped, zero failures; UI smoke failed on a noninteractive tab match. Device build and IPA upload skipped.
- [46061676530](https://github.com/dungprovaidai/MuseFleet/actions/runs/46061676530), source `ed45ea3`: same unit result; UI smoke failed with `Invalid key path isHittable specified in predicate format string (XCTElementQueryInvalidPredicate)`. Logs and `.xcresult` artifacts were downloaded; no complete UI flow or Settings screenshot was verified.
- [46063990154](https://github.com/dungprovaidai/MuseFleet/actions/runs/46063990154), source `2147858`: 31 unit tests, one skipped, zero failures; UI smoke timed out on tab hit-testing. The exported issue description and simulator recording were inspected. A frame from the recording shows the system passcode prompt for MuseFleet covering the app; no profile creation or Settings screenshot was reached. Both readable and privacy-redacted view trees appear behind the prompt. Device build and IPA upload skipped.
- [46065778744](https://github.com/dungprovaidai/MuseFleet/actions/runs/46065778744), source `222c8c0c94ca2668ac09382452bcf78734738cee`: SUCCESS. Local ad hoc simulator signing restored Keychain access without an Apple identity/profile. The isolated Keychain regression passed, hosted units reported 31 passed/one skipped, and UI smoke passed in 44.753 seconds. Downloaded `Tests.xcresult/database.sqlite3` independently reports 33 case runs: 32 Success, one Skipped and no other result. This includes the UI case; it is not 32 passed unit tests. Production app-lock behavior is unchanged. The arm64 unsigned device build and IPA validation then passed.

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

## Verified delivery evidence

The successful run produced `MuseFleet-unsigned.ipa`, its checksum and build metadata. The IPA artifact is [15230534206](https://github.com/dungprovaidai/MuseFleet/actions/runs/46065778744/artifacts/15230534206); actual simulator/build results are [15230584240](https://github.com/dungprovaidai/MuseFleet/actions/runs/46065778744/artifacts/15230584240). GitHub reports expiry at 2026-11-28 20:56 UTC; local copies were retained under `artifacts/delivery-46065778744/` and `artifacts/results-46065778744/` before expiry.

- IPA SHA-256: `c384d3dcde36061bb4a5a3872d3ee976e6f6425f5c5ade168b66743e7844879d`.
- Metadata: version `0.1.0`, build `7`, bundle `com.dungprovaidai.musefleet`, arm64/iOS, Xcode 26.3 (17C529), SDK iPhoneOS 26.2, minimum iOS 17.0, unsigned and no embedded provisioning profile.
- Validation: the downloaded IPA passed `scripts/validate_ipa.py --signing unsigned`; its parsed metadata matches the runner, ZIP CRCs pass and Windows `Get-FileHash` independently agrees with the `.sha256` and metadata. The native executable is 4,135,976 bytes, rather than a placeholder. macOS also checked the absence of a code signature. `codesign_verified=false` reflects the unsigned artifact, not a verified distribution signature.
- Actual screenshot: exported `68E76ABD-600F-4870-B9BE-F3A7A5F1D325.png`, named “MuseFleet simulator Settings” in the test manifest, visually inspected and retained as `artifacts/delivery-46065778744/MuseFleet-simulator-Settings.png`. It shows Settings and the four native tabs; notification permission is “Not requested.”
- The downloaded `.xcresult` bundles and read-only SQLite queries substantiate the test counts and outcomes. An extracted summary is retained as `test-evidence.json`; structural validation is retained as `independent-validation.json` in the delivery folder.

Physical-device installation, iOS 17 runtime behavior, authenticated Muse login and real/background notifications remain unverified. See [DELIVERY.md](DELIVERY.md) for the handoff.

## Source review corrections

Review found authentication re-entry after interruptions, a stale activation task resuming browser work after backgrounding, missing foreground sound presentation and pending-notification privacy races. Source now guards an already-unlocked session, rejects stale authentication generations, rechecks active scene state after awaits, honors sound settings, invalidates pending delivery tasks and rejects stale private foreground presentation. A separate privacy window covers native modal presentation; its snapshot/VoiceOver behavior still requires physical-device verification. App-lock changes now authenticate before updating the saved preference.
