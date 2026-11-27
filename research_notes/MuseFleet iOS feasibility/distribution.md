# MuseFleet iOS feasibility: builds, cost controls, signing, and distribution

Research date: **2026-11-28**. Scope: a native iOS 17+ SwiftUI app developed from Windows. This is research and proposed execution guidance; it is not evidence of a successful Apple build, installation, or APNs delivery.

Classification: **OFFICIAL** = current Apple/GitHub documentation or vendor-maintained runner inventory; **OFFICIAL-ARCHIVE** = older Apple technical note or WWDC transcript, useful for the stated technical principle; **INFERENCE** = engineering recommendation derived from cited sources; **UNVERIFIED** = a project/account condition that has not been established. Sources were read as full articles or, for Apple JavaScript documentation, through Apple's corresponding official DocC JSON. Search snippets were not treated as authoritative where they conflicted with the live article.

## 1. Can GitHub Actions provide real Xcode builds for this Windows-developed iOS 17+ app?

### Takeaway

**OFFICIAL:** Standard GitHub-hosted macOS runners include Xcode and iOS SDKs. A current documented combination is `macos-15` with explicitly selected Xcode 26.3; that Xcode supports an iOS 17 deployment target. These are availability facts, not a build result for MuseFleet. — [GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners); [macOS 15 arm64 inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md); [Apple Xcode support matrix](https://developer.apple.com/support/xcode/)

### Cited Findings

- **OFFICIAL:** The current standard macOS labels include `macos-15`, `macos-26`, and `macos-latest` on arm64 M1 hardware, and `macos-15-intel` / `macos-26-intel` on Intel. The reference lists 3 M1 cores, 7 GB RAM, and 14 GB SSD for the arm64 standard runner. These labels are available for public and private repositories; billing differs. — [GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- **OFFICIAL:** The fetched macOS 15 arm64 inventory identifies image `20261118.0550.1`, macOS 15.8.2, Xcode 26.3 at `/Applications/Xcode_26.3.app`, and iOS 26.2 SDKs for that Xcode. It also lists Xcode 16.4 as the default with iOS 18.5 SDKs. An image's default Xcode must not be inferred from its OS label. — [Official raw inventory](https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-15-arm64-Readme.md)
- **OFFICIAL:** Apple lists Xcode 26.3 as supporting macOS Sequoia 15.6 through Tahoe 26.x, iOS deployment targets 15 through 26.2, and Swift 6.2.3 with Swift 5 language mode available. An iOS 17 minimum does not require building with the iOS 17 SDK. — [Apple Xcode support matrix](https://developer.apple.com/support/xcode/)
- **OFFICIAL:** `-latest` denotes GitHub's latest stable image, not necessarily the vendor's latest OS. Jobs record their runner in workflow logs; macOS jobs may queue longer during high demand. — [GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- **OFFICIAL-ARCHIVE:** `xcodebuild` performs build, test, archive, and export operations on Xcode projects and workspaces. Apple's standalone Command Line Tools package contains the macOS SDK; it is not a substitute for full Xcode plus its iOS platform support. — [Apple TN2339](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)

### Inferences

- **INFERENCE:** Start with a standard `macos-15` runner and `DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer`, with an explicit existence/version check. Fail if that requested installation disappears rather than silently selecting another compiler. Revalidate the inventory before execution because the `main` inventory is mutable. — [Runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md); [Apple support matrix](https://developer.apple.com/support/xcode/)
- **INFERENCE:** Use `generic/platform=iOS` for the device build and set `IPHONEOS_DEPLOYMENT_TARGET=17.0`. Simulator tests must use an actually installed simulator obtained from `xcrun simctl list`; the inventory currently includes newer runtimes and does not establish an available iOS 17 simulator. Building against a newer SDK does not prove iOS 17 runtime behavior. — [Apple TN2339](https://developer.apple.com/library/archive/technotes/tn2339/_index.html); [Runner SDK/simulator inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md)

### Gaps

- **UNVERIFIED:** No Xcode command, XCTest, simulator run, or device installation was executed in this research task. Windows is the assigned environment; successful Apple execution remains an integration gate under the [repository contract](../../AGENTS.md).
- **UNVERIFIED:** Installed Xcode availability does not establish that the eventual project, shared schemes, resources, or Swift sources compile. No build duration estimate is based on MuseFleet execution.

## 2. What is included, and which build execution path respects the prohibition on costs?

### Takeaway

**OFFICIAL:** Standard public-repository runner compute is free. Private-repository macOS compute draws from the owner's shared included value and can incur charges after depletion. **INFERENCE:** Until repository visibility or enforceable no-overage controls are verified, leave the hosted build undispatched; a failed billing API lookup is not a quota check. — [GitHub billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions); [Budget controls](https://docs.github.com/en/billing/how-tos/set-up-budgets)

### Cited Findings

- **OFFICIAL:** The live billing article expresses included compute as monetary value, not a fixed number of minutes: GitHub Free / Free for organizations **$12 per month**, Pro / Team **$18**, and Enterprise Cloud **$300**. Artifact allowances are respectively 500 MB, 1 GB for Pro, 2 GB for Team, and 50 GB for Enterprise Cloud. Included compute resets each billing cycle and may be consumed by other eligible uses, including private runner jobs and cloud sandbox compute/memory. — [GitHub billing, included usage table](https://docs.github.com/en/billing/concepts/product-billing/github-actions#included-compute-usage-and-storage)
- **OFFICIAL:** Standard macOS M1/Intel runner pricing is **$0.062 USD per minute**, and each job's partial minute is rounded up. Standard Linux x64 pricing is $0.006 per minute. Larger macOS runners have separate higher rates and are billed even for public repositories. — [GitHub runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing)
- **OFFICIAL:** Standard public-repository runner compute is free independently of included compute. Self-hosted runners are also free from GitHub's runner billing, but this statement does not cover the hardware/cloud provider operating those machines. The repository owner is charged for private hosted usage, regardless of who triggered it. — [GitHub billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- **OFFICIAL:** With no valid payment method, usage is blocked after the included compute is consumed. With a valid payment method, additional usage can be charged. An Actions budget stops usage only if **Stop usage when budget limit is reached** is enabled; email alerts alone do not stop it. — [GitHub billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions); [Budget setup](https://docs.github.com/en/billing/how-tos/set-up-budgets)
- **OFFICIAL:** Budgets have product/SKU and account/repository scopes. Any exhausted applicable hard budget blocks additional usage. Newly created budgets only account for metered usage from their creation onward; they do not retroactively account for the entire current billing cycle. — [Budget setup](https://docs.github.com/en/billing/how-tos/set-up-budgets); [First-cycle budget limitation](https://docs.github.com/en/billing/concepts/budgets-and-alerts#your-first-billing-cycle-after-creating-a-budget)
- **OFFICIAL:** Artifact storage and GitHub Packages share a pooled allowance. Cache storage has a separate 10 GB allowance per repository, with overage when its configured storage limit exceeds the included amount. Storage accrues hourly; deleting an artifact stops future accrual but does not erase already accrued usage. Logs and job summaries do not consume artifact storage allowance. — [GitHub storage billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions#how-storage-billing-works)
- **OFFICIAL:** Manual execution requires `workflow_dispatch`, with the workflow present on the default branch. Concurrency groups can limit overlapping runs. A manual trigger or concurrency limit controls when jobs execute; neither is a billing budget. — [Manual workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow); [Concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)

### Inferences

**INFERENCE: Conditional safe execution choices, in preference order.** These are recommendations for the lead, not actions taken by this researcher. — [Billing conditions](https://docs.github.com/en/billing/concepts/product-billing/github-actions); [Budget conditions](https://docs.github.com/en/billing/how-tos/set-up-budgets)

| Path | Evidence required before the first job | Decision under current evidence |
| --- | --- | --- |
| Existing, authorized public repository + standard macOS runner | Verify the intended repository is already public and use a standard label, without `-large` / `-xlarge` or custom images. Independently establish the storage conditions before uploading artifacts. | Technically suitable; target visibility is unverified here. Do not make private source public as an implicit cost workaround. |
| Private repository + enforced no paid overage | Owner verifies account billing, remaining compute/storage, and an applicable Actions hard budget that prevents paid overage, ideally $0 paid usage if the account UI supports it; alternatively verify no valid payment method and no other charge path for the intended usage. | Blocked pending that evidence. Do not use guessed quota as authorization. |
| Existing user-controlled Mac | Verify authorized access and that its use creates no new rental/provider charge. Run Xcode locally or on an appropriately secured runner. | Technically suitable; available hardware/access is unknown. |
| Rental Mac, larger runner, Xcode Cloud purchase, or relay deployment | Explicit permission covering the actual provider and expense. | Outside the authorized zero-cost research scope. |

**INFERENCE: Numerical illustrations, not account balances.** At the current standard macOS rate, an entirely unused $12 allowance covers about 193 whole billed macOS minutes, $18 about 290, and $300 about 4,838, assuming no other shared compute use. A single job capped at 20 minutes represents approximately $1.24 of compute at that rate; failure or cancellation after work begins can still consume usage. These calculations do not authorize execution or bound storage expense. — [Included value](https://docs.github.com/en/billing/concepts/product-billing/github-actions); [Rate and rounding](https://docs.github.com/en/billing/reference/actions-runner-pricing)

**INFERENCE: Proposed first real run after cost evidence exists.** Use one manually dispatched standard macOS job, a 20-minute job timeout, no matrix/retries/schedule, and a concurrency group preventing overlap. Record selected Xcode, SDK, source commit, test results, binary metadata, and artifact SHA-256 in logs. Build and package the real device app in that job. Until artifact storage conditions are verified, retain only non-sensitive logs/summary; retrieving the IPA requires a separately verified artifact upload or local-Mac output. A short artifact retention period reduces exposure and storage duration but is not a no-cost guarantee. — [Manual execution](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow); [Workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax); [Storage billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions#how-storage-billing-works)

### Gaps

- **UNVERIFIED, supplied session context:** The assignment reports authentication as `dungprovaidai` with repository scope but no user scope, and a billing endpoint returning 404. This researcher did not repeat that request or broaden token scopes. It provides no proof of plan, remaining allowance, payment method, or budget enforcement.
- **UNVERIFIED, local observation:** `git remote -v` in the assigned research worktree returned no remote. The target GitHub repository and its visibility could not be verified from local remote configuration. No repository was created, published, or changed to public.
- **UNVERIFIED:** Whether this account's current budget UI accepts $0, which scopes/SKUs it covers, and whether a hard stop is effective for the intended compute and storage are unknown. The public docs establish the stop mechanism, not this account's configuration; a universal guarantee based solely on entering `$0` is not claimed.
- **SOURCE CONFLICT:** Search indexes returned older official-page snippets with 2,000 / 3,000 / 50,000 included minutes, while the fetched canonical article explicitly lists $12 / $18 / $300 included compute. Use the live article and actual account billing view; do not hard-code the older 10x macOS multiplier or treat an old minute table as today's verified balance. — [Canonical billing article](https://docs.github.com/en/billing/concepts/product-billing/github-actions)

## 3. How can a real unsigned arm64 app be packaged without inventing a placeholder IPA?

### Takeaway

**INFERENCE:** Compile a real `iphoneos` app on macOS, disable signing for that build, verify its Mach-O executable and iOS platform, and ZIP the app under `Payload/`. Label the result `unsigned`; manual ZIP packaging establishes artifact structure, while Apple's mandatory signing rules still govern device installation. — [Apple build tooling](https://developer.apple.com/library/archive/technotes/tn2339/_index.html); [IPA structure](https://developer.apple.com/library/archive/qa/qa1798/_index.html); [Mandatory signing](https://support.apple.com/guide/security/app-code-signing-process-sec7c917bf14/web)

### Cited Findings

- **OFFICIAL-ARCHIVE:** Apple's QA1798 describes an IPA as a ZIP that expands to `Payload/YourApp.app`. It documents inspecting the app's signed entitlements and `embedded.mobileprovision` separately. This supports the container structure; it does not document unsigned installation. — [Apple QA1798](https://developer.apple.com/library/archive/qa/qa1798/_index.html)
- **OFFICIAL:** iOS requires executable code signed using an Apple-issued certificate. A provisioning profile authorizes who may sign, the app identity, allowed devices, validity period, and entitlements. Repacking a ZIP does not supply that authorization. — [Apple Platform Security](https://support.apple.com/guide/security/app-code-signing-process-sec7c917bf14/web); [Apple TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
- **OFFICIAL-ARCHIVE:** Apple's supported distribution flow uses an Xcode archive and `xcodebuild -exportArchive ... -exportOptionsPlist ...`. Available export options must be obtained from the installed `xcodebuild -help`, rather than assuming an old list applies to a new Xcode. — [Apple TN2339](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)

### Inferences

**INFERENCE: Example macOS-only artifact recipe, not executed here.** The signing-disabled build flags and the following checks are an engineering proposal. The cited Apple documentation establishes the underlying build tool, ZIP structure, and signing boundary, not an official guarantee that every Xcode project can be exported unsigned. This block assumes the integrated project's shared scheme and product are both named `MuseFleet`; adjust to the actual project once integrated. Do not edit Apple's SDK settings to disable signing. — [Apple TN2339](https://developer.apple.com/library/archive/technotes/tn2339/_index.html); [Apple QA1798](https://developer.apple.com/library/archive/qa/qa1798/_index.html)

```bash
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer
test -d "$DEVELOPER_DIR"
scratch=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:?}}/musefleet-build.XXXXXX")
xcodebuild -version
xcodebuild -showsdks
xcodebuild -project MuseFleet.xcodeproj -scheme MuseFleet \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$scratch/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  IPHONEOS_DEPLOYMENT_TARGET=17.0 ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build

app="$scratch/DerivedData/Build/Products/Release-iphoneos/MuseFleet.app"
test -f "$app/Info.plist"
executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")
test -n "$executable"
test -s "$app/$executable"
test -x "$app/$executable"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$app/Info.plist")" = iPhoneOS
test "$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app/Info.plist")" = 17.0
file "$app/$executable" > "$scratch/binary.txt"
grep -q 'Mach-O 64-bit executable arm64' "$scratch/binary.txt"
xcrun lipo -verify_arch arm64 "$app/$executable"
xcrun vtool -show-build "$app/$executable" > "$scratch/build-version.txt"
awk '$1 == "platform" && $2 == "IOS" { found=1 } END { exit !found }' "$scratch/build-version.txt"
awk '$1 == "minos" && $2 == "17.0" { found=1 } END { exit !found }' "$scratch/build-version.txt"
cat "$scratch/binary.txt" "$scratch/build-version.txt"

mkdir -p "$scratch/stage/Payload"
ditto "$app" "$scratch/stage/Payload/MuseFleet.app"
ipa="$scratch/MuseFleet-unsigned.ipa"
(cd "$scratch/stage" && /usr/bin/zip -qry "$ipa" Payload)
unzip -t "$ipa"
shasum -a 256 "$ipa"
```

- **INFERENCE:** Check both architecture and Mach-O build platform. Apple Silicon simulators also use arm64; an architecture check alone cannot establish a device IPA. Require the `Release-iphoneos` output, `iPhoneOS` platform metadata, a real executable, and `IOS` rather than `IOSSIMULATOR` in the build load command. Do not create an IPA if compilation or any check fails. — [Apple's separate device and simulator destinations](https://developer.apple.com/library/archive/technotes/tn2339/_index.html); [Apple platform-specific archive guidance](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
- **INFERENCE:** Upload only the validated IPA and a digest/short build manifest after storage conditions are cleared. Re-open the ZIP and repeat executable/platform checks on its actual contents in the implementation. Do not upload `DerivedData`, the entire runner temp folder, signing inputs, or an empty ZIP renamed `.ipa`. Report separately whether the artifact is unsigned, correctly signed, and installed on a real device. — [IPA inspection](https://developer.apple.com/library/archive/qa/qa1798/_index.html); [GitHub artifact handling](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)

### Gaps

- **UNVERIFIED:** The example was not run on macOS and has not validated the future project's names, output path, signing behavior, or Mach-O command output. No IPA was produced in this research task.
- **UNVERIFIED:** A correct Mach-O/container check does not establish launch success, UI correctness, Muse compatibility, or a particular re-signing tool's support. Manual packaging is a handoff artifact, not an Apple-approved distribution route by itself.

## 4. How should signed IPA provisioning use a secure temporary keychain?

### Takeaway

**OFFICIAL:** GitHub documents importing a password-protected signing `.p12` and provisioning profile from secrets into a temporary macOS keychain. **INFERENCE:** Apply that pattern only to trusted, manually selected source and export through Xcode with the exact team's profile; destroy temporary signing material on every exit. — [GitHub Apple signing guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications); [GitHub workflow security](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)

### Cited Findings

- **OFFICIAL:** GitHub's documented secret inputs are `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `BUILD_PROVISION_PROFILE_BASE64`, and a keychain password. The guide creates/unlocks a temporary keychain, imports the certificate, sets the Apple tool key partition list, and installs an iOS `.mobileprovision` profile. Base64 is the transfer encoding in that pattern; the secret store protects the input. — [GitHub Apple signing guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- **OFFICIAL:** Standard GitHub-hosted macOS runner VMs are destroyed after the job. On self-hosted runners, cleaning `$RUNNER_TEMP` alone does not necessarily remove installed keychains and profiles; GitHub explicitly demonstrates cleanup with `if: always()`. — [GitHub signing cleanup](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications#required-clean-up-on-self-hosted-runners)
- **OFFICIAL:** GitHub recommends minimum `GITHUB_TOKEN` privileges and warns that untrusted code in privileged workflows can expose referenced secrets. It documents pinning actions to full commit SHAs when workflow dependency lockfiles are not used. — [GitHub workflow security](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- **OFFICIAL:** An app's requested entitlements must be authorized by its profile; the profile is an allowlist and is not itself the application's code signature. Apple's TN3125 recommends Xcode for signing on Apple platforms and describes `security cms` / `codesign` for inspection. — [Apple TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)

### Inferences

**INFERENCE: Recommended signed-job sequence derived from the official patterns.** — [GitHub signing guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications); [Apple archive/export tooling](https://developer.apple.com/library/archive/technotes/tn2339/_index.html); [Apple provisioning semantics](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)

1. Require the same cost evidence as the unsigned job. Keep signing optional and fail if the requested signing inputs are incomplete. Use a trusted ref, read-only contents permission where possible, and audited actions. Do not execute an untrusted PR checkout with signing secrets.
2. Use `umask 077` and a unique task directory under `$RUNNER_TEMP`. Decode the certificate and profile there without tracing commands or printing their contents. Generate a random keychain password per run and mask it if it could reach logs.
3. Create/unlock a task-specific keychain using `security create-keychain` / `security unlock-keychain`. Import the `.p12` and set `security set-key-partition-list -S apple-tool:,apple:`. Prefer restricting imported key access to `/usr/bin/codesign` with `security import -T /usr/bin/codesign` rather than granting every application access with `-A`; confirm the selected Xcode works with that restriction.
4. Decode the profile into a protected file for validation. Verify expiration, team, bundle identifier, profile kind, signing-certificate membership, required entitlements, and registered target device for development/ad hoc use. Do not print the full decoded profile, device list, private key, or environment. Install only the validated profile. Profile parsing is a diagnostic preflight, not a replacement for Xcode/device signature validation.
5. Archive with normal signing enabled and the intended team/profile. Use `xcodebuild -exportArchive` with an explicit export options plist generated for the installed Xcode and intended distribution method. Check `xcodebuild -help` for accepted method names; do not blindly copy legacy `app-store`, `ad-hoc`, or `development` strings into a newer toolchain. Without a separately authorized reason, avoid `-allowProvisioningUpdates` and automatic device/certificate creation; supplied local signing assets support a controlled manual path.
6. Inspect the **exported** app after export, not just its archive: signature integrity, signing team, bundle identifier, expiry and profile authorizations, allowed devices, and final entitlements. Use `codesign --verify --strict`, `codesign --display --entitlements - --xml`, and `security cms -D -i .../embedded.mobileprovision` with protected output files. Export can change entitlements. Device installation is still a separate test.
7. Remove the created profile, decoded certificate/profile files, and temporary keychain in both an exit trap and an `always()` cleanup step. On an authorized self-hosted Mac, restore any keychain search-list changes and remove only task-created items. Upload an explicit artifact allowlist, never the signing workspace or keychain.

**INFERENCE:** These inputs are Apple code-signing assets; they provide no reason to collect Muse passwords, OTPs, cookies, or tokens. They also do not require putting an Apple Account password or OTP into repository source or this report. — [GitHub's certificate/profile secret pattern](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications); [Repository security contract](../../AGENTS.md)

### Gaps

- **UNVERIFIED:** No Apple Developer Program membership, team, certificate/private key, profile, device registration, or secret configuration was inspected or supplied to this researcher.
- **UNVERIFIED:** The restricted import ACL, selected Xcode export method, final IPA signature, and installation must be validated on macOS/device before the signed pipeline is called working. No secrets were imported and no profiles were created here.

## 5. Which legitimate installation/distribution routes apply, and what are their limits?

### Takeaway

**OFFICIAL:** A free Personal Team supports temporary testing on the developer's devices. Development/ad hoc, TestFlight, App Store, enterprise, and regional alternative distribution each have their own signing and eligibility rules. An unsigned IPA or local ad-hoc code signature is not a universal installation route. — [Apple account overview](https://developer.apple.com/help/account/basics/about-your-developer-account); [Apple provisioning](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles); [Alternative distribution](https://support.apple.com/en-us/118110)

### Cited Findings

| Classification and route | Officially documented limitations | Source |
| --- | --- | --- |
| **OFFICIAL: Personal Team, free** | Sign in to an Apple Account in Xcode. Up to 10 App IDs and 3 devices, expiring after 7 days; up to 3 apps per device. Installation profiles expire 7 days from issuance, requiring rebuild/reinstall. | [Apple account overview](https://developer.apple.com/help/account/basics/about-your-developer-account) |
| **OFFICIAL: Paid Apple Developer Program** | Membership is $99 USD per membership year, with local pricing/eligible waivers. An existing membership cannot be presumed, and purchasing one would require permission in this task. | [Apple enrollment terms](https://developer.apple.com/programs/enroll/) |
| **OFFICIAL: Ad hoc distribution** | Requires a matching App ID, distribution certificate, and registered devices in the profile. Developer Program members can register up to 100 devices per product family per membership year; disabling a device does not recover that year's slot. | [Create an ad hoc profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile); [Device limits](https://developer.apple.com/help/account/devices/devices-overview) |
| **OFFICIAL: TestFlight** | Upload to App Store Connect, with eligible identifiers/profiles. Builds last up to 90 days. Up to 100 internal App Store Connect users and 10,000 external testers; the first external-testing build requires review, and later builds may also need review. | [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview) |
| **OFFICIAL: App Store-signed export** | A pre-submission app signed for App Store distribution cannot simply be run locally; Apple checks/re-signs the app for distribution. Use the store/TestFlight workflow rather than treating that IPA as ad hoc. | [Apple TN3125, “The where”](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles) |
| **OFFICIAL: Enterprise/in-house** | Eligible organizations may distribute proprietary apps to their own employees; membership/authorization and certificate/profile validity apply. This is not a general public sideloading substitute. | [Apple Platform Security, in-house apps](https://support.apple.com/guide/security/app-code-signing-process-sec7c917bf14/web) |
| **OFFICIAL: Regional alternative distribution** | Apple's current support article lists Brazil, Japan, and the EU, with region-specific device/platform options. Apple Account region and physical location must qualify. Apps still undergo notarization; EU web distribution is an eligibility-governed route. | [Apple alternative distribution, updated 2026-10-26](https://support.apple.com/en-us/118110) |

- **OFFICIAL:** Developer Mode applies to running development-signed apps through Xcode or installing an IPA with Apple Configurator. Ordinary App Store and TestFlight installation are unaffected. Enabling Developer Mode does not remove signing/provisioning requirements. — [Apple Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device); [Mandatory signing](https://support.apple.com/guide/security/app-code-signing-process-sec7c917bf14/web)
- **OFFICIAL:** Provisioning profiles contain expiration dates; validity varies by type and is typically no more than a year outside the macOS Developer ID exception. Check the actual profile rather than promising a fixed lifetime for a signed IPA. — [Apple TN3125, “The when”](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)

### Inferences

- **INFERENCE:** For one owner's iPhone, the lowest additional-cost official path is an available Mac/Xcode with a Personal Team, accepting 7-day reprovisioning and unsupported advanced capabilities. If the owner already has paid membership, a development/ad hoc export with the actual iPhone registered is a practical direct-test route; TestFlight suits broader beta testing. — [Account overview](https://developer.apple.com/help/account/basics/about-your-developer-account); [Ad hoc profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile); [TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)
- **INFERENCE:** Distinguish Apple **Ad Hoc distribution** (distribution certificate plus an authorized registered-device profile) from `codesign -s -` local ad-hoc signing. The latter does not create Apple authorization. Any legitimate third-party re-signing/install tool remains subject to the team/profile/device/capability restrictions; no particular Windows tool is endorsed or verified by this research. — [Mandatory Apple-issued signing](https://support.apple.com/guide/security/app-code-signing-process-sec7c917bf14/web); [Provisioning authorizations](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
- **INFERENCE:** Do not claim universal Windows-only deployment, unlimited free sideloading, permanent Personal Team installation, or regional alternative-distribution eligibility for the user. None follows from producing an IPA. — [Personal Team restrictions](https://developer.apple.com/help/account/basics/about-your-developer-account); [Alternative distribution requirements](https://support.apple.com/en-us/118110)

### Gaps

- **UNVERIFIED:** The user's actual iPhone OS, Apple Account region, physical distribution eligibility, Developer Mode state, registered UDID, membership, and access to an existing Mac are unknown. No sideloading tool or device trust setting was changed.
- **UNVERIFIED:** App Review acceptance of MuseFleet and rights/terms governing its eventual distribution have not been evaluated by this build/distribution research. The report does not promise approval.

## 6. What signing and infrastructure are necessary for APNs?

### Takeaway

**OFFICIAL:** Remote push requires a push-enabled App ID, the signed iOS `aps-environment` entitlement authorized by provisioning, APNs device registration, and a provider server. **INFERENCE:** Keep baseline local notifications separate from any future APNs configuration; an unsigned build, Personal Team install, or entitlement plist alone does not establish remote push. — [Apple APNs registration](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns); [APS entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment); [Provider server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)

### Cited Findings

- **OFFICIAL:** Enable Push Notifications in Xcode and enable the push notification service for the app's App ID in the developer account. Registration can fail if the app lacks the proper code-signing entitlement. — [Apple APNs registration](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)
- **OFFICIAL:** The iOS entitlement is `aps-environment`, with `development` for the sandbox environment and `production` for production profiles and TestFlight/prerelease distribution. Xcode derives the value from the current provisioning profile. The macOS entitlement `com.apple.developer.aps-environment` is a different key and should not be substituted for the iOS one. — [Apple APS entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment); [macOS counterpart](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.aps-environment)
- **OFFICIAL-ARCHIVE:** Apple explicitly states that APNs is unavailable to Personal Teams. This is an official WWDC explanation, not a current quota/price source; the current account overview separately establishes that advanced capabilities require program membership. — [WWDC19 session 304, approximately 6:43–7:45](https://developer.apple.com/videos/play/wwdc2019/304/); [Current account overview](https://developer.apple.com/help/account/basics/about-your-developer-account)
- **OFFICIAL:** Entitlements claimed in the app's signature must be authorized by the profile. Putting `aps-environment` into a source plist does not itself grant the capability. Inspect the final exported IPA because distribution export can reapply entitlements. — [Apple TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles); [Apple QA1798](https://developer.apple.com/library/archive/qa/qa1798/_index.html)
- **OFFICIAL:** The app obtains a device token unique to that app/device, forwards it securely to the provider server, and handles registration failures. Apple cautions against caching device tokens as permanent values; obtain an up-to-date token on registration. — [Apple APNs registration](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)
- **OFFICIAL:** The developer is responsible for the provider server, event/payload generation, receiving device tokens, and authenticated TLS/HTTP2 communication with APNs. APNs attempts delivery and may store or coalesce notifications; the documentation does not guarantee delivery of every event at a fixed time. — [Apple provider-server documentation](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)

### Inferences

- **INFERENCE:** For a future APNs-enabled build, validate that both the profile and **exported signature** contain an authorized, appropriate `aps-environment`; use the matching APNs environment and topic, then prove real registration and delivery on the installed app. Build success or a simulated payload is insufficient. — [APS environment](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment); [Registration](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns); [Export inspection](https://developer.apple.com/library/archive/qa/qa1798/_index.html)
- **INFERENCE:** Keep provider credentials on an authorized provider system rather than embedding them in an IPA. A future server also needs an authorized source of Muse events; APNs signing only solves notification delivery authorization. It does not create official Muse webhooks, observe a suspended WebView, or establish 24/7 monitoring. Do not deploy a relay or buy hosting as part of a build task. — [Provider responsibilities](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server); [Repository notification/cost contract](../../AGENTS.md)

### Gaps

- **UNVERIFIED:** No push-enabled MuseFleet App ID, signing entitlement, provider credentials, authorized event source, APNs device registration, or end-to-end delivery was verified. No provider deployment or billable action was performed.
- **UNVERIFIED:** This report does not establish official Muse webhook/APNs support or background observation. Those require separate first-party evidence and implementation/device checks.
