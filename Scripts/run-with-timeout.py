#!/usr/bin/env python3
"""Bound a command, forward cancellation, and reap its process group on failure."""

import math
import os
import signal
import subprocess
import sys
import time


def usage() -> int:
    print(f"usage: {sys.argv[0]} SECONDS -- COMMAND [ARG ...]", file=sys.stderr)
    return 64


def signal_group(process: subprocess.Popen, number: int) -> None:
    try:
        os.killpg(process.pid, number)
    except ProcessLookupError:
        pass


def stop_group(process: subprocess.Popen, number: int) -> None:
    signal_group(process, number)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass
    finally:
        # The leader can exit while a child ignores TERM and still holds a build lock or pipe.
        signal_group(process, signal.SIGKILL)
        process.wait()


def main() -> int:
    if len(sys.argv) < 4 or sys.argv[2] != "--":
        return usage()
    try:
        timeout = float(sys.argv[1])
    except ValueError:
        return usage()
    if not math.isfinite(timeout) or timeout <= 0:
        return usage()

    cancelled = 0

    def cancel(number, _frame):
        nonlocal cancelled
        cancelled = number

    for number in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(number, cancel)
    command = sys.argv[3:]
    try:
        process = subprocess.Popen(command, start_new_session=True)
    except OSError as error:
        print(f"Cannot start {command[0]}: {error}", file=sys.stderr)
        return 127
    started = time.monotonic()
    heartbeat = started + 30
    while True:
        if cancelled:
            stop_group(process, cancelled)
            return 128 + cancelled
        elapsed = time.monotonic() - started
        remaining = timeout - elapsed
        if remaining <= 0:
            print(f"Command timed out after {timeout:g} seconds: {command[0]}", file=sys.stderr)
            stop_group(process, signal.SIGTERM)
            return 124
        try:
            status = process.wait(timeout=min(remaining, 0.2))
            # A command that exits can still leave a background child holding stdout or a
            # build lock. No supervised Make action is meant to leave such jobs running.
            stop_group(process, signal.SIGTERM)
            return status if status >= 0 else 128 - status
        except subprocess.TimeoutExpired:
            if time.monotonic() >= heartbeat:
                print(f"Still running ({elapsed:.0f}s / {timeout:g}s): {command[0]}", file=sys.stderr)
                heartbeat = time.monotonic() + 30


if __name__ == "__main__":
    sys.exit(main())
