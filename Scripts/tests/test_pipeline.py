"""Regression checks for bounded command execution without Xcode or simulator access."""

import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

WATCHDOG = Path(__file__).resolve().parents[1] / "run-with-timeout.py"
XCODE_WRAPPER = WATCHDOG.with_name("run-xcode-test.sh")


class ResultBundleTests(unittest.TestCase):
    def run_action(self, status):
        code = (
            "import sys; from pathlib import Path; "
            "bundle = Path(sys.argv[sys.argv.index('-resultBundlePath') + 1]); "
            "bundle.mkdir(); print(bundle.parent, flush=True); "
            f"raise SystemExit({status})"
        )
        return subprocess.run(
            ["/bin/zsh", str(XCODE_WRAPPER), "5", sys.executable, "-I", "-c", code],
            capture_output=True, text=True, timeout=10,
        )

    def test_failure_retains_diagnostics_and_exit_status(self):
        result = self.run_action(65)
        directory = Path(result.stdout.strip())
        try:
            self.assertEqual(result.returncode, 65)
            self.assertTrue((directory / "result.xcresult").is_dir())
            self.assertIn(str(directory), (directory / "xcodebuild.log").read_text())
            self.assertIn(str(directory), result.stderr)
        finally:
            if directory.name.startswith("reset-radar-xcode-test."):
                shutil.rmtree(directory)

    def test_success_removes_scratch(self):
        result = self.run_action(0)
        self.assertEqual(result.returncode, 0)
        self.assertFalse(Path(result.stdout.strip()).exists())


class WatchdogTests(unittest.TestCase):
    def run_command(self, seconds, code):
        return subprocess.run(
            [sys.executable, "-I", str(WATCHDOG), str(seconds), "--", sys.executable, "-I", "-c", code],
            capture_output=True, text=True, timeout=10,
        )

    def test_preserves_exit_status_and_output(self):
        result = self.run_command(3, "print('child output'); raise SystemExit(17)")
        self.assertEqual(result.returncode, 17)
        self.assertEqual(result.stdout.strip(), "child output")

    def test_rejects_nonfinite_or_nonpositive_deadlines(self):
        for value in ("nan", "inf", "-inf", "0", "-1", "bad"):
            with self.subTest(value=value):
                self.assertEqual(self.run_command(value, "raise SystemExit(0)").returncode, 64)

    def test_timeout_has_distinct_status(self):
        result = self.run_command(0.1, "import time; time.sleep(60)")
        self.assertEqual(result.returncode, 124)
        self.assertIn("timed out", result.stderr)

    def test_child_signal_is_reported_as_shell_status(self):
        result = self.run_command(3, "import os, signal; os.kill(os.getpid(), signal.SIGTERM)")
        self.assertEqual(result.returncode, 143)

    def test_missing_executable(self):
        result = subprocess.run(
            [sys.executable, "-I", str(WATCHDOG), "1", "--", "/no-such-reset-radar-command"],
            capture_output=True, timeout=5,
        )
        self.assertEqual(result.returncode, 127)

    def test_timeout_kills_stubborn_descendant_after_leader_exits(self):
        # The grandchild inherits stdout. communicate() would hang if the wrapper only
        # waited for the cooperative leader and left the grandchild holding the pipe.
        code = """
import os, signal, time
pid = os.fork()
if pid == 0:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(60)
else:
    time.sleep(60)
"""
        result = self.run_command(0.5, code)
        self.assertEqual(result.returncode, 124)

    def test_normal_exit_does_not_leave_child_holding_output_pipe(self):
        code = """
import os, signal, time
pid = os.fork()
if pid == 0:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(60)
else:
    time.sleep(0.1)
    raise SystemExit(0)
"""
        result = self.run_command(2, code)
        self.assertEqual(result.returncode, 0)

    def test_parent_cancellation_reaches_child(self):
        with tempfile.TemporaryDirectory(prefix="reset-radar-watchdog-test-") as directory:
            ready = Path(directory) / "ready"
            code = f"import pathlib, time; pathlib.Path({str(ready)!r}).touch(); time.sleep(60)"
            process = subprocess.Popen(
                [sys.executable, "-I", str(WATCHDOG), "60", "--", sys.executable, "-I", "-c", code],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True,
            )
            try:
                deadline = time.monotonic() + 5
                while not ready.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(ready.exists(), "child did not start")
                process.send_signal(signal.SIGTERM)
                process.communicate(timeout=8)
                self.assertEqual(process.returncode, 143)
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()


if __name__ == "__main__":
    unittest.main()
