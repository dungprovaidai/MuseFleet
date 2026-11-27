import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from apple_pipeline import build_version, choose_simulator, select_xcode


ROOT = Path(__file__).resolve().parents[2]


class PipelineTests(unittest.TestCase):
    def test_version_uses_validated_values_not_shell_code(self):
        self.assertEqual(build_version({"INPUT_VERSION": "2.3.4", "GITHUB_RUN_NUMBER": "17"}), ("2.3.4", "17"))
        self.assertEqual(build_version({"GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v2.0.1"}), ("2.0.1", "1"))
        with self.assertRaises(ValueError):
            build_version({"GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v"})
        for version in ("1.0; touch file", "$(echo bad)", "1.0.0\nBUILD=bad", "--help", "1.0", "1.0.0-beta"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                build_version({"INPUT_VERSION": version})
        for number in ("0", "1\nOTHER=bad", "-1", "xyz", "10000"):
            with self.assertRaises(ValueError):
                build_version({"GITHUB_RUN_NUMBER": number})

    def test_available_iphone_chosen_dynamically(self):
        old = "11111111-1111-1111-1111-111111111111"
        new = "22222222-2222-2222-2222-222222222222"
        device = lambda name, udid, available=True: {"name": name, "udid": udid, "isAvailable": available, "state": "Shutdown"}
        data = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-17-5": [device("iPhone 15", old)],
                            "com.apple.CoreSimulator.SimRuntime.iOS-18-2": [device("iPhone 16", new), device("iPhone unavailable", old, False),
                                                                                      device("iPad Pro", old)],
                            "com.apple.CoreSimulator.SimRuntime.tvOS-18-2": [device("iPhone wrong platform", old)]}}
        self.assertEqual(choose_simulator(data), new)
        with self.assertRaises(ValueError):
            choose_simulator({"devices": {}})

    def test_newest_usable_preinstalled_xcode_is_selected_without_download(self):
        candidates = [Path(f"/Applications/Xcode_{version}.app/Contents/Developer") for version in (16, 26, 27)]

        def fake_run(arguments, **options):
            if arguments == ["xcode-select", "-p"]:
                return subprocess.CompletedProcess(arguments, 1, "", "no selection")
            version = next(value for value in (16, 26, 27) if "Xcode_" + str(value) in arguments[0])
            self.assertEqual(options["env"]["DEVELOPER_DIR"], str(candidates[(16, 26, 27).index(version)]))
            output = f"Xcode {version}.3\n" if arguments[-1] == "-version" else ("macOS SDK only" if version == 27 else f"iOS -sdk iphoneos{version + 2}.0")
            return subprocess.CompletedProcess(arguments, 0, output, "")

        with tempfile.TemporaryDirectory() as directory:
            environment_file = Path(directory) / "github-env"
            with patch("apple_pipeline.Path.glob", return_value=candidates), patch("apple_pipeline.Path.is_file", return_value=True), \
                    patch("apple_pipeline.subprocess.run", side_effect=fake_run), patch.dict(os.environ, {"GITHUB_ENV": str(environment_file)}), patch("builtins.print"):
                select_xcode()
            self.assertEqual(environment_file.read_text(), "DEVELOPER_DIR=" + str(candidates[1]) + "\n")

    def test_macos_workflows_cannot_run_without_cost_guard(self):
        for path in (ROOT / ".github/workflows").glob("*.yml"):
            text = path.read_text()
            jobs = text.split("\njobs:\n", 1)[1]
            blocks = re.split(r"(?m)^  [A-Za-z0-9_-]+:\n", jobs)[1:]
            self.assertTrue(blocks)
            for block in blocks:
                self.assertIn("if: ${{ vars.ALLOW_MACOS_ACTIONS == 'true' }}", block)
                self.assertIn("runs-on: macos-15", block)
                self.assertIn("timeout-minutes: 30", block)
            self.assertIn("contents: read", text)
            self.assertIn("if: ${{ always() }}", text)
            self.assertNotRegex(text, r"run:.*\$\{\{.*inputs\.")
            self.assertNotIn("pull_request_target", text)

    def test_configuration_has_no_tracking_or_fake_background_capability(self):
        info = plistlib.loads((ROOT / "Config/Info.plist").read_bytes())
        self.assertTrue(info["NSFaceIDUsageDescription"])
        self.assertNotIn("NSPhotoLibraryUsageDescription", info)
        self.assertNotIn("NSAppTransportSecurity", info)
        self.assertNotIn("UIBackgroundModes", info)
        privacy = plistlib.loads((ROOT / "Config/PrivacyInfo.xcprivacy").read_bytes())
        self.assertIs(privacy["NSPrivacyTracking"], False)
        self.assertEqual(privacy["NSPrivacyCollectedDataTypes"], [])


if __name__ == "__main__":
    unittest.main()
