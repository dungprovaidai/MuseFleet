#!/usr/bin/env python3
"""Ephemeral Apple signing setup. Secrets are read from environment, never logged."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import subprocess
import sys

from validate_ipa import load_plist


BUNDLE_ID = "com.dungprovaidai.musefleet"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def secure_run(arguments, stage):
    result = subprocess.run(arguments, capture_output=True)
    if result.returncode:
        raise ValueError(f"Apple signing operation failed: {stage} (details withheld to protect credentials)")
    return result.stdout


def validate_profile(profile, team, now=None):
    require(isinstance(profile, dict), "Provisioning profile must be a dictionary")
    require(isinstance(team, str) and re.fullmatch(r"[A-Z0-9]{10}", team), "Invalid Apple team identifier")
    require(profile.get("TeamIdentifier") == [team], "Provisioning profile team mismatch")
    require(isinstance(profile.get("Platform"), list) and "iOS" in profile["Platform"], "Provisioning profile is not for iOS")
    uuid = profile.get("UUID")
    require(isinstance(uuid, str) and re.fullmatch(r"[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}", uuid),
            "Invalid provisioning profile UUID")
    now = now or datetime.now(timezone.utc)
    for field in ("CreationDate", "ExpirationDate"):
        require(isinstance(profile.get(field), datetime), "Provisioning profile has invalid dates")
    created = profile["CreationDate"].replace(tzinfo=timezone.utc)
    expires = profile["ExpirationDate"].replace(tzinfo=timezone.utc)
    require(created <= now < expires, "Provisioning profile is expired or not yet valid")
    entitlements = profile.get("Entitlements")
    require(isinstance(entitlements, dict), "Provisioning profile has no entitlements")
    require(entitlements.get("application-identifier") == team + "." + BUNDLE_ID,
            "An explicit provisioning profile matching the MuseFleet bundle is required")
    require(entitlements.get("com.apple.developer.team-identifier") == team, "Entitlement team mismatch")
    require(type(entitlements.get("get-task-allow", False)) is bool, "Invalid debugging entitlement")
    aps = entitlements.get("aps-environment")
    require(aps is None or isinstance(aps, str) and aps in {"development", "production"}, "Invalid APNs environment")
    devices = profile.get("ProvisionedDevices", [])
    require(isinstance(devices, list) and all(isinstance(item, str) and re.fullmatch(r"(?:[A-Fa-f0-9]{40}|[A-Fa-f0-9]{8}-[A-Fa-f0-9]{16})", item)
                                            for item in devices), "Invalid provisioned device list")
    all_devices = profile.get("ProvisionsAllDevices", False)
    require(type(all_devices) is bool and not (devices and all_devices), "Invalid distribution/device combination")
    debugging = entitlements.get("get-task-allow", False)
    if debugging:
        require(devices and not all_devices, "Development signing requires registered devices")
        method = "debugging"
    elif devices:
        method = "release-testing"
    elif all_devices:
        method = "enterprise"
    else:
        method = "app-store-connect"
    require(aps is None or aps == ("development" if debugging else "production"), "APNs environment conflicts with distribution mode")
    certificates = profile.get("DeveloperCertificates")
    require(isinstance(certificates, list) and certificates and all(isinstance(item, bytes) and item for item in certificates),
            "Provisioning profile has no signing certificates")
    return {"uuid": uuid, "team": team, "method": method, "aps_environment": aps,
            "certificate_hashes": {hashlib.sha1(item).hexdigest().upper() for item in certificates}}


def decode_profile(path):
    data = secure_run(["/usr/bin/openssl", "smime", "-verify", "-inform", "DER", "-noverify", "-in", str(path)],
                      "decode provisioning profile")
    return load_plist(data)


def profile_directory():
    version = secure_run(["xcodebuild", "-version"], "read Xcode version").decode()
    match = re.search(r"^Xcode (\d+)", version)
    require(match, "Unable to determine Xcode version for provisioning profile installation")
    relative = "Library/Developer/Xcode/UserData/Provisioning Profiles" if int(match[1]) >= 16 else "Library/MobileDevice/Provisioning Profiles"
    return Path.home() / relative


def verify_signed_app(bundle):
    secure_run(["codesign", "--verify", "--deep", "--strict", str(bundle)], "verify application signature")
    raw = secure_run(["codesign", "--display", "--entitlements", ":-", str(bundle)], "read application entitlements")
    entitlements = load_plist(raw)
    require(isinstance(entitlements, dict), "Invalid signed application entitlements")
    team = entitlements.get("com.apple.developer.team-identifier")
    profile = decode_profile(bundle / "embedded.mobileprovision")
    validated = validate_profile(profile, team)
    require(entitlements.get("application-identifier") == team + "." + BUNDLE_ID, "Signed bundle entitlement mismatch")
    require(entitlements.get("aps-environment") == validated["aps_environment"], "Signed APNs entitlement mismatch")
    require(entitlements.get("get-task-allow", False) == profile["Entitlements"].get("get-task-allow", False),
            "Signed debugging entitlement mismatch")
    for key, value in entitlements.items():
        permitted = profile["Entitlements"].get(key)
        if isinstance(value, list):
            require(isinstance(permitted, list) and all(isinstance(item, str) and any(
                isinstance(rule, str) and (item == rule or rule.endswith("*") and item.startswith(rule[:-1]))
                for rule in permitted) for item in value), "Signed entitlement is not permitted by profile")
        else:
            require(value == permitted, "Signed entitlement is not permitted by profile")
    # Validate the signing leaf itself against the certificates authorized by the profile.
    import tempfile
    with tempfile.TemporaryDirectory(prefix="musefleet-cert-") as temporary:
        prefix = str(Path(temporary) / "certificate")
        secure_run(["codesign", "--display", "--extract-certificates", prefix, str(bundle)], "read signing certificate")
        certificate = Path(prefix + "0").read_bytes()
        require(hashlib.sha1(certificate).hexdigest().upper() in validated["certificate_hashes"],
                "Signing certificate is not authorized by the embedded profile")


def write_private(path, data):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as handle:
        handle.write(data)


def setup(directory):
    require(sys.platform == "darwin", "Signing requires macOS")
    directory.mkdir(mode=0o700, parents=True, exist_ok=False)
    required = ("APPLE_CERTIFICATE_BASE64", "APPLE_CERTIFICATE_PASSWORD", "APPLE_PROVISIONING_PROFILE_BASE64", "APPLE_TEAM_ID")
    require(all(os.environ.get(key) for key in required), "Missing Apple signing secrets")
    try:
        certificate = base64.b64decode(os.environ["APPLE_CERTIFICATE_BASE64"], validate=True)
        mobileprofile = base64.b64decode(os.environ["APPLE_PROVISIONING_PROFILE_BASE64"], validate=True)
    except ValueError:
        raise ValueError("Invalid base64 signing secret") from None
    require(0 < len(certificate) < 16 * 1024 * 1024 and 0 < len(mobileprofile) < 16 * 1024 * 1024,
            "Invalid signing secret size")
    p12 = directory / "certificate.p12"
    profile_path = directory / "profile.mobileprovision"
    write_private(p12, certificate)
    write_private(profile_path, mobileprofile)
    profile = validate_profile(decode_profile(profile_path), os.environ["APPLE_TEAM_ID"])
    installed = profile_directory() / (profile["uuid"] + ".mobileprovision")
    require(not installed.exists(), "Refusing to replace an existing provisioning profile")
    original_keychains = shlex.split(secure_run(["security", "list-keychains", "-d", "user"], "read keychain list").decode())
    keychain = directory / "signing.keychain-db"
    state = {"keychain": str(keychain), "original_keychains": original_keychains, "profile": str(installed)}
    write_private(directory / "cleanup.json", json.dumps(state).encode())
    password = os.environ.get("KEYCHAIN_PASSWORD") or secrets.token_urlsafe(32)
    secure_run(["security", "create-keychain", "-p", password, str(keychain)], "create temporary keychain")
    secure_run(["security", "set-keychain-settings", "-lut", "21600", str(keychain)], "configure keychain")
    secure_run(["security", "unlock-keychain", "-p", password, str(keychain)], "unlock keychain")
    secure_run(["security", "import", str(p12), "-k", str(keychain), "-P", os.environ["APPLE_CERTIFICATE_PASSWORD"],
                "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"], "import signing certificate")
    secure_run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, str(keychain)],
               "authorize codesign")
    secure_run(["security", "list-keychains", "-d", "user", "-s", str(keychain), *original_keychains], "set keychain search list")
    identities = secure_run(["security", "find-identity", "-v", "-p", "codesigning", str(keychain)], "validate signing identity").decode()
    matching = sorted(set(re.findall(r"\b[A-F0-9]{40}\b", identities)) & profile["certificate_hashes"])
    require(matching, "No valid certificate/private key matching the provisioning profile")
    identity = matching[0]
    installed.parent.mkdir(parents=True, exist_ok=True)
    write_private(installed, mobileprofile)
    export = {"method": profile["method"], "teamID": profile["team"], "signingStyle": "manual",
              "signingCertificate": identity, "provisioningProfiles": {BUNDLE_ID: profile["uuid"]},
              "manageAppVersionAndBuildNumber": False, "stripSwiftSymbols": True,
              "destination": "export", "uploadSymbols": False}
    write_private(directory / "ExportOptions.plist", plistlib.dumps(export))
    settings = {"CODE_SIGN_STYLE": "Manual", "DEVELOPMENT_TEAM": profile["team"], "CODE_SIGN_IDENTITY": identity,
                "PROVISIONING_PROFILE_SPECIFIER": profile["uuid"], "CODE_SIGNING_ALLOWED": "YES",
                "CODE_SIGN_ENTITLEMENTS": "Config/Push.entitlements" if profile["aps_environment"] else ""}
    if profile["aps_environment"]:
        settings["APS_ENVIRONMENT"] = profile["aps_environment"]
    write_private(directory / "build-settings.json", json.dumps(settings).encode())
    p12.unlink()
    profile_path.unlink()
    print("Validated signing credentials and prepared ephemeral keychain.")


def cleanup(directory):
    state_path = directory / "cleanup.json"
    failures = []
    if state_path.exists():
        state = json.loads(state_path.read_text())
        try:
            secure_run(["security", "list-keychains", "-d", "user", "-s", *state["original_keychains"]], "restore keychain list")
        except ValueError as error:
            failures.append(str(error))
        keychain = Path(state["keychain"])
        require(keychain == directory / "signing.keychain-db", "Unexpected keychain cleanup path")
        if keychain.exists():
            try:
                secure_run(["security", "delete-keychain", str(keychain)], "delete temporary keychain")
            except ValueError as error:
                failures.append(str(error))
        profile = Path(state["profile"])
        allowed = {Path.home() / "Library/MobileDevice/Provisioning Profiles", Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"}
        require(profile.parent in allowed
                and re.fullmatch(r"[A-Fa-f0-9-]{36}\.mobileprovision", profile.name), "Unexpected profile cleanup path")
        profile.unlink(missing_ok=True)
    if directory.exists():
        # Only this task's private signing files; never recurse through unrelated runner paths.
        for name in ("certificate.p12", "profile.mobileprovision", "cleanup.json", "ExportOptions.plist", "build-settings.json"):
            (directory / name).unlink(missing_ok=True)
        directory.rmdir()
    require(not failures, "Signing cleanup failed; " + "; ".join(failures))
    print("Removed ephemeral signing credentials.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("setup", "cleanup"))
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    try:
        (setup if args.action == "setup" else cleanup)(args.directory.resolve())
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Signing failed: {error}\n")


if __name__ == "__main__":
    main()
