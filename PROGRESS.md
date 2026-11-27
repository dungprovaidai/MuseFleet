# MuseFleet progress

## Current state

2026-11-28: A real unsigned arm64 IPA, version 0.1.0 (build 7), has been built, downloaded and independently validated. Run [46065778744](https://github.com/dungprovaidai/MuseFleet/actions/runs/46065778744) at `222c8c0` passed 31 unit tests and one UI test, with one additional unit test skipped for notification permission. The actual `.xcresult` database confirms 32 successful cases, one skipped and zero failures. The simulator Settings screenshot was inspected. See [DELIVERY.md](DELIVERY.md) for download links, SHA-256 and signing limitations. Windows still has no local Xcode or physical iPhone connection.

## Gates

| Phase | State | Evidence / blocker |
|---|---|---|
| 0 Research | DOCUMENTATION COMPLETE; runtime gates open | Official Muse home/form fetched; iOS17 identified stores documented; Muse embedded login and authenticated event DOM unverified |
| 1 Isolation and notification PoCs | SYNTHETIC SIMULATOR FIXTURES PASS; live gates open | Two named stores isolate, persist and delete local fixture state; observer fixture tests pass; system notification delivery PoC skipped without permission |
| 2 Core browser | COMPILED; targeted simulator tests PASS | Named store deletion, max3 LRU, navigation policy and observer boundaries tested; real Muse login, uploads and downloads unverified |
| 3 Notifications | CORE TESTS PASS; Muse source BLOCKED | Persistence, routing, deduplication, privacy and quiet hours tested; no real event source verified |
| 4 Native UI | COMPILED; UI smoke PASS | Profile creation, relaunch persistence, Accounts/Inbox/Settings navigation and actual Settings screenshot verified on simulator |
| 5 Background delivery | BLOCKED | No verified upstream event source or APNs credentials |
| 6 Security and QA | UNIT TESTS PASS; device QA pending | App-lock generation checks, URL policy, notification privacy, corrupt-file preservation and persistence tested on simulator; physical-device privacy and authentication remain unverified |
| 7 GitHub and IPA | UNSIGNED IPA VERIFIED | Manual run 46065778744 at 222c8c0; actual arm64 iOS executable, unsigned status, metadata and SHA-256 checked; local 28 Python + 9 Node tests pass |
| 8 Delivery | ARTIFACT READY | IPA and evidence retained locally under artifacts/; download/checksum details in DELIVERY.md; signed installation and live Muse validation remain open |

Never treat a written test, simulator-only check or packaged placeholder as a verified production feature.

## Decisions

- Source website: official `https://muse.ai/`; initial login form verified by public HTTP fetch. Muse's official native app minimum iOS18 does not establish third-party iOS17 web compatibility.
- Production DOM adapter remains disabled until the authenticated interface has been observed and tested. Muse is asynchronous; typing cessation cannot prove task completion.
- No BGAppRefresh registration or relay deployment without a usable authorized data source. No 24/7 WebView monitoring claim.
- Codable atomic local snapshot selected for the small metadata dataset; complete file protection, no backup, corrupt files preserved.
- Keychain stores the device-local lock preference; device-owner authentication protects changes. No Meta secrets are read or logged.
- Six subagents dispatched in branches/worktrees: three official-source research topics, browser engine, native UI, DevOps. A report writer synthesizes research.
- Skill routing: existing ponytail and deep-research used. Native iOS skill search failed on a read-only Windows cache object; no skill was installed or executed from an unapproved candidate.

## Current blockers

1. No physical iPhone or browser MCP; user-controlled Muse login, two-account live isolation and physical-device app-lock/privacy behavior are not tested. The configured iOS 17 minimum has not been exercised on an iOS 17 runtime.
2. No verified authenticated Muse DOM or official event upstream; real response notifications and background/locked/force-quit delivery remain incomplete. The notification-delivery PoC was skipped for lack of granted system permission.
3. No Apple signing credentials; ordinary iPhone installation needs appropriate signing. Signed automation additionally remains blocked by provisioning-profile signer authorization; no signed IPA or APNs delivery is claimed.

## Build evidence

- First run [46052949212](https://github.com/dungprovaidai/MuseFleet/actions/runs/46052949212) failed on malformed asset JSON, corrected by `133259b`.
- Store-in-use retry (`08a3614`) and explicit named-store content removal (`2db9744`) resolved the browser fixture failures. Run [46059671694](https://github.com/dungprovaidai/MuseFleet/actions/runs/46059671694) executed 31 unit tests with one skip and zero failures; its UI test selected a noninteractive tab.
- Run [46061676530](https://github.com/dungprovaidai/MuseFleet/actions/runs/46061676530) at `ed45ea3` again executed 31 unit tests with one skip and zero failures. Its UI test failed with `XCTElementQueryInvalidPredicate` for `isHittable`; device build and IPA upload were skipped. Logs identify Xcode 26.3, iOS Simulator 26.2 and iPhone SE (3rd generation). This does not test the iOS 17 minimum.
- Run [46063990154](https://github.com/dungprovaidai/MuseFleet/actions/runs/46063990154) at `2147858` executed 31 unit tests with one skip and zero failures. UI smoke timed out waiting for an interactive tab. Exported artifacts contain a simulator screen recording and issue description; an inspected frame shows the iOS passcode prompt for MuseFleet, rather than an interactive app. Device packaging was skipped.
- Run [46065778744](https://github.com/dungprovaidai/MuseFleet/actions/runs/46065778744) at `222c8c0` succeeded. Local ad hoc simulator signing restored Keychain access; the isolated create/read/delete regression and complete UI smoke passed without changing production app-lock behavior. Hosted units: 32 total, 31 passed, one skipped. UI: one passed. Actual arm64 unsigned device build and validation succeeded; IPA SHA-256 is `c384d3dcde36061bb4a5a3872d3ee976e6f6425f5c5ade168b66743e7844879d`. The downloaded IPA, metadata, checksum, `.xcresult` database and actual screenshot were independently inspected.
- User approved public source; GitHub visibility confirmed public. Official billing documentation states standard public Actions usage is free and scopes metered compute/storage to private repositories. Current repository initially had zero artifacts. Artifact retention is one day; automatic push/PR/tag execution remains off.
- GitHub OAuth workflow permission was added through the official device authentication flow after an initial push rejection. No credential was committed.
- Signed mode is fail-closed pending documented provisioning-profile signer authorization, in addition to missing signing assets. Unsigned build is independent.
