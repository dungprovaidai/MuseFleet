import json
from pathlib import Path
import re
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from generate_project import generate, object_id


def parse_openstep(text):
    """Parse this generator's quoted OpenStep subset independently of its serializer."""
    tokens = iter(re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]', text))

    def value(token):
        if token == "{":
            result = {}
            token = next(tokens)
            while token != "}":
                key = json.loads(token)
                assert key not in result
                assert next(tokens) == "="
                result[key] = value(next(tokens))
                assert next(tokens) == ";"
                token = next(tokens)
            return result
        if token == "(":
            result = []
            token = next(tokens)
            while token != ")":
                result.append(value(token))
                assert next(tokens) == ","
                token = next(tokens)
            return result
        return json.loads(token)

    result = value(next(tokens))
    assert next(tokens, None) is None
    return result


class ProjectTests(unittest.TestCase):
    def test_project_enumeration_references_targets_and_determinism(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = ["App/MuseFleetApp.swift", "App/UI/Home.swift", "App/Browser/observer.js", "App/Browser/Nested/skip.js",
                     "App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
                     "App/Resources/Assets.xcassets/Contents.json", 'App/Resources/a"b.json',
                     "App/Resources/Tiếng Việt.json",
                     "Tests/CoreTests/StoreTests.swift", "BrowserTests/IsolationTests.swift",
                     "BrowserTests/Fixtures/page.html", "UITests/LaunchTests.swift"]
            for relative in reversed(paths):
                path = root / relative
                # Quotes in names are legal on macOS but not on Windows.
                if '"' in relative and sys.platform == "win32":
                    continue
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("fixture")
            generated = generate(root)
            self.assertEqual(generated, generate(root))
            project = parse_openstep(generated["MuseFleet.xcodeproj/project.pbxproj"])
            objects = project["objects"]
            self.assertEqual(objects[project["rootObject"]]["isa"], "PBXProject")
            references = re.findall(r'"([A-F0-9]{24})"', generated["MuseFleet.xcodeproj/project.pbxproj"])
            self.assertTrue(set(references) <= set(objects))
            targets = {item["name"]: item for item in objects.values() if item["isa"] == "PBXNativeTarget"}
            self.assertEqual(set(targets), {"MuseFleet", "MuseFleetTests", "MuseFleetUITests"})
            compiled = [objects[item["fileRef"]]["path"] for item in objects.values() if item["isa"] == "PBXBuildFile"]
            self.assertIn("App/Browser/observer.js", compiled)
            self.assertNotIn("App/Browser/Nested/skip.js", compiled)
            self.assertIn("BrowserTests/Fixtures/page.html", compiled)
            self.assertIn("App/Resources/Assets.xcassets", compiled)
            self.assertIn("App/Resources/Tiếng Việt.json", compiled)
            self.assertNotIn("App/Resources/Assets.xcassets/Contents.json", compiled)
            settings = [item["buildSettings"] for item in objects.values() if item["isa"] == "XCBuildConfiguration"]
            self.assertEqual(sum("TEST_HOST" in item for item in settings), 2)
            self.assertEqual(sum("TEST_TARGET_NAME" in item for item in settings), 2)
            self.assertTrue(all("CODE_SIGN_ENTITLEMENTS" not in item for item in settings))
            self.assertTrue(any(item.get("ASSETCATALOG_COMPILER_APPICON_NAME") == "AppIcon" for item in settings))
            scheme = ET.fromstring(generated["MuseFleet.xcodeproj/xcshareddata/xcschemes/MuseFleet.xcscheme"])
            self.assertEqual(len(scheme.findall("./TestAction/Testables/TestableReference")), 2)
            self.assertTrue(all(item.attrib["BlueprintIdentifier"] in objects for item in scheme.iter("BuildableReference")))
            original_id = object_id("file:App/UI/Home.swift")
            (root / "App/UI/Another.swift").write_text("fixture")
            regenerated = parse_openstep(generate(root)["MuseFleet.xcodeproj/project.pbxproj"])
            self.assertEqual(objects[original_id], regenerated["objects"][original_id])

    def test_empty_branch_still_references_lead_entrypoint(self):
        with tempfile.TemporaryDirectory() as directory:
            project = parse_openstep(generate(Path(directory))["MuseFleet.xcodeproj/project.pbxproj"])
            self.assertIn(object_id("file:App/MuseFleetApp.swift"), project["objects"])


if __name__ == "__main__":
    unittest.main()
