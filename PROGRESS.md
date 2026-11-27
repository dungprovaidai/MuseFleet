# MuseFleet progress

## Current state

2026-11-28: Empty Windows workspace inspected. Git and GitHub CLI available; GitHub authenticated as `dungprovaidai`. No Swift, Xcode, XcodeGen, macOS runner connection, browser MCP or iPhone connection available locally. Existing skills and tool catalog inspected.

## Gates

| Phase | State | Evidence / blocker |
|---|---|---|
| 0 Research | DOCUMENTATION COMPLETE; runtime gates open | Official Muse home/form fetched; iOS17 identified stores documented; Muse embedded login and authenticated event DOM unverified |
| 1 Isolation and notification PoCs | TEST SOURCE IN PROGRESS; runtime BLOCKED | Apple execution environment and real Muse login required |
| 2 Core browser | SOURCE INTEGRATED; Apple runtime pending | Per-UUID stores, max3 LRU, popup/download/navigation, strict observer boundary |
| 3 Notifications | CORE IMPLEMENTED; Muse source BLOCKED | Local persistence/routing/dedup/quiet hours implemented; no real event source verified |
| 4 Native UI | SOURCE INTEGRATED; Apple runtime pending | Home, Accounts, Inbox, Settings; original icon generated; no demo accounts seeded |
| 5 Background delivery | BLOCKED | No verified upstream event source or APNs credentials |
| 6 Security and QA | IN PROGRESS | App lock, URL policy, privacy, atomic storage and unit test source; no Apple runtime execution |
| 7 GitHub and IPA | PIPELINE INTEGRATED; public build preparation | User approved source public; visibility changed; 21 Python and 9 Node tests passed; 31 Swift files syntax-parsed |
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

1. User approved making source public for standard free runners. Verify public Actions storage policy, then run manual build/test; no paid services authorized. Automatic run variable remains disabled.
2. No physical iPhone or browser MCP; user-controlled Muse login and two-account live isolation are not tested.
3. No verified authenticated Muse DOM or official event upstream; real response notifications and background/locked/force-quit delivery remain incomplete.
4. No Apple signing credentials; signed IPA and APNs are unavailable. A real unsigned arm64 IPA still requires an Apple build runner.
