"""Catch missing asset slots and lost compiled icons before packaging or installation."""

import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("app_icons", ROOT / "Scripts/check-app-icons.py")
ICONS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ICONS)


class AppIconTests(unittest.TestCase):
    def test_installer_rejects_missing_icon_before_quitting_or_replacing_app(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / "Scripts"
            scripts.mkdir()
            for name in ("install-mac-app.sh", "check-app-icons.py"):
                shutil.copyfile(ROOT / "Scripts" / name, scripts / name)
            (scripts / "check-mac-signing.sh").write_text("#!/bin/sh\nexit 0\n")
            (scripts / "check-mac-signing.sh").chmod(0o755)
            commands = root / "bin"
            commands.mkdir()
            for name, body in {
                "ditto": 'mkdir -p "$4/ResetRadarMac.app/Contents/Resources"\n',
                "codesign": "exit 0\n",
                "pgrep": f'touch "{root}/quit-attempted"\nexit 1\n',
            }.items():
                command = commands / name
                command.write_text("#!/bin/sh\n" + body)
                command.chmod(0o755)
            installed = root / "Applications/ResetRadarMac.app"
            installed.mkdir(parents=True)
            sentinel = installed / "keep"
            sentinel.write_text("installed app")
            package = root / "app.zip"
            package.touch()
            env = dict(os.environ, PATH=f"{commands}:{os.environ['PATH']}",
                       MAC_PACKAGE_PATH=str(package), MAC_APPLICATIONS_DIR=str(installed.parent),
                       RR_INSTALL_DIR=str(commands))
            result = subprocess.run(["zsh", str(scripts / "install-mac-app.sh")],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("App icons:", result.stderr)
            self.assertEqual(sentinel.read_text(), "installed app")
            self.assertFalse((root / "quit-attempted").exists())

    def test_checked_in_catalogs_are_complete(self):
        ICONS.check_sources()

    def test_source_slot_with_wrong_pixel_size_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for target in ("ResetRadarMac", "ResetRadarWatch"):
                shutil.copytree(ROOT / target / "Assets.xcassets", root / target / "Assets.xcassets")
            icon = root / "ResetRadarMac/Assets.xcassets/AppIcon.appiconset/icon-16.png"
            shutil.copyfile(icon.with_name("icon-32.png"), icon)
            with self.assertRaisesRegex(ValueError, "expected 16px"):
                ICONS.check_sources(root)

    def test_mac_bundle_requires_referenced_compiled_icon(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            resources = app / "Contents/Resources"
            resources.mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIconName": "AppIcon", "CFBundleIconFile": "AppIcon",
            }))
            (resources / "Assets.car").write_bytes(b"fixture")
            icon = resources / "AppIcon.icns"
            icon.write_bytes(b"icns" + struct.pack(">I", 16) + b"fixture!")
            ICONS.check_mac(app)
            icon.unlink()
            with self.assertRaises(FileNotFoundError):
                ICONS.check_mac(app)
            icon.write_bytes(b"not an icns")
            with self.assertRaisesRegex(ValueError, "Invalid compiled Mac icon"):
                ICONS.check_mac(app)

    def test_ipa_requires_embedded_watch_icon_and_matching_companion(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "reader"}))
            with self.assertRaises(FileNotFoundError):
                ICONS.check_ios(app)
            watch = app / "Watch/ResetRadarWatch.app"
            watch.mkdir(parents=True)
            info = {"WKCompanionAppBundleIdentifier": "reader", "CFBundleIcons": {
                "CFBundlePrimaryIcon": {"CFBundleIconName": "AppIcon",
                                        "CFBundleIconFiles": ["AppIcon40x40"]}}}
            (watch / "Info.plist").write_bytes(plistlib.dumps(info))
            (watch / "Assets.car").write_bytes(b"fixture")
            with self.assertRaisesRegex(ValueError, "missing icon rendition"):
                ICONS.check_ios(app)
            (watch / "AppIcon40x40@2x.png").write_bytes(b"fixture")
            ICONS.check_ios(app)
            info["WKCompanionAppBundleIdentifier"] = "wrong-reader"
            (watch / "Info.plist").write_bytes(plistlib.dumps(info))
            with self.assertRaisesRegex(ValueError, "companion identifier"):
                ICONS.check_ios(app)


if __name__ == "__main__":
    unittest.main()
