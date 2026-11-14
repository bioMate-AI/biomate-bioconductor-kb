#!/usr/bin/env python3
"""
Thin REINVENT4 CLI wrapper for the reinvent4-nf image.

Live ECR historically had ``/opt/biomate/reinvent_runner.py`` that called a bare
``reinvent`` console script — which was missing. This replacement resolves the
CLI the same way as ``drug_discovery.reinvent4_runtime`` (PATH → main_script)
so any in-image callers stay honest.

Usage: reinvent_runner.py <config.toml> [extra args ignored]
"""
from __future__ import annotations

import os
import sys


def main() -> int:
    if len(sys.argv) < 2:
        sys.stderr.write("Usage: reinvent_runner.py <config.toml>\n")
        return 2
    cfg = sys.argv[1]
    # Prefer image-baked shared helper; fall back to local import path.
    sys.path.insert(0, "/opt/biomate")
    try:
        from drug_discovery.reinvent4_runtime import run_reinvent, resolve_cli
    except ImportError:
        sys.stderr.write(
            "FATAL: drug_discovery.reinvent4_runtime not importable "
            "(expected PYTHONPATH=/opt/biomate)\n"
        )
        return 3
    if resolve_cli() is None:
        sys.stderr.write("ERROR: REINVENT4 CLI/package not found in container\n")
        return 3
    proc = run_reinvent(cfg)
    if proc.stdout:
        sys.stdout.write(proc.stdout)
    if proc.stderr:
        sys.stderr.write(proc.stderr)
    return int(proc.returncode)


if __name__ == "__main__":
    raise SystemExit(main())
