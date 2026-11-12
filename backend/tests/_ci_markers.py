"""Explicit, reasoned expected-failure markers shared by backend tests.

Every marker here is a STRICT xfail tied to a concrete, checkable condition and
listed in docs/20261110_LIVE_JOURNEY_TESTS_AND_CI.md. When the condition stops
holding (the artifact appears / the dependency is installed), strict=True makes
an unexpected pass fail CI, so the marker gets removed instead of rotting.
"""
from __future__ import annotations

import shutil
from pathlib import Path

import pytest

BACKEND = Path(__file__).resolve().parents[1]
WORKFLOW_DB = BACKEND / "database" / "galaxy_ai_tools.db"

# The 4,2xx-workflow catalog (~330 MB) is NOT in git (backend/database is
# untracked); dev/prod mount it, CI checkouts never have it. Verified
# 2026-11-10: with the real DB symlinked in, the marked tests pass.
# (size check: a test that sqlite3.connect()s the missing path leaves a 0-byte file)
HAS_WORKFLOW_DB = WORKFLOW_DB.exists() and WORKFLOW_DB.stat().st_size > 0
requires_workflow_db = pytest.mark.xfail(
    not HAS_WORKFLOW_DB,
    reason="needs the untracked workflow catalog backend/database/galaxy_ai_tools.db (not in git; absent in CI)",
    strict=True,
)

# R + Bioconductor are installed in the Batch worker images, not on the CI runner.
requires_rscript = pytest.mark.xfail(
    shutil.which("Rscript") is None,
    reason="needs Rscript (R/Bioconductor lives in the Batch worker images, not the CI runner)",
    raises=FileNotFoundError,
    strict=True,
)
