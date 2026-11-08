"""Exercise the install Make target without signing or changing installed apps."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class FreshMacInstallTests(unittest.TestCase):
    def run_install(self, package_status=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copyfile(Path(__file__).resolve().parents[2] / "Makefile", root / "Makefile")
            scripts = root / "Scripts"
            scripts.mkdir()
            package = root / ".build/mac/ResetRadarMac.zip"
            package.parent.mkdir(parents=True)
            package.write_text("stale distribution")
            mocks = {
                "generate-project.sh": "exit 0\n",
                "package-mac-app.sh": (
                    f"exit_status={package_status}\n"
                    'printf "%s" "$1" > package-path\n'
                    '[ "$exit_status" = 0 ] || exit "$exit_status"\n'
                    'printf "fresh build" > "$1"\n'
                ),
                "install-mac-app.sh": (
                    'cat "$MAC_PACKAGE_PATH" > installed-content\n'
                    'printf "%s" "$MAC_PACKAGE_PATH" > installed-path\n'
                ),
            }
            for name, body in mocks.items():
                path = scripts / name
                path.write_text("#!/bin/sh\nset -eu\n" + body)
                path.chmod(0o755)
            env = os.environ.copy()
            env["MAC_PACKAGE_PATH"] = str(package)
            result = subprocess.run(
                ["make", "RUN_WITH_TIMEOUT=", "install-macos"], cwd=root,
                env=env, capture_output=True, text=True, timeout=10,
            )
            self.assertEqual(package.read_text(), "stale distribution")
            staged_path = Path((root / "package-path").read_text())
            self.assertNotEqual(staged_path, package)
            self.assertFalse(staged_path.parent.exists(), "temporary package leaked")
            if package_status:
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((root / "installed-content").exists())
            else:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((root / "installed-content").read_text(), "fresh build")
                self.assertEqual((root / "installed-path").read_text(), str(staged_path))

    def test_install_ignores_stale_distribution_and_cleans_temporary_package(self):
        self.run_install()

    def test_failed_build_does_not_install_stale_distribution(self):
        self.run_install(package_status=65)


if __name__ == "__main__":
    unittest.main()
