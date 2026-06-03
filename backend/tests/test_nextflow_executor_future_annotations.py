"""Regression guard: nextflow_executor.py MUST have `from __future__ import annotations`.

Dev Galaxy runs on Python 3.9. nextflow_executor.py uses PEP 604 union syntax
(`list | str | None`) in function signatures. Without `from __future__ import
annotations` at the top of the file, the worker crashes at import time with:

    TypeError: unsupported operand type(s) for |: 'type' and 'type'

That crash puts Galaxy gunicorn into a perpetual worker-restart loop (Gap 0):
worker boots → fails on this import → exits code 3 → supervisor respawns →
hits the same error → forever. The dev API never serves a real request.

Auto-sync has silently stripped this import line FOUR+ times:
  - 2026-05-?? first add
  - 2026-05-27 stripped → re-added
  - 2026-06-?? stripped again
  - 2026-06-03 stripped again → re-added with this test

If this test fails, restore the line at the top of the file:

    from __future__ import annotations

Place it immediately after the module docstring, BEFORE any other import,
because PEP 604 evaluation happens at module-load time.
"""
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
TARGET = (
    REPO_ROOT
    / "backend"
    / "lib"
    / "galaxy"
    / "webapps"
    / "galaxy"
    / "api"
    / "nextflow_executor.py"
)


def test_nextflow_executor_has_future_annotations():
    assert TARGET.exists(), f"nextflow_executor.py missing at {TARGET}"
    text = TARGET.read_text()
    assert "from __future__ import annotations" in text, (
        "nextflow_executor.py is missing `from __future__ import annotations`. "
        "Galaxy on Python 3.9 will crash at gunicorn worker boot with "
        "`TypeError: unsupported operand type(s) for |` because of the PEP 604 "
        "union types in signatures like `log_tail: list | str | None = None`. "
        "Without the __future__ import, every dev API call returns 'fetch failed' "
        "from Node→Galaxy (Gap 0 perpetual restart loop). See history at top of "
        "this test file. Restore the line at the top of nextflow_executor.py, "
        "BEFORE any other import."
    )


def test_nextflow_executor_future_import_is_first():
    """The __future__ import must come before regular imports."""
    text = TARGET.read_text()
    future_idx = text.find("from __future__ import annotations")
    first_regular_import = -1
    for line in text.split("\n"):
        if line.startswith("import ") and "__future__" not in line:
            first_regular_import = text.find(line)
            break
    assert future_idx != -1, "missing __future__ import (see other test)"
    assert first_regular_import == -1 or future_idx < first_regular_import, (
        "from __future__ import annotations must appear BEFORE any other import. "
        "PEP 604 evaluation depends on it being processed first by the parser."
    )
