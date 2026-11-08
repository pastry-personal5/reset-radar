"""Check source icon slots and compiled bundle resources without third-party packages."""

import argparse
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_sources(root=ROOT):
    for target, platform in (("ResetRadarMac", "mac"), ("ResetRadarWatch", "watchos")):
        catalog = root / target / "Assets.xcassets"
        require(json.loads((catalog / "Contents.json").read_text())["info"]["version"] == 1,
                f"{target}: invalid catalog version")
        icon = catalog / "AppIcon.appiconset"
        manifest = json.loads((icon / "Contents.json").read_text())
        expected = ({(f"{size}x{size}", f"{scale}x")
                     for size in (16, 32, 128, 256, 512) for scale in (1, 2)}
                    if platform == "mac" else {("1024x1024", "1x")})
        slots = set()
        referenced = set()
        for entry in manifest["images"]:
            slot = (entry["size"], entry.get("scale", "1x"))
            require(slot not in slots, f"{target}: duplicate icon slot {slot}")
            slots.add(slot)
            require(entry["idiom"] == ("mac" if platform == "mac" else "universal"),
                    f"{target}: incorrect icon idiom")
            if platform == "watchos":
                require(entry.get("platform") == "watchos", "Watch icon must target watchOS")
            name = entry["filename"]
            require(Path(name).name == name, f"{target}: invalid icon filename")
            referenced.add(name)
            data = (icon / name).read_bytes()
            require(data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR",
                    f"{name}: invalid PNG header")
            width, height = struct.unpack(">II", data[16:24])
            size = int(entry["size"].split("x")[0]) * int(entry.get("scale", "1x")[:-1])
            require(width == height == size, f"{name}: expected {size}px, got {width}x{height}")
            result = subprocess.run(["sips", "-g", "format", str(icon / name)],
                                    check=True, capture_output=True, text=True)
            require("format: png" in result.stdout, f"{name}: image decoder rejected PNG")
        require(slots == expected, f"{target}: incomplete or unexpected icon slots")
        require({p.name for p in icon.glob("*.png")} == referenced,
                f"{target}: unassigned PNGs in AppIcon")


def load_plist(path):
    with path.open("rb") as stream:
        return plistlib.load(stream)


def check_mac(app):
    resources = app / "Contents/Resources"
    info = load_plist(app / "Contents/Info.plist")
    name = info.get("CFBundleIconFile", "")
    require(name and Path(name).name == name, "Mac bundle has no valid CFBundleIconFile")
    icon = resources / (name if name.endswith(".icns") else name + ".icns")
    data = icon.read_bytes()
    require(data[:4] == b"icns" and len(data) > 8
            and struct.unpack(">I", data[4:8])[0] == len(data), "Invalid compiled Mac icon")
    require(info.get("CFBundleIconName") == "AppIcon", "Mac bundle does not select AppIcon")
    require((resources / "Assets.car").is_file(), "Mac bundle is missing Assets.car")


def check_watch(app):
    info = load_plist(app / "Info.plist")
    primary = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
    require(primary.get("CFBundleIconName") == "AppIcon", "Watch bundle does not select AppIcon")
    require((app / "Assets.car").is_file(), "Watch bundle is missing Assets.car")
    for name in primary.get("CFBundleIconFiles", []):
        require(Path(name).name == name and any(app.glob(name + "*.png")),
                f"Watch bundle is missing icon rendition {name}")


def check_ios(app):
    watch = app / "Watch/ResetRadarWatch.app"
    check_watch(watch)
    require(load_plist(watch / "Info.plist").get("WKCompanionAppBundleIdentifier")
            == load_plist(app / "Info.plist").get("CFBundleIdentifier"),
            "Embedded Watch companion identifier does not match iOS app")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--mac-app", type=Path)
    group.add_argument("--watch-app", type=Path)
    group.add_argument("--ios-app", type=Path)
    args = parser.parse_args()
    try:
        if args.mac_app:
            check_mac(args.mac_app)
        elif args.watch_app:
            check_watch(args.watch_app)
        elif args.ios_app:
            check_ios(args.ios_app)
        else:
            check_sources()
    except (ValueError, OSError, KeyError, struct.error, subprocess.CalledProcessError) as error:
        print(f"App icons: {error}", file=sys.stderr)
        return 1
    print("App icons: verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
