import base64
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from signing import BUNDLE_ID, cleanup, profile_directory, secure_run, setup, validate_profile


TEAM = "A1B2C3D4E5"
NOW = datetime.now(timezone.utc)


def profile_fixture():
    return {"UUID": "11111111-2222-3333-4444-555555555555", "TeamIdentifier": [TEAM], "Platform": ["iOS"],
            "CreationDate": (NOW - timedelta(days=1)).replace(tzinfo=None),
            "ExpirationDate": (NOW + timedelta(days=1)).replace(tzinfo=None),
            "Entitlements": {"application-identifier": TEAM + "." + BUNDLE_ID,
                             "com.apple.developer.team-identifier": TEAM, "get-task-allow": True},
            "ProvisionedDevices": ["00008110-001234567890001E"], "DeveloperCertificates": [b"synthetic-certificate"]}


class SigningTests(unittest.TestCase):
    def test_profile_distribution_and_optional_push(self):
        for method, debug, devices, all_devices in (("debugging", True, True, False),
                                                  ("release-testing", False, True, False),
                                                  ("enterprise", False, False, True),
                                                  ("app-store-connect", False, False, False)):
            profile = profile_fixture()
            profile["Entitlements"]["get-task-allow"] = debug
            if not devices:
                profile.pop("ProvisionedDevices")
            profile["ProvisionsAllDevices"] = all_devices
            with self.subTest(method=method):
                self.assertEqual(validate_profile(profile, TEAM, NOW)["method"], method)
                self.assertIsNone(validate_profile(profile, TEAM, NOW)["aps_environment"])
                profile["Entitlements"]["aps-environment"] = "development" if debug else "production"
                self.assertEqual(validate_profile(profile, TEAM, NOW)["aps_environment"], profile["Entitlements"]["aps-environment"])

    def test_reject_wrong_bundle_team_expiry_and_distribution(self):
        changes = [("TeamIdentifier", ["ZZZZZZZZZZ"]), ("UUID", "../../bad"), ("Platform", ["macOS"]),
                   ("ExpirationDate", (NOW - timedelta(seconds=1)).replace(tzinfo=None)),
                   ("CreationDate", (NOW + timedelta(days=2)).replace(tzinfo=None)),
                   ("ProvisionedDevices", []), ("ProvisionedDevices", ["bad/device"]),
                   ("ProvisionedDevices", ["--------"]),
                   ("ProvisionsAllDevices", True), ("DeveloperCertificates", []), ("Entitlements", [])]
        for key, value in changes:
            profile = {**profile_fixture(), key: value}
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_profile(profile, TEAM, NOW)
        for key, value in (("application-identifier", TEAM + ".*"),
                           ("application-identifier", TEAM + ".com.other.app"),
                           ("com.apple.developer.team-identifier", "ZZZZZZZZZZ"),
                           ("aps-environment", "production"), ("aps-environment", []), ("get-task-allow", "true")):
            profile = profile_fixture()
            profile["Entitlements"][key] = value
            with self.subTest(entitlement=key), self.assertRaises(ValueError):
                validate_profile(profile, TEAM, NOW)
        with self.assertRaises(ValueError):
            validate_profile(profile_fixture(), "$(unsafe)", NOW)

    def test_mock_setup_and_cleanup_use_only_matching_identity_and_private_files(self):
        # Mocking Apple tools verifies orchestration only, never signing validity.
        profile = profile_fixture()
        identity = hashlib.sha1(profile["DeveloperCertificates"][0]).hexdigest().upper()
        environment = {"APPLE_CERTIFICATE_BASE64": base64.b64encode(b"synthetic-p12").decode(),
                       "APPLE_CERTIFICATE_PASSWORD": "synthetic-password", "APPLE_PROVISIONING_PROFILE_BASE64": base64.b64encode(b"synthetic-profile").decode(),
                       "APPLE_TEAM_ID": TEAM, "KEYCHAIN_PASSWORD": "synthetic-keychain-password"}
        for push in (False, True):
            with self.subTest(push=push), tempfile.TemporaryDirectory() as directory:
                if push:
                    profile["Entitlements"]["aps-environment"] = "development"
                root = Path(directory)
                signing = root / "signing"

                def fake_run(arguments, stage):
                    if stage == "decode provisioning profile":
                        return plistlib.dumps(profile)
                    if stage == "read keychain list":
                        return b'"/original/login.keychain-db"\n'
                    if stage == "read Xcode version":
                        return b'Xcode 26.3\nBuild version synthetic\n'
                    if stage == "create temporary keychain":
                        Path(arguments[-1]).touch()
                    if stage == "delete temporary keychain":
                        Path(arguments[-1]).unlink()
                    if stage == "validate signing identity":
                        return (" 1) " + identity + " synthetic identity\n").encode()
                    return b""

                with patch("signing.sys.platform", "darwin"), patch("signing.secure_run", side_effect=fake_run), \
                        patch("signing.Path.home", return_value=root / "home"), patch.dict(os.environ, environment), patch("builtins.print") as output:
                    setup(signing)
                    self.assertFalse((signing / "certificate.p12").exists())
                    self.assertTrue((root / "home/Library/Developer/Xcode/UserData/Provisioning Profiles" / (profile["UUID"] + ".mobileprovision")).is_file())
                    settings = json.loads((signing / "build-settings.json").read_text())
                    self.assertEqual(settings["CODE_SIGN_IDENTITY"], identity)
                    self.assertEqual(settings["CODE_SIGN_ENTITLEMENTS"], "Config/Push.entitlements" if push else "")
                    export = plistlib.loads((signing / "ExportOptions.plist").read_bytes())
                    self.assertEqual(export["destination"], "export")
                    self.assertFalse(export["uploadSymbols"])
                    cleanup(signing)
                    self.assertFalse(signing.exists())
                    for value in environment.values():
                        self.assertNotIn(value, str(output.call_args_list))

    def test_apple_tool_failure_does_not_expose_secret_arguments_or_output(self):
        import subprocess
        result = subprocess.CompletedProcess([], 1, b"synthetic-secret-output", b"synthetic-secret-error")
        with patch("signing.subprocess.run", return_value=result), self.assertRaises(ValueError) as error:
            secure_run(["security", "synthetic-secret-password"], "import certificate")
        self.assertNotIn("synthetic-secret", str(error.exception))

    def test_partial_setup_failure_is_cleaned_up(self):
        environment = {"APPLE_CERTIFICATE_BASE64": base64.b64encode(b"synthetic-p12").decode(),
                       "APPLE_CERTIFICATE_PASSWORD": "synthetic-password",
                       "APPLE_PROVISIONING_PROFILE_BASE64": base64.b64encode(b"synthetic-profile").decode(), "APPLE_TEAM_ID": TEAM}
        with tempfile.TemporaryDirectory() as directory:
            signing = Path(directory) / "signing"
            with patch("signing.sys.platform", "darwin"), patch.dict(os.environ, environment), \
                    patch("signing.secure_run", side_effect=ValueError("synthetic setup failure")), patch("builtins.print"):
                with self.assertRaises(ValueError):
                    setup(signing)
                self.assertTrue((signing / "certificate.p12").is_file())
                cleanup(signing)
                self.assertFalse(signing.exists())

    def test_xcode_version_selects_current_or_legacy_profile_location(self):
        for version, expected in ((15, "Library/MobileDevice/Provisioning Profiles"),
                                  (16, "Library/Developer/Xcode/UserData/Provisioning Profiles"),
                                  (26, "Library/Developer/Xcode/UserData/Provisioning Profiles")):
            with self.subTest(version=version), patch("signing.secure_run", return_value=f"Xcode {version}.3\n".encode()):
                self.assertEqual(profile_directory(), Path.home() / expected)


if __name__ == "__main__":
    unittest.main()
