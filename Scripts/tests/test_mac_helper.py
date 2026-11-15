"""Reject a status-line helper that only runs inside the app bundle."""

from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MacHelperCheckTests(unittest.TestCase):
    def check(self, helper_body):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "ResetRadarMac.app"
            helpers = app / "Contents/Helpers"
            helpers.mkdir(parents=True)
            (app / "Contents/Frameworks").mkdir()
            helper = helpers / "ResetRadarStatusLine"
            helper.write_text("#!/bin/sh\n" + helper_body)
            helper.chmod(0o755)
            return subprocess.run(
                ["zsh", str(ROOT / "Scripts/check-mac-helper.sh"), str(app)],
                capture_output=True, text=True, timeout=20,
            )

    def test_self_contained_helper_passes(self):
        result = self.check('[ "$1" = --version ] && printf "1\\n"\n')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_helper_needing_bundle_frameworks_is_rejected(self):
        # Mirrors @executable_path/../Frameworks: present in the bundle, absent beside bin/.
        result = self.check('[ -d "$(dirname "$0")/../Frameworks" ] || exit 134\nprintf "1\\n"\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not run outside the app bundle", result.stderr)

    def test_silent_helper_is_rejected(self):
        self.assertNotEqual(self.check("exit 0\n").returncode, 0)


if __name__ == "__main__":
    unittest.main()
