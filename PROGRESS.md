# MuseFleet progress

## Current state

2026-11-28: Integrated source is committed in the public MuseFleet repository. The authorized standard GitHub Actions macOS runner has compiled the app and run simulator tests. The latest completed run executed 31 unit tests with one skip and zero failures, but UI testing was blocked by a system app-lock passcode prompt. The exported simulator recording confirms the prompt. A manual unsigned build at `222c8c0` is running with local simulator signing and an isolated Keychain regression test. No IPA has been produced yet. Windows still has no local Xcode, simulator or physical iPhone connection.

## Gates

| Phase | State | Evidence / blocker |
|---|---|---|
| 0 Research | DOCUMENTATION COMPLETE; runtime gates open | Official Muse home/form fetched; iOS17 identified stores documented; Muse embedded login and authenticated event DOM unverified |
| 1 Isolation and notification PoCs | SYNTHETIC SIMULATOR FIXTURES PASS; live gates open | Two named stores isolate, persist and delete local fixture state; observer fixture tests pass; system notification delivery PoC skipped without permission |
| 2 Core browser | COMPILED; targeted simulator tests PASS | Named store deletion, max3 LRU, navigation policy and observer boundaries tested; real Muse login, uploads and downloads unverified |
| 3 Notifications | CORE TESTS PASS; Muse source BLOCKED | Persistence, routing, deduplication, privacy and quiet hours tested; no real event source verified |
| 4 Native UI | COMPILED; UI smoke RETRY RUNNING | Home, Accounts, Inbox, Settings; system passcode prompt blocked tab interaction in the previous run; supported resolved-element queries retained |
| 5 Background delivery | BLOCKED | No verified upstream event source or APNs credentials |
| 6 Security and QA | UNIT TESTS PASS; device QA pending | App-lock generation checks, URL policy, notification privacy, corrupt-file preservation and persistence tested on simulator; physical-device privacy and authentication remain unverified |
| 7 GitHub and IPA | UNSIGNED BUILD RETRY RUNNING | Manual run 46065778744 at 222c8c0; simulator unit/UI gates precede arm64 device build and IPA validation. Local checks: 28 Python + 9 Node tests passed |
| 8 Delivery | PENDING | Requires real artifact and honest test evidence |

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

1. UI smoke must pass before device packaging. The latest recording shows a device-owner authentication prompt over the app; unsigned simulator Keychain access is the suspected trigger because the app deliberately locks on Keychain errors. Simulator builds now use local ad hoc signing and a real isolated Keychain round-trip test. App-lock behavior is unchanged; the next run must establish the result.
2. No physical iPhone or browser MCP; user-controlled Muse login and two-account live isolation are not tested.
3. No verified authenticated Muse DOM or official event upstream; real response notifications and background/locked/force-quit delivery remain incomplete.
4. No Apple signing credentials; signed IPA and APNs are unavailable. A real unsigned arm64 IPA is pending a successful test-gated Actions run and independent artifact validation.

## Build evidence

- First run [46052949212](https://github.com/dungprovaidai/MuseFleet/actions/runs/46052949212) failed on malformed asset JSON, corrected by `133259b`.
- Store-in-use retry (`08a3614`) and explicit named-store content removal (`2db9744`) resolved the browser fixture failures. Run [46059671694](https://github.com/dungprovaidai/MuseFleet/actions/runs/46059671694) executed 31 unit tests with one skip and zero failures; its UI test selected a noninteractive tab.
- Run [46061676530](https://github.com/dungprovaidai/MuseFleet/actions/runs/46061676530) at `ed45ea3` again executed 31 unit tests with one skip and zero failures. Its UI test failed with `XCTElementQueryInvalidPredicate` for `isHittable`; device build and IPA upload were skipped. Logs identify Xcode 26.3, iOS Simulator 26.2 and iPhone SE (3rd generation). This does not test the iOS 17 minimum.
- Run [46063990154](https://github.com/dungprovaidai/MuseFleet/actions/runs/46063990154) at `2147858` executed 31 unit tests with one skip and zero failures. UI smoke timed out waiting for an interactive tab. Exported artifacts contain a simulator screen recording and issue description; an inspected frame shows the iOS passcode prompt for MuseFleet, rather than an interactive app. Device packaging was skipped.
- Run [46065778744](https://github.com/dungprovaidai/MuseFleet/actions/runs/46065778744) at `222c8c0` is running. Simulator builds use local ad hoc signing with no Apple certificate or profile, and a new hosted XCTest checks isolated Keychain create/read/delete access. Device packaging remains unsigned. The tab query matches its identifier and readable label, then evaluates `.isHittable` directly and requires a unique interactive match.
- User approved public source; GitHub visibility confirmed public. Official billing documentation states standard public Actions usage is free and scopes metered compute/storage to private repositories. Current repository initially had zero artifacts. Artifact retention is one day; automatic push/PR/tag execution remains off.
- GitHub OAuth workflow permission was added through the official device authentication flow after an initial push rejection. No credential was committed.
- Signed mode is fail-closed pending documented provisioning-profile signer authorization, in addition to missing signing assets. Unsigned build is independent.
