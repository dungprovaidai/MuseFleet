"""Synthetic parser fixtures only: no fixture is an application or deliverable IPA."""
import hashlib
from pathlib import Path
import plistlib
import stat
import struct
import sys
import tempfile
import unittest
import warnings
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from validate_ipa import BUNDLE_ID, checked_entries, inspect_macho, inspect_plist, load_plist, validate_ipa


def macho_fixture(platform=2):
    text_offset = 4096
    length = text_offset + 4
    segment = struct.pack("<II16sQQQQiiII", 0x19, 152, b"__TEXT", 0x100000000, 8192, 0, length, 7, 5, 1, 0)
    section = struct.pack("<16s16sQQIIIIIIII", b"__text", b"__TEXT", 0x100001000, 4, text_offset, 2, 0, 0, 0x80000400, 0, 0, 0)
    linker = struct.pack("<III", 0xE, 32, 12) + b"/usr/lib/dyld\0"
    linker = linker.ljust(32, b"\0")
    commands = segment + section + linker + struct.pack("<IIQQ", 0x80000028, 24, text_offset, 0)
    commands += struct.pack("<IIIIII", 0x32, 24, platform, 17 << 16, 18 << 16, 0)
    header = struct.pack("<IiiIIIII", 0xFEEDFACF, 0x0100000C, 0, 2, 4, len(commands), 0, 0)
    return (header + commands).ljust(text_offset, b"\0") + b"\xc0\x03\x5f\xd6"


def plist_fixture():
    return {"CFBundleIdentifier": BUNDLE_ID, "CFBundleExecutable": "MuseFleet", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "7", "MinimumOSVersion": "17.0",
            "CFBundleSupportedPlatforms": ["iPhoneOS"]}


def member(archive, name, data, mode=stat.S_IFREG | 0o644):
    info = zipfile.ZipInfo(name)
    info.filename = name  # Preserve malicious separators when running fixtures on Windows.
    info.create_system = 3
    info.external_attr = mode << 16
    archive.writestr(info, data)


def bundle(archive, info=None, binary=None):
    member(archive, "Payload/MuseFleet.app/Info.plist", plistlib.dumps(info if info is not None else plist_fixture()))
    member(archive, "Payload/MuseFleet.app/MuseFleet", macho_fixture() if binary is None else binary, stat.S_IFREG | 0o755)


class IPATests(unittest.TestCase):
    def test_structural_fixture_and_checksum(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "parser-fixture.zip"
            with zipfile.ZipFile(path, "w") as archive:
                bundle(archive)
            metadata = validate_ipa(path)
            self.assertEqual(metadata["architecture"], "arm64")
            self.assertEqual(metadata["sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
            self.assertFalse(metadata["codesign_verified"])
            with self.assertRaises(ValueError):
                validate_ipa(path, "signed")

    def test_reject_unsafe_archive_paths_types_and_collisions(self):
        cases = ["../escape", "/absolute", "Payload/../escape", "Payload\\escape", "C:/escape", "Payload//bad", "Payload/./bad", "Payload/line\nbreak", "Payload/null\0truncated"]
        for name in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "bad.zip"
                with zipfile.ZipFile(path, "w") as archive:
                    member(archive, name, b"bad")
                with zipfile.ZipFile(path) as archive, self.assertRaises(ValueError):
                    checked_entries(archive)
        for entries in ([('Payload/link', stat.S_IFLNK | 0o777)],
                        [('Payload/directory-mode', stat.S_IFDIR | 0o755)],
                        [('Payload/one', stat.S_IFREG), ('Payload/ONE', stat.S_IFREG)],
                        [('Payload/file', stat.S_IFREG), ('Payload/file/child', stat.S_IFREG)],
                        [('Payload/é', stat.S_IFREG), ('Payload/e\u0301', stat.S_IFREG)],
                        [('Payload/dup', stat.S_IFREG), ('Payload/dup', stat.S_IFREG)]):
            with self.subTest(entries=entries), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "bad.zip"
                with warnings.catch_warnings(), zipfile.ZipFile(path, "w") as archive:
                    warnings.simplefilter("ignore", UserWarning)
                    for name, mode in entries:
                        member(archive, name, b"bad", mode)
                with zipfile.ZipFile(path) as archive, self.assertRaises(ValueError):
                    checked_entries(archive)

    def test_corrupt_zip_crc_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "corrupt.zip"
            with zipfile.ZipFile(path, "w") as archive:
                bundle(archive)
                member(archive, "Payload/MuseFleet.app/resource", b"unique-crc-fixture")
            path.write_bytes(path.read_bytes().replace(b"unique-crc-fixture", b"broken-crc-fixture"))
            with self.assertRaises((ValueError, zipfile.BadZipFile)):
                validate_ipa(path)

    def test_reject_forged_zip_sizes_and_encryption(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.zip"
            with zipfile.ZipFile(path, "w") as archive:
                member(archive, "Payload/file", b"x")
            for field, value in (("file_size", 256 * 1024 * 1024 + 1), ("flag_bits", 1), ("compress_type", 99)):
                with self.subTest(field=field), zipfile.ZipFile(path) as archive:
                    setattr(archive.infolist()[0], field, value)
                    with self.assertRaises(ValueError):
                        checked_entries(archive)

    def test_reject_missing_extra_or_fake_app(self):
        for case in ("missing", "outside", "second", "profile", "placeholder", "simulator", "nonexecutable"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "bad.zip"
                with zipfile.ZipFile(path, "w") as archive:
                    if case == "missing":
                        member(archive, "Payload/MuseFleet.app/readme", b"not an app")
                    elif case == "nonexecutable":
                        member(archive, "Payload/MuseFleet.app/Info.plist", plistlib.dumps(plist_fixture()))
                        member(archive, "Payload/MuseFleet.app/MuseFleet", macho_fixture())
                    else:
                        bundle(archive, binary=b"placeholder" if case == "placeholder" else macho_fixture(7 if case == "simulator" else 2))
                        if case == "outside":
                            member(archive, "outside", b"bad")
                        if case == "second":
                            member(archive, "Payload/Second.app/Info.plist", b"bad")
                        if case == "profile":
                            member(archive, "Payload/MuseFleet.app/embedded.mobileprovision", b"bad")
                with self.assertRaises(ValueError):
                    validate_ipa(path)

    def test_reject_malformed_macho_headers_and_commands(self):
        original = macho_fixture()
        cases = [b"", original[:31], original[:100], original[:4096]]
        for offset, value in ((4, 0x01000007), (12, 6), (16, 5000), (20, 8), (36, 0), (36, 151),
                              (96, 0xFFFFFFFF), (32 + 152 + 32 + 8, 0)):
            mutated = bytearray(original)
            struct.pack_into("<I", mutated, offset, value)
            cases.append(bytes(mutated))
        cases.append(original[:-4] + b"\0" * 4)
        for index, data in enumerate(cases):
            with self.subTest(index=index), self.assertRaises(ValueError):
                inspect_macho(data)

    def test_reject_invalid_code_signature_load_command(self):
        original = bytearray(macho_fixture())
        position = 32 + 152 + 32 + 24
        for size, start, length in ((24, 0, 0), (16, 0, 16), (16, 4096, 1000), (16, 4096, 4)):
            data = bytearray(original)
            struct.pack_into("<IIII", data, position, 0x1D, size, start, length)
            with self.subTest(size=size, start=start, length=length), self.assertRaises(ValueError):
                inspect_macho(data)

    def test_reject_unsafe_and_malformed_plists(self):
        cases = [("CFBundleIdentifier", "com.attacker.app"), ("CFBundleExecutable", "../escape"),
                 ("CFBundleExecutable", ["MuseFleet"]), ("CFBundleVersion", "$(VERSION)"),
                 ("CFBundleShortVersionString", 1), ("MinimumOSVersion", "16.0"),
                 ("CFBundleSupportedPlatforms", ["iPhoneSimulator"]), ("UIBackgroundModes", ["fetch"]),
                 ("NSAppTransportSecurity", {"NSAllowsArbitraryLoadsInWebContent": True}),
                 ("NSAppTransportSecurity", {"NSExceptionDomains": {"muse.ai": {}}})]
        for key, value in cases:
            info = {**plist_fixture(), key: value}
            with self.subTest(key=key), self.assertRaises(ValueError):
                inspect_plist(plistlib.dumps(info))
        for data in (b'<plist><dict><key>a</key><string>b</string><key>a</key><string>c</string></dict></plist>',
                     b'<!DOCTYPE plist [<!ENTITY x "bad">]><plist><string>&x;</string></plist>',
                     b'<plist><dict><key>a</key></dict></plist>', b'<plist><dict>', b'not a plist',
                     plistlib.dumps({"a": "b", "c": "d"}, fmt=plistlib.FMT_BINARY).replace(b"\x51c", b"\x51a")):
            with self.assertRaises(ValueError):
                load_plist(data)
        with self.assertRaises(ValueError):
            inspect_plist(plistlib.dumps(["not a dictionary"]))
        self.assertEqual(inspect_plist(plistlib.dumps(plist_fixture(), fmt=plistlib.FMT_BINARY))["CFBundleIdentifier"], BUNDLE_ID)


if __name__ == "__main__":
    unittest.main()
