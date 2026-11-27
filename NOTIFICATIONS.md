# Notification capability and setup

## Current release blocker

The app has local inbox/notification/routing code and proof-of-concept fixtures. It does **not** yet have a verified production Muse event source. New Muse responses, completed tasks and approvals must not be described as working notifications until real-account tests establish event detection and coverage.

| Provider | Classification | Current behavior / requirement |
|---|---|---|
| Foreground web observer | BLOCKED for Muse; fixtures only | Authenticated Muse message/task markup and stable IDs have not been verified. Production detection remains unavailable. |
| Official Muse notifications | DOCUMENTED in official Muse; UNVERIFIED as an integration | Official native app alerts do not become MuseFleet events. No proven webhook subscription is connected. |
| Background refresh | UNSUPPORTED for continuous WebView monitoring | No permitted data source exists to refresh. iOS decides whether/when background refresh runs. No BGAppRefresh task is registered. |
| Email / WhatsApp / external channel | DOCUMENTED end-user channels; UNVERIFIED event coverage | External app notifications are separate from MuseFleet. Automatic task/approval export has not been demonstrated. |
| Native APNs remote push | BLOCKED | Needs an authorized event upstream, user-approved relay, APNs server credentials, device registration and compatible signing. None is configured. |
| iOS local notification delivery | DOCUMENTED API; runtime PoC pending | Can deliver an event already known to the app. Does not discover future Muse activity. |

See `research_notes/MuseFleet iOS feasibility/` for source citations and precise distinctions. Production UI never claims Monitoring 24/7.

## Event rules

The model includes response, completed, failed, attention, approval, question, artifact, progress and session-expired types. Event identity is scoped to the account UUID. Seen IDs persist after a user deletes a displayed event so an old event does not reappear immediately. The inbox stores account identity snapshots, timestamp, type, source, optional safe URL, optional bounded preview and read state.

Hidden previews are the default. In that mode new message text is not persisted and native alerts hide the account name and message. Notification permission denial does not prevent valid known events from being saved to Inbox. Per-account disable stops native delivery for that profile. Quiet hours suppress native delivery and haptics but keep Inbox events; start is inclusive, end exclusive, equal start/end means all-day quiet. iOS Focus and notification settings may further suppress alerts.

Only validated same-origin main-frame messages from an isolated WebKit content world may reach an installed observer. No page receives a general native API. A future adapter must baseline existing history, distinguish user/assistant content using observed structure, emit stable response IDs once, and identify explicit completion/approval transitions separately from text streaming. Silence, `aria-busy` alone or words like “done” are insufficient evidence.

## Native notification routing

On tap: validate account UUID/event ID → wait for app unlock → verify account still exists → validate conversation URL → open that account and safe URL/home → mark read and update badge. Foreign hosts, HTTP, credentials, unsupported ports, query-based auth callbacks and fragments are rejected as persisted routes. A missing conversation URL opens Muse home for the selected account.

## Setup that can be performed now

1. Settings → Notifications → request permission. If denied, use the iOS Settings link to change it.
2. Configure sound, haptics, quiet hours and preview privacy. Enable/disable native notifications per profile.
3. Treat **Detection unavailable** as unavailable. Allowing iOS notifications alone does not connect a Muse event source.
4. Use the local-delivery XCTest PoC only on a dedicated test device with notification permission already granted. It is explicitly labeled TEST ONLY, checks scheduling and removes the pending request; it is not a Muse response or a lock-screen-delivery test.

## Optional external-channel experiment

Only after confirming the official Muse email channel is enabled for the chosen account and approving the recipient, a person can submit this prompt directly in Muse:

> For this task, if your officially supported email feature permits it, send a brief update to [my approved address] when the task finishes, fails, needs approval, or cannot continue. Include the account label [label] and task title. Do not include passwords, OTPs, login links, cookies, tokens, or sensitive conversation content. Ask for any sending approval required by Muse. Tell me if this request cannot be fulfilled reliably.

This is a proposed manual experiment. The application does not submit it, send mail, link WhatsApp or claim it covers every response. Test success, failure and approval events separately. A successful one-off email is not a comprehensive native notification integration.

## Background and relay decision

iOS suspends web content; switching apps, locking or force quitting cannot be solved by a continuously running WKWebView. Previously scheduled local alerts and server-originated APNs alerts are different from background event discovery. A Home Screen web app's Web Push is not automatically forwarded into WKWebView or MuseFleet.

Do not deploy a relay until a permitted upstream proves stable event/account IDs, authentication, source validation, retries and coverage. The future relay may accept only authorized minimal events and use APNs credentials kept on the server. No Meta session belongs on that server. No relay, Cloudflare account change or charge has been authorized or made. An unsupported signing method must fall back to local/external capabilities rather than claim APNs works.

## Required real-device evidence

Log a sanitized event ID, provider, account alias, trigger time and observed arrival time for foreground A, foreground B, background, locked and force-quit tests. Verify tap routing with app lock enabled. Repeat with denial, Focus, quiet hours, stale sessions, offline mode and revoked profile. Simulator scheduling cannot certify physical-device APNs or Muse login.
