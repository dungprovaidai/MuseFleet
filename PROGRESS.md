# MuseFleet progress

## Current state

2026-11-28: A diagnostic unsigned arm64 IPA, version 0.1.4 (build 11), has been built, downloaded and independently validated. Run [46102409678](https://github.com/dungprovaidai/MuseFleet/actions/runs/46102409678) at `5d72826` passed 32 unit tests and one UI test, with one notification-permission skip. `auth.muse.ai`, the exact hostname reported by the user, now passes the HTTPS allowlist; lookalikes remain rejected. The user's live login remains untested. See [DELIVERY.md](DELIVERY.md) for download, SHA-256 and signing limits. Windows still has no local Xcode or physical iPhone connection.

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
| 7 GitHub and IPA | DIAGNOSTIC IPA VERIFIED | Manual run 46102409678 at 5d72826; actual arm64 iOS executable, unsigned status, metadata and SHA-256 checked; local 28 Python + 9 Node tests pass |
| 8 Delivery | DIAGNOSTIC BUILD READY | 0.1.4 IPA and evidence retained locally under artifacts/; download/checksum details in DELIVERY.md; signed installation and live Muse validation remain open |

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
- User reported Safari can open Muse on iOS 26.6.2 while MuseFleet cannot open pages. Run [46090966062](https://github.com/dungprovaidai/MuseFleet/actions/runs/46090966062) at `f2bbe8c` passed: 32 unit cases and one UI case passed, one notification-permission test skipped. New IPA 0.1.1/build 8 was downloaded and independently validated; SHA-256 `3f7d72b27a553d339a0827f93a03aca06d840d091c8cd69b6d8ed7d406ebb98b`. It reports safe numeric network/WebKit error codes. This is diagnostic, not a claim the user's failure is fixed.
- User supplied a screenshot with WebKit error 102. Run [46093660501](https://github.com/dungprovaidai/MuseFleet/actions/runs/46093660501) at `2fef329` passed: 32 unit tests, one UI test, one notification-permission skip; the `.xcresult` confirms 33 successes and one skip. The 0.1.2/build 9 unsigned arm64 IPA passed independent validation; SHA-256 `e9c8f04e44bd0ad488b1d3c591a6226d0039660c9e30aea7220c337b8bc68aec`. Code 102 may indicate a navigation interruption; app-policy rejection is now reported distinctly, but the actual redirect destination remains unknown. No allowlist change or TLS bypass was made.
- User supplied a follow-up screenshot explicitly showing policy-blocked redirect. Public Muse page JS (retrieved without submitting credentials) configures `https://auth.meta.com/oidc`; its auth return validator recognizes `/auth_platform`, `/checkpoint` and `/checkpoints` there, and Meta social origins `www.facebook.com`/`www.instagram.com` on `/auth_platform`. Run [46095940301](https://github.com/dungprovaidai/MuseFleet/actions/runs/46095940301) at `6f84487` passed 32 units and one UI smoke with one notification-permission skip. Version 0.1.3/build 10 unsigned IPA independently validated; SHA-256 `433d08fff50414a3136c390eb165c45880ed9abf5aed096b2ca6fa8d5be7c1fb`. It allows those exact HTTPS routes and displays only a blocked hostname on other redirects. This is public frontend evidence, not an authentication contract or real device sign-in test.
- User's screenshot identified `auth.muse.ai`. Run [46102409678](https://github.com/dungprovaidai/MuseFleet/actions/runs/46102409678) at `5d72826` passed 32 unit tests and one UI smoke, with one notification-permission skip. Version 0.1.4/build 11 IPA passed independent validation; SHA-256 `e4986b79800abb037cbcac0a41f3cd4f9a1ffdc01c554f4e18a9db57423c82a2`. Only that exact HTTPS host was added; lookalikes and insecure variants remain rejected. Sign-in completion is still unverified on the user's phone.
- User approved public source; GitHub visibility confirmed public. Official billing documentation states standard public Actions usage is free and scopes metered compute/storage to private repositories. Current repository initially had zero artifacts. Artifact retention is one day; automatic push/PR/tag execution remains off.
- GitHub OAuth workflow permission was added through the official device authentication flow after an initial push rejection. No credential was committed.
- Signed mode is fail-closed pending documented provisioning-profile signer authorization, in addition to missing signing assets. Unsigned build is independent.
