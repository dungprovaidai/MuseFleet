# Security review and release conditions

## Data boundary

MuseFleet is a container for the official HTTPS website. Credentials and OTP entry belong to that website. The application must not inspect authentication form values, extract tokens, copy cookies, replay internal API requests, bypass CAPTCHA, change user agent to evade restrictions or transmit sessions. No app-owned remote service is currently deployed.

Each account's UUID chooses a separate persistent WKWebsiteDataStore. The default shared store is prohibited. Tests use local synthetic stores to check cookies/local storage separation and deletion; they do not inspect a real Meta login cookie. A profile rename leaves its UUID intact. Removing a WebView from RAM must not remove its website data.

## Implemented controls requiring Apple runtime verification

- Keychain-based lock preference, device-owner authentication and biometric/passcode fallback.
- A privacy curtain while the scene is inactive/backgrounded and while locked; notification routing waits for unlock.
- Versioned atomic local metadata writes with complete file protection and backup exclusion; unreadable data is preserved.
- Exact Muse HTTPS host validation for saved links, no URL credentials or nonstandard ports. Saved links with query/fragment are currently rejected until a verified conversation format exists.
- Default notification preview privacy, bounded message previews, account-scoped deduplication and ID-validated notification routing.
- WebKit script messages restricted by isolated content world, main frame, origin and validated payload; no production Muse adapter until rendered semantics are verified.
- Generic OSLog messages without profiles, conversation text, URLs, cookies or credentials.
- No secrets in source, signing assets ignored, ephemeral CI signing keychain planned and cleaned after use.

## Threats and limits

App lock protects app access and snapshots; it is not a separate encryption boundary against an unlocked/jailbroken device, OS compromise, or a person able to alter app storage. WebKit controls its website database encryption, backups, session expiry and storage lifetime. Metadata notes, avatars, account labels and downloaded documents may be sensitive.

An external HTTPS link can lead to another website. Users should inspect the destination before following it; being linked from Muse is not proof the destination is trustworthy. External Safari authentication does not imply authentication in a per-profile WebView. System screen recording and screenshots while the person actively uses the app are not universally preventable through public iOS APIs; MuseFleet does not capture them by default.

Optional website-data deletion must target only the selected UUID, release its live WebView and surface deletion errors. Removing metadata while retaining website data can intentionally leave an orphaned session. Clear it first if complete removal is intended; do not imply metadata removal logs out all devices or revokes server sessions. Files explicitly exported using the share sheet are outside the app's control.

Quiet hours and preview privacy cannot retract content already read by the person, copied, exported or seen by another notification service. Apple notification settings and Focus apply separately. Remote payloads are not accepted merely because an arbitrary URL or page claims an event occurred.

## CI secrets and signing

No certificate, provisioning profile, APNs signing key or Apple membership was supplied. Unsigned build mode must not require or fetch any. Signed mode requires user-supplied GitHub Secrets and must validate application identifier, Team ID, profile expiry/distribution and any `aps-environment`. Never print decoded profile contents, private key data or signing passwords to workflow logs. Release publication and relay deployment require separate user authorization.

Signed validation currently fails closed before importing credentials: a documented public check of Apple provisioning-profile signer authorization is unresolved. CMS signature integrity by itself is insufficient, and no private policy APIs or untrusted roots are installed. This additional signing gate must be resolved even if credentials are supplied later. Legacy App ID prefixes are checked separately from Team ID; certificate extraction uses the correct single-argument `codesign` option.

## Release gates still open

1. Compile and execute tests on Apple SDKs; review integration and actual workflow logs.
2. Verify two real Muse accounts, restart restoration, logout/deletion isolation and memory-pressure recreation on iPhone.
3. Verify auth redirects/popups without broadening host trust or weakening TLS.
4. Establish authenticated DOM evidence before enabling a production observer; check cross-account script/event isolation.
5. Run lock-screen, interruption, notification permission and deep-link tests with physical device evidence.
6. Inspect real IPA executable, bundle identifier, architecture, signing and checksum; do not label an untested binary secure or production ready.

No penetration test, physical-device audit or assertion of “no critical security defects” is made without those results.
