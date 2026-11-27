#!/usr/bin/env python3
"""Reject unsafe IPA ZIPs and verify an actual arm64 iOS executable, not a placeholder."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import struct
import subprocess
import sys
import tempfile
import unicodedata
from xml.parsers.expat import ExpatError
import zipfile


BUNDLE_ID = "com.dungprovaidai.musefleet"
MAX_FILE = 256 * 1024 * 1024
MAX_TOTAL = 2 * 1024 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_plist(data):
    class UniqueDictionary(dict):
        def __setitem__(self, key, value):
            require(key not in self, "Duplicate plist keys")
            super().__setitem__(key, value)

    if not data.startswith(b"bplist"):
        require(b"<!ENTITY" not in data.upper(), "XML entities are forbidden in plists")
    try:
        return plistlib.loads(data, dict_type=UniqueDictionary)
    except (ValueError, TypeError, plistlib.InvalidFileException, ExpatError):
        raise ValueError("Malformed plist or duplicate dictionary keys") from None


def inspect_macho(data):
    require(len(data) >= 32 and data[:4] == b"\xcf\xfa\xed\xfe", "Expected a thin little-endian 64-bit Mach-O")
    _, cpu, _, filetype, count, command_bytes, _, _ = struct.unpack_from("<IiiIIIII", data)
    require(cpu == 0x0100000C and filetype == 2, "Executable must be arm64 MH_EXECUTE")
    require(0 < count <= 4096 and 0 < command_bytes <= len(data) - 32, "Invalid load-command table")
    end = 32 + command_bytes
    offset = 32
    text_ranges = []
    entry = None
    platform = None
    signature = None
    dyld = False
    for _ in range(count):
        require(offset + 8 <= end, "Truncated load command")
        command, size = struct.unpack_from("<II", data, offset)
        require(size >= 8 and size % 8 == 0 and offset + size <= end, "Invalid load-command size")
        if command == 0x19:  # LC_SEGMENT_64
            require(size >= 72, "Truncated segment")
            segment = data[offset + 8:offset + 24].rstrip(b"\0")
            _, _, file_offset, file_size = struct.unpack_from("<QQQQ", data, offset + 24)
            sections = struct.unpack_from("<I", data, offset + 64)[0]
            require(size == 72 + sections * 80 and file_offset + file_size <= len(data), "Invalid segment range")
            for index in range(sections):
                section = offset + 72 + index * 80
                section_name = data[section:section + 16].rstrip(b"\0")
                section_segment = data[section + 16:section + 32].rstrip(b"\0")
                section_size, section_offset = struct.unpack_from("<QI", data, section + 40)
                flags = struct.unpack_from("<I", data, section + 64)[0]
                if flags & 0xFF not in {1, 0xC, 0x12}:  # Zero-fill sections have no file bytes.
                    require(section_offset + section_size <= len(data), "Invalid section range")
                if segment == b"__TEXT" and section_segment == segment and section_name == b"__text":
                    require(section_size > 0 and section_offset >= end and
                            file_offset <= section_offset < section_offset + section_size <= file_offset + file_size,
                            "Invalid executable text section")
                    require(any(data[section_offset:section_offset + section_size]), "Executable text is empty")
                    text_ranges.append((section_offset, section_offset + section_size))
        elif command == 0x80000028:  # LC_MAIN
            require(size == 24 and entry is None, "Invalid or duplicate LC_MAIN")
            entry = struct.unpack_from("<Q", data, offset + 8)[0]
        elif command == 0x32:  # LC_BUILD_VERSION
            require(size >= 24 and platform is None, "Invalid or duplicate build version")
            platform, minimum, _, tools = struct.unpack_from("<IIII", data, offset + 8)
            require(size == 24 + tools * 8 and minimum >= 17 << 16, "Expected iOS 17+ deployment target")
        elif command == 0xE:  # LC_LOAD_DYLINKER
            name_offset = struct.unpack_from("<I", data, offset + 8)[0] if size >= 16 else 0
            require(12 <= name_offset < size, "Invalid dynamic linker command")
            dyld = data[offset + name_offset:offset + size].split(b"\0", 1)[0] == b"/usr/lib/dyld"
        elif command == 0x1D:  # LC_CODE_SIGNATURE
            require(size == 16 and signature is None, "Invalid or duplicate code signature")
            start, length = struct.unpack_from("<II", data, offset + 8)
            require(start >= end and length >= 12 and start + length <= len(data), "Invalid code signature range")
            magic, blob_size, slots = struct.unpack_from(">III", data, start)
            require(magic == 0xFADE0CC0 and blob_size <= length and 12 + slots * 8 <= blob_size,
                    "Invalid signature superblob")
            signature = (start, length)
        offset += size
    require(offset == end, "Load-command count/size mismatch")
    require(platform == 2, "Expected an iOS device binary, not a simulator or macOS binary")
    require(dyld and text_ranges and entry is not None and any(a <= entry < b for a, b in text_ranges),
            "Missing executable text, dynamic linker, or valid entry point")
    return {"architecture": "arm64", "platform": "iOS", "load_commands": count,
            "code_signature_present": signature is not None}


def checked_entries(archive):
    entries = archive.infolist()
    require(0 < len(entries) <= 100000, "Invalid ZIP entry count")
    names = {}
    total = 0
    for info in entries:
        name = info.filename
        parts = name.rstrip("/").split("/")
        require(name and all(ord(char) >= 32 and ord(char) != 127 for char in name) and not name.startswith("/") and "\\" not in name and ":" not in name and
                "\0" not in name and all(part not in {"", ".", ".."} for part in parts), "Unsafe ZIP path")
        require(name == info.orig_filename, "Truncated ZIP filename")
        canonical = unicodedata.normalize("NFD", name.rstrip("/")).casefold()
        require(canonical not in names, "Duplicate or case-colliding ZIP entry")
        mode = info.external_attr >> 16
        require(stat.S_IFMT(mode) in {0, stat.S_IFREG, stat.S_IFDIR}, "Links and special files are forbidden")
        require(stat.S_IFMT(mode) != stat.S_IFDIR or info.is_dir(), "Directory mode/path mismatch")
        require(not info.flag_bits & 1 and info.compress_type in {zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED},
                "Encrypted or unsupported ZIP entry")
        require(0 <= info.file_size <= MAX_FILE, "ZIP member exceeds size limit")
        require(not info.is_dir() or info.file_size == 0, "Directory contains data")
        require(info.file_size < 1024 * 1024 or info.file_size <= max(1, info.compress_size) * 1000,
                "Excessive ZIP compression ratio")
        total += info.file_size
        require(total <= MAX_TOTAL, "ZIP exceeds total size limit")
        names[canonical] = info
    for name in names:
        for parent in PurePosixPath(name).parents:
            if str(parent) in names:
                require(names[str(parent)].is_dir(), "ZIP file shadows a directory")
    return entries


def inspect_plist(data):
    require(len(data) <= 2 * 1024 * 1024, "Info.plist exceeds size limit")
    info = load_plist(data)
    require(isinstance(info, dict), "Info.plist must be a dictionary")
    require(info.get("CFBundleIdentifier") == BUNDLE_ID, "Unexpected bundle identifier")
    executable = info.get("CFBundleExecutable")
    require(isinstance(executable, str) and re.fullmatch(r"[A-Za-z0-9_-]+", executable) is not None,
            "Unsafe executable name")
    require(info.get("CFBundlePackageType") == "APPL", "Expected an application bundle")
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        require(isinstance(info.get(key), str) and re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", info[key]) is not None,
                "Invalid or unresolved bundle version")
    minimum = info.get("MinimumOSVersion", "")
    require(isinstance(minimum, str) and re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", minimum) is not None
            and int(minimum.split(".")[0]) >= 17, "Expected minimum iOS 17")
    require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "Expected iPhoneOS bundle platform")
    require(not info.get("UIBackgroundModes"), "Background modes are not authorized")
    ats = info.get("NSAppTransportSecurity", {})
    require(isinstance(ats, dict) and not any(ats.get(key) for key in
            ("NSAllowsArbitraryLoads", "NSAllowsArbitraryLoadsInWebContent", "NSAllowsArbitraryLoadsForMedia"))
            and not ats.get("NSExceptionDomains"), "Transport security exceptions are not authorized")
    return info


def validate_ipa(path, signing="unsigned", codesign=False):
    require(signing in {"signed", "unsigned"}, "Unknown signing mode")
    with zipfile.ZipFile(path) as archive:
        entries = checked_entries(archive)
        files = {info.filename: info for info in entries if not info.is_dir()}
        apps = {name.split("/")[1] for name in files if len(name.split("/")) >= 3
                and name.startswith("Payload/") and name.split("/")[1].endswith(".app")}
        require(len(apps) == 1, "IPA must contain exactly one Payload application")
        app = "Payload/" + next(iter(apps))
        require(all(name == "Payload/" or name == app + "/" or name.startswith(app + "/") for name in
                    (info.filename for info in entries)), "Unexpected content outside the application")
        require(app + "/Info.plist" in files, "Missing application Info.plist")
        info = inspect_plist(archive.read(app + "/Info.plist"))
        executable = app + "/" + info["CFBundleExecutable"]
        require(executable in files, "Missing application executable")
        require(files[executable].external_attr >> 16 & 0o111, "Application executable is not executable")
        binary = inspect_macho(archive.read(executable))
        require(binary["code_signature_present"] == (signing == "signed"), "Signing mode does not match executable")
        profile = app + "/embedded.mobileprovision"
        require((profile in files) == (signing == "signed"), "Provisioning profile does not match signing mode")
        verified = False
        if codesign:
            require(sys.platform == "darwin", "codesign verification requires macOS")
            with tempfile.TemporaryDirectory(prefix="musefleet-verify-") as temporary:
                for member in entries:
                    target = Path(temporary).joinpath(*PurePosixPath(member.filename).parts)
                    if member.is_dir():
                        target.mkdir(parents=True, exist_ok=True)
                    else:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        with archive.open(member) as source, target.open("wb") as destination:
                            import shutil
                            shutil.copyfileobj(source, destination)
                        target.chmod((member.external_attr >> 16 & 0o777) or 0o644)
                bundle = Path(temporary) / app
                if signing == "signed":
                    from signing import verify_signed_app
                    verify_signed_app(bundle)
                    verified = True
                else:
                    result = subprocess.run(["codesign", "--display", str(bundle)], capture_output=True)
                    require(result.returncode != 0 and b"not signed at all" in result.stderr,
                            "Unsigned bundle has unexpected signing state")
                # Read every resource to check CRCs even when the executable already passed.
        require(archive.testzip() is None, "ZIP CRC validation failed")
    with Path(path).open("rb") as handle:
        digest = hashlib.file_digest(handle, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else _digest(handle)
    return {"bundle_identifier": BUNDLE_ID, "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
            "executable": info["CFBundleExecutable"], **binary, "signing_mode": signing,
            "codesign_verified": verified, "sha256": digest, "size_bytes": Path(path).stat().st_size}


def _digest(handle):
    digest = hashlib.sha256()
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--signing", choices=("unsigned", "signed"), required=True)
    parser.add_argument("--codesign", action="store_true", help="Also verify on macOS using codesign and the embedded profile")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        metadata = validate_ipa(args.ipa, args.signing, args.codesign)
    except (ValueError, KeyError, TypeError, plistlib.InvalidFileException, zipfile.BadZipFile, OSError, struct.error) as error:
        parser.exit(1, f"IPA validation failed: {error}\n")
    text = json.dumps(metadata, indent=2) + "\n"
    if args.output:
        args.output.write_text(text, encoding="utf-8")
    print(text, end="")


if __name__ == "__main__":
    main()
