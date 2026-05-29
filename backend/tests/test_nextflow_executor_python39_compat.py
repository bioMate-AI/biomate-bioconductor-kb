"""Regression guard: ensure nextflow_executor.py keeps `from __future__ import annotations`.

This file uses PEP 604 `X | Y` union syntax (introduced in Python 3.10) in
13+ type annotations. The Galaxy container ships Python 3.9, where those
annotations fail at module load without `from __future__ import annotations`
(PEP 563).

This test FAILS if the import is missing — preventing the bug from
recurring after auto-commit/sync scripts strip it. Historical incidents:
commits 903745e19, 1f49b6e45 — both restoring this exact line.
"""
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
EXECUTOR = REPO_ROOT / "backend" / "lib" / "galaxy" / "webapps" / "galaxy" / "api" / "nextflow_executor.py"


def test_executor_has_future_annotations_import():
    assert EXECUTOR.exists(), f"executor not found at {EXECUTOR}"
    text = EXECUTOR.read_text()
    assert "from __future__ import annotations" in text, (
        "nextflow_executor.py is missing `from __future__ import annotations`. "
        "This breaks every gunicorn worker on Python 3.9 with TypeError on the "
        "PEP 604 union syntax (X | Y). See comments at top of nextflow_executor.py "
        "for full context. Restore the line immediately."
    )
