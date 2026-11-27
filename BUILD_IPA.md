# Building MuseFleet

MuseFleet targets iPhone on iOS 17 or later, uses Swift 5 language mode, and has no runtime package dependencies. The bundle identifier is `com.dungprovaidai.musefleet`. The checked-in `MuseFleet.xcodeproj` and shared `MuseFleet` scheme include the app, hosted `MuseFleetTests`, and `MuseFleetUITests` targets.

Windows can generate the project and test the pipeline scripts. Xcode, simulator tests, code signing, and a real IPA require macOS. No Apple build or device installation has been verified by the Windows pipeline work.

## Integrating source files

`scripts/generate_project.py` is the project source of truth; XcodeGen and a separate `project.yml` are unnecessary. Object identifiers are derived from stable names, so unrelated source changes do not renumber the project. Run the generator **after merging the application/browser/UI branches**, and whenever sources or resources are added or removed:

```powershell
python -I -X utf8 scripts/generate_project.py
python -I -X utf8 scripts/generate_project.py --check
python -I -X utf8 -m unittest discover -s Tests/Pipeline -v
git add MuseFleet.xcodeproj
```

The generator enumerates `App/**/*.swift`, `Tests/CoreTests/**/*.swift`, `BrowserTests/**/*.swift`, and `UITests/**/*.swift`. It copies top-level `App/Browser/*.js` files to the app bundle resource root, treats each asset catalog as one resource, and copies `App/Resources` plus `Config/PrivacyInfo.xcprivacy`. Unit/UI fixture directories named `Fixtures` under their test roots go into the corresponding test bundles. Keep fixture resource basenames distinct within each bundle. Design scripts outside `App` are not included.

The DevOps branch initially has no application/test sources of its own. Its generated project references the lead-owned `App/MuseFleetApp.swift`; regeneration on the integrated tree adds the remaining source/resource references and AppIcon build setting. CI requires actual core, browser, and UI test sources and a current project. It fails when integration is incomplete.

## macOS checks

Open `MuseFleet.xcodeproj`, select the shared `MuseFleet` scheme, select an available iPhone simulator, and run Product → Test. The command-line equivalent is:

```sh
python3 -m unittest discover -s Tests/Pipeline -v
python3 scripts/generate_project.py --check
plutil -lint MuseFleet.xcodeproj/project.pbxproj Config/Info.plist Config/PrivacyInfo.xcprivacy Config/Push.entitlements
python3 scripts/apple_pipeline.py test
```

The script uses the currently selected Xcode locally. On Actions, `select-xcode` selects the newest usable preinstalled Xcode with an iOS 17+ SDK through `DEVELOPER_DIR`; it does not download Xcode or hardcode an installation name. Simulator selection uses available iPhone devices on an installed iOS 17+ runtime. Both hosted unit tests and UI tests run, with real build/test `.xcresult` bundles written under `artifacts`. No successful result is fabricated when a tool, runtime, test source, or build output is missing. Tests must use local fixtures and must not log into real Muse accounts or record credentials.

## Actions and cost authorization

Every macOS job in `.github/workflows/ci.yml` and `.github/workflows/build-ipa.yml` requires the repository Actions variable `ALLOW_MACOS_ACTIONS` to equal the exact string `true`. Without it, push, pull request, tag, and manual dispatch jobs are skipped. Do not enable this variable, push a triggering tag, or dispatch a workflow until the owner authorizes runner usage. No workflow has been launched as part of this implementation.

Both workflows use the standard `macos-15` runner with a 30-minute job limit, read-only repository permissions, and artifact retention of one day. The CI workflow supports main/master pushes, pull requests, and manual dispatch. The IPA workflow supports manual dispatch or `v*` tags. Automatic push/PR/tag builds also require `ALLOW_AUTOMATIC_MACOS_ACTIONS=true`; approval for a manual run does not enable ongoing automatic consumption. A tag build is always unsigned; signed builds require the manual boolean input. Neither workflow creates a GitHub Release, publishes an app, or installs anything on a device. Download artifacts promptly before they expire.

Billing depends on current GitHub pricing, repository visibility, plan, account limits, and existing usage. The repository variable is an authorization gate, not proof that a run is free. No no-charge account status was established here.

## Unsigned IPA

After authorization, manually run **Build IPA** with `signed=false` and a version such as `1.0.0`. A tag like `v1.0.0` uses that version. Version input accepts three numeric components; all values enter subprocess argument arrays without shell interpolation. The Actions run number is the bundle build number (1...9999); this fails explicitly rather than emitting an invalid Apple bundle version if that limit is reached.

The workflow runs the pipeline tests, resolves dependencies, builds and tests the app on a simulator, then builds Release for `generic/platform=iOS`, `ARCHS=arm64`, and `CODE_SIGNING_ALLOWED=NO`. It packages the actual `Release-iphoneos/MuseFleet.app` under `Payload/`. An unsigned build has no APNs entitlement or embedded provisioning profile. It requires suitable signing before it can be installed on an ordinary iPhone; it is not an App Store or TestFlight submission.

The IPA artifact contains:

- `MuseFleet-unsigned.ipa` or `MuseFleet-signed.ipa`, only after validation succeeds.
- A `.sha256` file identifying the exact IPA bytes.
- `build-metadata.json` recording bundle/version/build, arm64/iOS status, signature status, checksum, Xcode version, commit, and workflow run.

Actual `.xcresult` files are uploaded with `always()` even after build/test failures when those files exist. After successful simulator tests, `xcresulttool export attachments` exports actual test screenshots into the results artifact. These are simulator captures with test-created profile metadata, never screenshots of a logged-in user or proof of physical-device behavior. No screenshots are claimed until that command has run successfully.

## Signed IPA

The owner supplies these repository Actions secrets; never commit their values or paste them into logs:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_BASE64` | Base64 of an Apple signing `.p12` including its private key |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the `.p12` |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Base64 of an unexpired explicit iOS provisioning profile for this bundle/team |
| `APPLE_TEAM_ID` | Ten-character Apple Developer team identifier |
| `KEYCHAIN_PASSWORD` | Optional temporary-keychain password; a random value is generated if absent |

For base64 input, use a single line without surrounding whitespace. Do not reuse a personal login-keychain password. Creation of certificates, profiles, secrets, or an Apple developer membership is outside the workflow.

After authorizing Actions costs and supplying credentials, manually dispatch **Build IPA** with `signed=true`. Setup decodes and verifies the profile's CMS signature with the system `/usr/bin/openssl` without importing its certificates into a user keychain. It checks the exact application identifier and team, validity dates, iOS platform, device/distribution settings, and APNs environment. It imports the `.p12` into a private temporary keychain and requires a valid signing identity whose certificate is authorized by the profile. The profile is installed in Xcode 16+'s `~/Library/Developer/Xcode/UserData/Provisioning Profiles` location (or the legacy location for an older selected Xcode). An existing profile with the same UUID is never overwritten. The password and base64 values are never printed.

The profile determines export method: development → `debugging`, ad hoc → `release-testing`, enterprise → `enterprise`, or App Store → `app-store-connect`. The workflow archives with manual signing and exports locally with `destination=export`, no automatic version changes, and no symbol upload. It never passes `-allowProvisioningUpdates` or initiates App Store submission. Development/ad hoc IPAs install only on devices registered in the profile; enterprise requires the appropriate Apple membership and device trust; an App Store export needs the separate authorized submission process.

`Config/Push.entitlements` is separate from the project's ordinary build settings. A signed build selects it only when the validated profile grants `aps-environment`, using that profile's development/production value. This grants a signing capability; it does not establish Muse webhooks, a push relay, APNs credentials, or background web monitoring. Unsigned and ordinary simulator builds never select it.

An `always()` step restores the prior keychain search list, deletes the temporary keychain, and removes the installed profile and private signing files. A hard runner termination can prevent cleanup steps from executing; hosted runner isolation provides the remaining boundary. Signing files live under `RUNNER_TEMP`, outside uploaded artifacts. Credentials are exposed only to the signing setup step.

## IPA validation and security configuration

Standalone validation is also available:

```sh
python3 scripts/validate_ipa.py artifacts/MuseFleet-unsigned.ipa --signing unsigned --codesign --output artifacts/validation.json
# For a signed artifact, use --signing signed instead.
```

The validator rejects path traversal, special files/symlinks, duplicate/case/Unicode-colliding entries, encrypted or oversized ZIPs, conflicting paths, malformed plists, wrong bundle/platform/version metadata, missing executables, and placeholder/simulator binaries. It checks arm64 Mach-O headers, segment/section bounds, load-command sizes, an actual text section, a valid entry point, iOS deployment, dynamic linker, and signature presence. It reads every ZIP member to verify CRCs and computes SHA-256. The generated package format is a single `Payload/*.app`; unrelated outer ZIP content is rejected.

On macOS, unsigned validation also confirms the bundle is unsigned with `codesign`. Signed validation uses `codesign --verify --deep --strict`, compares signed entitlements to the embedded profile, checks profile validity again, and verifies that the signing leaf certificate belongs to that profile. Without `--codesign`, structural checks alone never claim cryptographic signature verification. The synthetic local fixtures test parser rejection and signing orchestration; they are not runnable apps or real signing evidence.

`Config/Info.plist` supplies the Face ID reason and document opening support. The system photo picker requires no photo-library permission, so no access reason is declared. Downloads can be shared through the app's system document/share UI; blanket file sharing is disabled to avoid exposing account metadata. There are no arbitrary-load ATS exceptions or background modes.

The privacy manifest declares no app tracking or collected data. The currently inspected core does not call UserDefaults, file timestamp, or disk capacity APIs, so no required-reason API is declared. Recheck this manifest against all integrated source before distribution. If UserDefaults is introduced for this app's own settings, declare its actual use with reason `CA92.1`; do not add unused file timestamp/disk space reasons. Muse web content remains subject to the website's own privacy behavior.

## Remaining release evidence

Before distributing an artifact, obtain a successful authorized macOS build and XCTest run, inspect its uploaded `.xcresult` and metadata, verify the checksum, and test installation on a permitted physical iPhone. Account isolation, native notifications, downloads, app lock, accessibility, and the current website observer need their own app/device evidence. A successful packaging script does not prove those product features.
