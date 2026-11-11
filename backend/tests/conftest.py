"""Session-wide configuration for backend/tests.

CI runs ``cd backend && python -m pytest tests/`` (pytest.ini: pythonpath = lib).

1. Repo root on sys.path. Several modules (test_family_dedup, test_procedure_widener,
   test_wired_agentic_memory, test_connector_live) import ``backend.lib.…`` — they
   were written to run from the repo root and only passed when another module
   happened to insert the root first (order-dependent). Make it deterministic.

2. collect_ignore — files that are NOT unit tests but match pytest's default
   ``*_test.py`` / ``test_*.py`` patterns. Each is a live end-to-end SCRIPT that
   needs a running BioMate stack, real LLM keys and/or a browser; they are run by
   hand (``python tests/<file>``), never by CI. Listed individually with the
   reason — anything not listed here is collected. The deployed-stack journeys
   that CI/dev actually gate on live in frontend/e2e/live-journeys.e2e.ts
   (docs/20261110_LIVE_JOURNEY_TESTS_AND_CI.md).
"""
from __future__ import annotations

import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

collect_ignore = [
    # Live LLM agent scripts: drive a running Galaxy+Node stack with real API keys.
    "e2e_citation_pilot_agent_test.py",
    "e2e_citation_pilot_api_agent_test.py",
    "e2e_comprehensive_llm_agent_test.py",
    "e2e_pilot_qc_professional_test.py",
    "e2e_real_qc_gate_test.py",
    "e2e_sgi_bench_test.py",
    # Browser UI suite (its conftest imports Playwright-for-Python and drives a
    # running UI) — not installed in CI, not a unit test.
    "e2e_ui",
]
