# Architecture

## Boundaries and data flow

`SwiftUI → FleetStore` persists local profile/event metadata. `SwiftUI → BrowserPool → BrowserSession → WKWebView` loads the official website. An account UUID selects exactly one persistent `WKWebsiteDataStore(forIdentifier:)` before WebView creation. A profile rename does not change its UUID or session. The cache may evict WebViews; it never substitutes the default data store or removes persistent sessions as an eviction side effect.

`verified page adapter → NotificationProvider → NotificationCoordinator → FleetStore / UserNotifications` is the intended event path. The production Muse adapter is unavailable until authenticated DOM evidence exists. Synthetic fixture selectors are confined to tests. There is no credential extraction, private Muse API, runtime remote configuration or script downloaded from a relay.

Native notification responses create a `NotificationRoute` containing an account UUID and event ID. The app waits for device authentication if lock is enabled, verifies the profile still exists, validates the URL, selects that profile, navigates its WebView and marks the event read. Missing/unsafe links fall back to the verified Muse home URL. No inferred conversation path is constructed.

## Local persistence

Profiles, settings, events and seen-event IDs use a versioned Codable JSON snapshot in Application Support, written atomically with complete file protection and excluded from backup. This small metadata dataset does not currently require database queries or a schema framework. A corrupt/unreadable snapshot is preserved and writes are disabled; there is no destructive automatic reset. Write failures surface in UI. In-memory settings can temporarily differ from disk after a failed save and must be retried.

WebKit owns cookies, local storage, caches and other website state within each persistent store. MuseFleet does not read or copy authentication state. Website session expiry remains controlled by Muse. WebKit's platform-managed storage/backup behavior is separate from MuseFleet's metadata snapshot; app lock does not encrypt website data with a distinct application password.

Keychain stores only the device-local app-lock flag with `WhenUnlockedThisDeviceOnly`; it stores no Meta credential. At launch, Keychain overrides the metadata lock preference. An inaccessible Keychain fails closed. `LocalAuthentication` uses device-owner authentication with biometric or passcode fallback. Changing the lock preference requires device-owner authentication.

## Browser lifecycle

BrowserPool keeps at most three sessions. It suspends observers when the app backgrounds and reduces the cache under memory pressure. Browser process termination is an error/recovery state; a re-created view selects the same persistent data store and reopens a safe last URL. Evicted accounts cannot be monitored by a foreground WebView observer. This limit is exposed, rather than described as continuous monitoring.

Login popups must share the parent account's data store; user navigation to third-party HTTPS destinations requires explicit handling. There is no custom user-agent impersonation and no copying a session from Safari. Native WebKit file inputs provide system upload UI. Downloads stay in the app sandbox for explicit sharing; they may contain private material and should be cleared through storage management.

## Concurrency and dependencies

App state and UI/browser/notification coordinators are main-actor isolated. Swift Concurrency bridges platform asynchronous operations. Apple system frameworks supply Observation, SwiftUI, WebKit, LocalAuthentication, Security, UserNotifications, PhotosUI and OSLog. Runtime third-party dependencies: none.

## Deliberate limits

- Metadata schema version 1 has no silent forward migration; a future schema requires explicit migration plus tests.
- URL persistence currently accepts exact Muse HTTPS hosts without query or fragment. Query-based conversation routing needs a verified safe format; it is not guessed.
- No fake heartbeat, BGAppRefresh polling, silent audio, VoIP, location monitoring or unattended GitHub runner exists.
- A relay is not implemented/deployed because the required permitted Muse event source is unverified.
