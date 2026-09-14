#!/usr/bin/env python3
"""Fail the build if tracked files contain likely secrets.

Run from anywhere inside the repository; uses `git ls-files` so untracked local
files (such as a real `.env`) are ignored, while `.env.example` placeholders are
allowed.
"""

import re
import subprocess
import sys

PATTERNS = [
    ("private key block", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----")),
    ("stripe live secret", re.compile(r"sk_live_[0-9a-zA-Z]{16,}")),
    ("stripe live restricted", re.compile(r"rk_live_[0-9a-zA-Z]{16,}")),
    ("aws access key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("google api key", re.compile(r"AIza[0-9A-Za-z_\-]{35}")),
    ("slack token", re.compile(r"xox[baprs]-[0-9A-Za-z\-]{10,}")),
    (
        "assigned signing key",
        re.compile(r"LICENSE_SIGNING_PRIVATE_KEY=[0-9A-Za-z_\-/+=]{40,}"),
    ),
]

ALLOWED_SUFFIXES = (".example",)


def main():
    root = subprocess.check_output(
        ["git", "rev-parse", "--show-toplevel"], text=True
    ).strip()
    files = subprocess.check_output(
        ["git", "ls-files"], text=True, cwd=root
    ).splitlines()

    findings = []
    for path in files:
        if path.endswith(ALLOWED_SUFFIXES):
            continue
        try:
            with open(f"{root}/{path}", encoding="utf-8", errors="ignore") as handle:
                text = handle.read()
        except OSError:
            continue
        for label, pattern in PATTERNS:
            if pattern.search(text):
                findings.append((path, label))

    if findings:
        print("Potential secrets found in tracked files:")
        for path, label in findings:
            print(f"  {path}: {label}")
        return 1

    print(f"Secret scan clean ({len(files)} tracked files).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
