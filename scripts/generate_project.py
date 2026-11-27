#!/usr/bin/env python3
"""Generate the checked-in Xcode project using only Python's standard library."""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "com.dungprovaidai.musefleet"


def object_id(key):
    return hashlib.sha256(key.encode("utf-8")).hexdigest()[:24].upper()


def quote(value):
    return json.dumps(str(value), ensure_ascii=False)


def render(value, depth=0):
    if isinstance(value, dict):
        lines = ["{"]
        for key, item in value.items():
            lines.append("\t" * (depth + 1) + f"{quote(key)} = {render(item, depth + 1)};")
        return "\n".join(lines) + "\n" + "\t" * depth + "}"
    if isinstance(value, list):
        return "(" + ", ".join(render(item, depth) for item in value) + ("," if value else "") + ")"
    return quote(value)


def resources(root, relative):
    """Treat asset catalogs/bundles as one resource, never compile their contents."""
    directory = root / relative
    if not directory.is_dir():
        return []
    result = []
    for path in sorted(directory.iterdir()):
        if path.name.startswith(".") or path.name.endswith(".md"):
            continue
        if path.suffix in {".xcassets", ".bundle"} or path.is_file():
            if path.suffix != ".swift":
                result.append(path.relative_to(root).as_posix())
        elif path.is_dir():
            result.extend(resources(root, path.relative_to(root)))
    return result


def file_type(path):
    return {".swift": "sourcecode.swift", ".js": "sourcecode.javascript",
            ".xcassets": "folder.assetcatalog", ".bundle": "wrapper.cfbundle",
            ".plist": "text.plist.xml", ".xcprivacy": "text.xml"}.get(Path(path).suffix, "file")


def generate(root):
    objects = {}

    def add(key, isa, **fields):
        identifier = object_id(key)
        if identifier in objects:
            raise ValueError(f"Duplicate project object: {key}")
        objects[identifier] = {"isa": isa, **fields}
        return identifier

    sources = sorted({p.relative_to(root).as_posix() for p in (root / "App").rglob("*.swift")}
                     | {"App/MuseFleetApp.swift"})
    unit_sources = sorted(p.relative_to(root).as_posix() for base in ("Tests/CoreTests", "BrowserTests")
                          for p in (root / base).rglob("*.swift"))
    ui_sources = sorted(p.relative_to(root).as_posix() for p in (root / "UITests").rglob("*.swift"))
    app_resources = sorted(set(resources(root, "App/Resources") + ["Config/PrivacyInfo.xcprivacy"]
                               + [p.relative_to(root).as_posix() for p in (root / "App/Browser").glob("*.js")]))
    unit_resources = sorted(resources(root, "Tests/CoreTests/Fixtures") + resources(root, "BrowserTests/Fixtures"))
    ui_resources = resources(root, "UITests/Fixtures")
    all_files = sorted(set(sources + unit_sources + ui_sources + app_resources + unit_resources + ui_resources
                           + ["Config/Info.plist", "Config/Push.entitlements"]))
    refs = {path: add("file:" + path, "PBXFileReference", lastKnownFileType=file_type(path),
                      path=path, sourceTree="SOURCE_ROOT") for path in all_files}
    products = []
    targets = []
    common = {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SWIFT_VERSION": "5.0",
              "TARGETED_DEVICE_FAMILY": "1", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
              "SUPPORTS_MACCATALYST": "NO", "CLANG_ENABLE_MODULES": "YES",
              "CLANG_ENABLE_OBJC_ARC": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
              "CODE_SIGN_STYLE": "Automatic", "MARKETING_VERSION": "1.0.0", "CURRENT_PROJECT_VERSION": "1"}

    def configs(key, extra):
        ids = []
        for mode in ("Debug", "Release"):
            settings = {**extra}
            if key == "project":
                settings.update(common)
                settings.update({"DEBUG_INFORMATION_FORMAT": "dwarf" if mode == "Debug" else "dwarf-with-dsym",
                                 "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O",
                                 "SWIFT_COMPILATION_MODE": "singlefile" if mode == "Debug" else "wholemodule",
                                 "ENABLE_TESTABILITY": "YES" if mode == "Debug" else "NO"})
                if mode == "Debug":
                    settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)"
            ids.append(add(f"{key}:{mode}", "XCBuildConfiguration", buildSettings=settings, name=mode))
        return add(key + ":configs", "XCConfigurationList", buildConfigurations=ids,
                   defaultConfigurationIsVisible="0", defaultConfigurationName="Release")

    for name, src, res, extension, kind in (
        ("MuseFleet", sources, app_resources, "app", "application"),
        ("MuseFleetTests", unit_sources, unit_resources, "xctest", "bundle.unit-test"),
        ("MuseFleetUITests", ui_sources, ui_resources, "xctest", "bundle.ui-testing"),
    ):
        product = add(name + ":product", "PBXFileReference", explicitFileType="wrapper.application" if extension == "app" else "wrapper.cfbundle",
                      includeInIndex="0", path=f"{name}.{extension}", sourceTree="BUILT_PRODUCTS_DIR")
        products.append(product)
        phases = []
        for label, isa, paths in (("sources", "PBXSourcesBuildPhase", src), ("frameworks", "PBXFrameworksBuildPhase", []),
                                  ("resources", "PBXResourcesBuildPhase", res)):
            files = [add(f"{name}:{label}:{path}", "PBXBuildFile", fileRef=refs[path]) for path in paths]
            phases.append(add(f"{name}:{label}", isa, buildActionMask="2147483647", files=files,
                              runOnlyForDeploymentPostprocessing="0"))
        settings = {"PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE + ("" if extension == "app" else "." + name),
                    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"]}
        dependencies = []
        if extension == "app":
            settings.update({"INFOPLIST_FILE": "Config/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
                             "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES"})
            if any(Path(path).name == "AppIcon.appiconset" for path in (root / "App/Resources").rglob("*.appiconset")):
                settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
        else:
            settings.update({"GENERATE_INFOPLIST_FILE": "YES"})
            proxy = add(name + ":proxy", "PBXContainerItemProxy", containerPortal=object_id("project"), proxyType="1",
                        remoteGlobalIDString=object_id("target:MuseFleet"), remoteInfo="MuseFleet")
            dependencies = [add(name + ":dependency", "PBXTargetDependency", target=object_id("target:MuseFleet"), targetProxy=proxy)]
            if name == "MuseFleetTests":
                settings.update({"TEST_HOST": "$(BUILT_PRODUCTS_DIR)/MuseFleet.app/MuseFleet", "BUNDLE_LOADER": "$(TEST_HOST)"})
            else:
                settings["TEST_TARGET_NAME"] = "MuseFleet"
        targets.append(add("target:" + name, "PBXNativeTarget", buildConfigurationList=configs(name, settings),
                           buildPhases=phases, buildRules=[], dependencies=dependencies, name=name, productName=name,
                           productReference=product, productType="com.apple.product-type." + kind))
    products_group = add("products", "PBXGroup", children=products, name="Products", sourceTree="<group>")
    main_group = add("main", "PBXGroup", children=[*refs.values(), products_group], sourceTree="<group>")
    add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1600",
        "TargetAttributes": {object_id("target:" + name): {"CreatedOnToolsVersion": "16.0", **({"TestTargetID": object_id("target:MuseFleet")} if name != "MuseFleet" else {})}
                             for name in ("MuseFleet", "MuseFleetTests", "MuseFleetUITests")}},
        buildConfigurationList=configs("project", {}), compatibilityVersion="Xcode 14.0", developmentRegion="en",
        hasScannedForEncodings="0", knownRegions=["en", "Base"], mainGroup=main_group, productRefGroup=products_group,
        projectDirPath="", projectRoot="", targets=targets)
    project = "// !$*UTF8*$!\n" + render({"archiveVersion": "1", "classes": {}, "objectVersion": "56",
                                             "objects": dict(sorted(objects.items())), "rootObject": object_id("project")}) + "\n"
    scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.7")

    def reference(parent, name):
        ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=object_id("target:" + name),
                      BuildableName=name + (".app" if name == "MuseFleet" else ".xctest"), BlueprintName=name,
                      ReferencedContainer="container:MuseFleet.xcodeproj")

    action = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(action, "BuildActionEntries")
    for name in ("MuseFleet", "MuseFleetTests", "MuseFleetUITests"):
        entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES" if name == "MuseFleet" else "NO",
                              buildForProfiling="YES" if name == "MuseFleet" else "NO", buildForArchiving="YES" if name == "MuseFleet" else "NO",
                              buildForAnalyzing="YES")
        reference(entry, name)
    action = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                           selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
    testables = ET.SubElement(action, "Testables")
    for name in ("MuseFleetTests", "MuseFleetUITests"):
        reference(ET.SubElement(testables, "TestableReference", skipped="NO", parallelizable="NO"), name)
    for tag, mode in (("LaunchAction", "Debug"), ("ProfileAction", "Release")):
        action = ET.SubElement(scheme, tag, buildConfiguration=mode, useCustomWorkingDirectory="NO")
        reference(ET.SubElement(action, "BuildableProductRunnable", runnableDebuggingMode="0"), "MuseFleet")
    ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    ET.indent(scheme, space="  ")
    return {"MuseFleet.xcodeproj/project.pbxproj": project,
            "MuseFleet.xcodeproj/xcshareddata/xcschemes/MuseFleet.xcscheme": '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(scheme, encoding="unicode") + "\n"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if the project needs regeneration")
    args = parser.parse_args()
    stale = []
    for relative, content in generate(ROOT).items():
        path = ROOT / relative
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != content:
                stale.append(relative)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    if stale:
        parser.exit(1, "Regenerate after adding/removing sources or resources: python scripts/generate_project.py\n" + "\n".join(stale) + "\n")
    print("Xcode project is current." if args.check else "Generated MuseFleet.xcodeproj and shared scheme.")


if __name__ == "__main__":
    main()
