#!/usr/bin/env python3
"""macOS CI entry points; subprocess arguments never pass through a shell."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zipfile

from generate_project import ROOT
from validate_ipa import require, validate_ipa


def run(arguments, stage, capture=False, env=None):
    print(stage, flush=True)
    result = subprocess.run([str(item) for item in arguments], cwd=ROOT, env=env,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None, text=True)
    require(result.returncode == 0, stage + " failed")
    return result.stdout if capture else None


def write_environment(key, value):
    require("\n" not in value and "\r" not in value, "Unsafe environment output")
    with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as handle:
        handle.write(f"{key}={value}\n")


def select_xcode():
    candidates = set(Path("/Applications").glob("Xcode*.app/Contents/Developer"))
    current = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True)
    if current.returncode == 0:
        candidates.add(Path(current.stdout.strip()))
    usable = []
    for developer in sorted(candidates):
        binary = developer / "usr/bin/xcodebuild"
        if not binary.is_file():
            continue
        environment = {**os.environ, "DEVELOPER_DIR": str(developer)}
        version = subprocess.run([str(binary), "-version"], capture_output=True, text=True, env=environment)
        sdks = subprocess.run([str(binary), "-showsdks"], capture_output=True, text=True, env=environment)
        match = re.search(r"^Xcode (\d+)(?:\.(\d+))?(?:\.(\d+))?", version.stdout)
        ios = re.findall(r"-sdk iphoneos(\d+)(?:\.(\d+))?", sdks.stdout)
        if version.returncode == sdks.returncode == 0 and match and any(int(item[0]) >= 17 for item in ios):
            usable.append((tuple(int(item or 0) for item in match.groups()), str(developer)))
    require(usable, "No preinstalled Xcode with an iOS 17+ SDK is available")
    version, developer = max(usable)
    write_environment("DEVELOPER_DIR", developer)
    print("Selected installed Xcode " + ".".join(map(str, version)))


def choose_simulator(data):
    candidates = []
    for runtime, devices in data.get("devices", {}).items():
        match = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+(?:-\d+)*)", runtime)
        if not match:
            continue
        version = tuple(int(part) for part in match[1].split("-"))
        if version[0] < 17:
            continue
        for device in devices:
            if device.get("isAvailable") is True and device.get("name", "").startswith("iPhone"):
                udid = device.get("udid", "")
                if re.fullmatch(r"[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}", udid):
                    candidates.append((version, device.get("state") == "Booted", device["name"], udid))
    require(candidates, "No available iPhone simulator running iOS 17+; install a runtime before retrying")
    return max(candidates)[-1]


def project_arguments():
    return ["xcodebuild", "-project", "MuseFleet.xcodeproj", "-scheme", "MuseFleet"]


def test():
    require((ROOT / "App/MuseFleetApp.swift").is_file(), "Merge application sources before running Apple builds")
    require(any((ROOT / "Tests/CoreTests").rglob("*.swift")) and any((ROOT / "BrowserTests").rglob("*.swift"))
            and any((ROOT / "UITests").rglob("*.swift")), "Core, browser, and UI test sources are required")
    run([sys.executable, "scripts/generate_project.py", "--check"], "Check generated project")
    run(["plutil", "-lint", "MuseFleet.xcodeproj/project.pbxproj", "Config/Info.plist",
         "Config/PrivacyInfo.xcprivacy", "Config/Push.entitlements"], "Validate project and plist syntax with Apple tooling")
    listing = json.loads(run(["xcrun", "simctl", "list", "devices", "available", "--json"], "Find available simulators", capture=True))
    simulator = choose_simulator(listing)
    selected = next(device for devices in listing["devices"].values() for device in devices if device.get("udid") == simulator)
    if selected.get("state") != "Booted":
        run(["xcrun", "simctl", "boot", simulator], "Boot selected iPhone simulator")
    run(["xcrun", "simctl", "bootstatus", simulator, "-b"], "Wait for simulator boot")
    (ROOT / "artifacts").mkdir(exist_ok=True)
    (ROOT / "artifacts/simulator.json").write_text(json.dumps({"udid": simulator, "name": selected["name"]}, indent=2) + "\n")
    # Simulator Keychain access needs a local signature; no Apple identity or profile is used.
    base = project_arguments() + ["-destination", "platform=iOS Simulator,id=" + simulator,
                                 "-derivedDataPath", "build/Simulator", "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-"]
    run(base + ["-resolvePackageDependencies"], "Resolve package dependencies (none expected)")
    run(base + ["-resultBundlePath", "artifacts/Build.xcresult", "build-for-testing"], "Build application and unit/UI test bundles")
    run(base + ["-resultBundlePath", "artifacts/Tests.xcresult", "-parallel-testing-enabled", "NO",
                "-maximum-concurrent-test-simulator-destinations", "1", "-test-timeouts-enabled", "YES",
                "-maximum-test-execution-time-allowance", "180", "test-without-building"], "Run hosted unit and UI tests")
    run(["xcrun", "xcresulttool", "export", "attachments", "--path", "artifacts/Tests.xcresult",
         "--output-path", "artifacts/screenshots"], "Export actual simulator test attachments")


def build_version(environment):
    version = environment.get("INPUT_VERSION", "").strip()
    if not version and environment.get("GITHUB_REF_TYPE") == "tag":
        version = environment.get("GITHUB_REF_NAME", "").removeprefix("v")
    elif not version:
        version = "1.0.0"
    require(re.fullmatch(r"[0-9]{1,3}(?:\.[0-9]{1,3}){2}", version), "Version must have three numeric components, such as 1.0.0")
    number = environment.get("GITHUB_RUN_NUMBER", "1")
    require(re.fullmatch(r"[1-9][0-9]{0,3}", number), "Build number must be 1...9999 to fit Apple's bundle-version format")
    return version, number


def package_app(app, ipa):
    require(app.is_dir() and (app / "Info.plist").is_file(), "Built application was not produced")
    with zipfile.ZipFile(ipa, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(app.rglob("*")):
            require(not path.is_symlink(), "Unexpected symlink in iOS application bundle")
            if path.is_file():
                archive.write(path, "Payload/" + app.name + "/" + path.relative_to(app).as_posix())


def build_ipa():
    version, number = build_version(os.environ)
    signed_value = os.environ.get("INPUT_SIGNED", "false")
    require(signed_value in {"true", "false"}, "Invalid signing input")
    signed = signed_value == "true"
    signing_directory = Path(os.environ["RUNNER_TEMP"]) / "musefleet-signing"
    artifacts = ROOT / "artifacts"
    artifacts.mkdir(exist_ok=True)
    base = project_arguments() + ["-configuration", "Release", "-destination", "generic/platform=iOS",
                                 "-sdk", "iphoneos", "-derivedDataPath", "build/Device", "ARCHS=arm64", "ONLY_ACTIVE_ARCH=NO",
                                 "MARKETING_VERSION=" + version, "CURRENT_PROJECT_VERSION=" + number]
    run(base + ["-resolvePackageDependencies"], "Resolve device build dependencies")
    if signed:
        settings = json.loads((signing_directory / "build-settings.json").read_text())
        require(isinstance(settings, dict) and settings.get("CODE_SIGNING_ALLOWED") == "YES", "Signing setup has not completed")
        run(base + [key + "=" + value for key, value in settings.items()] + ["-archivePath", "build/MuseFleet.xcarchive",
                    "-resultBundlePath", "artifacts/Archive.xcresult", "archive"], "Archive signed arm64 application")
        run(["xcodebuild", "-exportArchive", "-archivePath", "build/MuseFleet.xcarchive",
             "-exportOptionsPlist", signing_directory / "ExportOptions.plist", "-exportPath", "build/Export"], "Export signed IPA")
        exported = list((ROOT / "build/Export").glob("*.ipa"))
        require(len(exported) == 1, "Export did not produce exactly one IPA")
        ipa = artifacts / "MuseFleet-signed.ipa"
        exported[0].replace(ipa)
    else:
        run(base + ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "CODE_SIGN_ENTITLEMENTS=",
                    "-resultBundlePath", "artifacts/Device.xcresult", "build"], "Build unsigned arm64 application")
        ipa = artifacts / "MuseFleet-unsigned.ipa"
        package_app(ROOT / "build/Device/Build/Products/Release-iphoneos/MuseFleet.app", ipa)
    metadata = validate_ipa(ipa, "signed" if signed else "unsigned", codesign=True)
    require(metadata["version"] == version and metadata["build"] == number, "Exported version/build does not match inputs")
    metadata.update({"commit": os.environ.get("GITHUB_SHA"), "run_id": os.environ.get("GITHUB_RUN_ID"),
                     "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"), "runner_os": sys.platform,
                     "xcode": run(["xcodebuild", "-version"], "Record Xcode version", capture=True).strip()})
    (artifacts / "build-metadata.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    (artifacts / (ipa.name + ".sha256")).write_text(metadata["sha256"] + "  " + ipa.name + "\n", encoding="utf-8")
    print("Validated IPA, SHA-256 checksum, and build metadata are ready as workflow artifacts.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("select-xcode", "test", "build-ipa"))
    args = parser.parse_args()
    try:
        require(sys.platform == "darwin", "Apple builds require macOS; no Apple test success is inferred on Windows")
        {"select-xcode": select_xcode, "test": test, "build-ipa": build_ipa}[args.action]()
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(1, f"Pipeline failed: {error}\n")


if __name__ == "__main__":
    main()
