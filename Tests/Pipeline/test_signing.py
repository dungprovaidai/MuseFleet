import base64
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from signing import BUNDLE_ID, cleanup, decode_profile, profile_directory, secure_run, setup, validate_profile, verify_signed_app
from validate_ipa import validate_ipa
from test_ipa import bundle as write_bundle_fixture


TEAM = "A1B2C3D4E5"
LEGACY_PREFIX = "LEGACY1234"
NOW = datetime.now(timezone.utc)


def profile_fixture(prefix=TEAM):
    return {"UUID": "11111111-2222-3333-4444-555555555555", "TeamIdentifier": [TEAM], "Platform": ["iOS"],
            "ApplicationIdentifierPrefix": [prefix],
            "CreationDate": (NOW - timedelta(days=1)).replace(tzinfo=None),
            "ExpirationDate": (NOW + timedelta(days=1)).replace(tzinfo=None),
            "Entitlements": {"application-identifier": prefix + "." + BUNDLE_ID,
                             "com.apple.developer.team-identifier": TEAM, "get-task-allow": True},
            "ProvisionedDevices": ["00008110-001234567890001E"], "DeveloperCertificates": [b"synthetic-certificate"]}


class SigningTests(unittest.TestCase):
    def test_legacy_app_id_prefix_is_independent_of_team(self):
        profile = profile_fixture(LEGACY_PREFIX)
        self.assertEqual(validate_profile(profile, TEAM, NOW)["team"], TEAM)
        profile["Entitlements"]["application-identifier"] = TEAM + "." + BUNDLE_ID
        with self.assertRaisesRegex(ValueError, "matching the MuseFleet bundle"):
            validate_profile(profile, TEAM, NOW)
        profile["Entitlements"]["application-identifier"] = LEGACY_PREFIX + "." + BUNDLE_ID
        profile["Entitlements"]["com.apple.developer.team-identifier"] = LEGACY_PREFIX
        with self.assertRaisesRegex(ValueError, "Entitlement team mismatch"):
            validate_profile(profile, TEAM, NOW)

    def test_reject_missing_malformed_or_wrong_app_id_prefix(self):
        for prefixes in (None, [], TEAM, [None], ["bad"], [TEAM + "."], ["*"], ["WRONG12345"]):
            profile = {**profile_fixture(), "ApplicationIdentifierPrefix": prefixes}
            with self.subTest(prefixes=prefixes), self.assertRaises(ValueError):
                validate_profile(profile, TEAM, NOW)

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
        # Trust and Apple tools are mocked; this verifies orchestration, never signing validity.
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

                with patch("signing.sys.platform", "darwin"), patch("signing.decode_profile", return_value=profile), \
                        patch("signing.secure_run", side_effect=fake_run), \
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
        result = subprocess.CompletedProcess([], 1, b"synthetic-secret-output", b"synthetic-secret-error")
        with patch("signing.subprocess.run", return_value=result), self.assertRaises(ValueError) as error:
            secure_run(["security", "synthetic-secret-password"], "import certificate")
        self.assertNotIn("synthetic-secret", str(error.exception))

    def test_blocked_setup_never_materializes_or_imports_private_key_and_cleans_profile(self):
        environment = {"APPLE_CERTIFICATE_BASE64": base64.b64encode(b"synthetic-p12").decode(),
                       "APPLE_CERTIFICATE_PASSWORD": "synthetic-password",
                       "APPLE_PROVISIONING_PROFILE_BASE64": base64.b64encode(b"synthetic-profile").decode(), "APPLE_TEAM_ID": TEAM}
        with tempfile.TemporaryDirectory() as directory:
            signing = Path(directory) / "signing"
            with patch("signing.sys.platform", "darwin"), patch.dict(os.environ, environment), \
                    patch("signing.secure_run") as apple_tools, patch("builtins.print"):
                with self.assertRaisesRegex(ValueError, "Signed mode blocked"):
                    setup(signing)
                apple_tools.assert_not_called()
                self.assertFalse((signing / "certificate.p12").exists())
                self.assertTrue((signing / "profile.mobileprovision").is_file())
                cleanup(signing)
                self.assertFalse(signing.exists())

    def test_cms_content_verification_cannot_bypass_profile_signer_block(self):
        # Even a decoder reporting a valid signature over attacker-chosen metadata is insufficient.
        with tempfile.TemporaryDirectory() as directory:
            profile = Path(directory) / "attacker.mobileprovision"
            profile.write_bytes(plistlib.dumps(profile_fixture()))
            with patch("signing.secure_run", return_value=plistlib.dumps(profile_fixture())) as cms:
                with self.assertRaisesRegex(ValueError, "Apple-issued provisioning profile signer authorization"):
                    decode_profile(profile)
                cms.assert_not_called()

    def check_signed_fixture(self, profile, entitlements=None, certificate=b"synthetic-certificate", failure=None):
        """Exercise codesign arguments and comparisons; profile origin is explicitly mocked."""
        with tempfile.TemporaryDirectory(prefix="musefleet signed test ") as directory:
            bundle = Path(directory) / "MuseFleet.app"
            bundle.mkdir()
            claimed = profile["Entitlements"] if entitlements is None else entitlements

            def fake_run(arguments, stage):
                self.assertEqual(arguments[-1], str(bundle))
                if stage == "verify application signature":
                    self.assertEqual(arguments, ["codesign", "--verify", "--deep", "--strict", str(bundle)])
                    if failure:
                        raise ValueError(failure)
                    return b""
                if stage == "read application entitlements":
                    self.assertEqual(arguments, ["codesign", "--display", "--entitlements", ":-", str(bundle)])
                    return plistlib.dumps(claimed)
                self.assertEqual(stage, "read signing certificate")
                self.assertEqual(len(arguments), 4)
                self.assertEqual(arguments[:2], ["codesign", "--display"])
                self.assertTrue(arguments[2].startswith("--extract-certificates="))
                prefix = arguments[2].split("=", 1)[1]
                self.assertTrue(prefix)
                Path(prefix + "0").write_bytes(certificate)
                return b""

            with patch("signing.decode_profile", return_value=profile) as trusted_fixture, \
                    patch("signing.secure_run", side_effect=fake_run) as codesign:
                verify_signed_app(bundle)
                trusted_fixture.assert_called_once_with(bundle / "embedded.mobileprovision")
                self.assertEqual(codesign.call_count, 3)

    def test_verify_signed_app_extracts_certificate_with_one_option_argument(self):
        for prefix in (TEAM, LEGACY_PREFIX):
            with self.subTest(prefix=prefix):
                self.check_signed_fixture(profile_fixture(prefix))

    def test_verify_signed_app_rejects_wrong_app_prefix_team_certificate_and_signature(self):
        profile = profile_fixture(LEGACY_PREFIX)
        for key, value, reason in (("application-identifier", TEAM + "." + BUNDLE_ID, "bundle entitlement mismatch"),
                                   ("application-identifier", LEGACY_PREFIX + ".com.other.app", "bundle entitlement mismatch"),
                                   ("com.apple.developer.team-identifier", LEGACY_PREFIX, "profile team mismatch")):
            with self.subTest(key=key, value=value), self.assertRaisesRegex(ValueError, reason):
                self.check_signed_fixture(profile, {**profile["Entitlements"], key: value})
        with self.assertRaisesRegex(ValueError, "certificate is not authorized"):
            self.check_signed_fixture(profile, certificate=b"attacker-certificate")
        with self.assertRaisesRegex(ValueError, "synthetic codesign failure"):
            self.check_signed_fixture(profile, failure="synthetic codesign failure")

    def test_verify_signed_app_fails_closed_even_when_codesign_reports_success(self):
        def successful_codesign(arguments, stage):
            if stage == "read application entitlements":
                return plistlib.dumps(profile_fixture()["Entitlements"])
            self.assertEqual(stage, "verify application signature")
            return b""

        with patch("signing.secure_run", side_effect=successful_codesign) as codesign:
            with self.assertRaisesRegex(ValueError, "Signed mode blocked"):
                verify_signed_app(Path("MuseFleet.app"))
            self.assertEqual(codesign.call_count, 2)

    def test_unsigned_validation_does_not_depend_on_blocked_signed_mode(self):
        # Synthetic Mach-O and mocked codesign prove routing only, never an Apple build.
        with tempfile.TemporaryDirectory() as directory:
            archive_path = Path(directory) / "unsigned-parser-fixture.zip"
            with zipfile.ZipFile(archive_path, "w") as archive:
                write_bundle_fixture(archive)
            result = subprocess.CompletedProcess([], 1, b"", b"code object is not signed at all")
            with patch("validate_ipa.sys.platform", "darwin"), patch("validate_ipa.subprocess.run", return_value=result), \
                    patch("signing.verify_signed_app") as signed_check:
                metadata = validate_ipa(archive_path, "unsigned", codesign=True)
                signed_check.assert_not_called()
                self.assertEqual(metadata["signing_mode"], "unsigned")
                self.assertFalse(metadata["code_signature_present"])
                self.assertFalse(metadata["codesign_verified"])

    def test_xcode_version_selects_current_or_legacy_profile_location(self):
        for version, expected in ((15, "Library/MobileDevice/Provisioning Profiles"),
                                  (16, "Library/Developer/Xcode/UserData/Provisioning Profiles"),
                                  (26, "Library/Developer/Xcode/UserData/Provisioning Profiles")):
            with self.subTest(version=version), patch("signing.secure_run", return_value=f"Xcode {version}.3\n".encode()):
                self.assertEqual(profile_directory(), Path.home() / expected)


if __name__ == "__main__":
    unittest.main()
