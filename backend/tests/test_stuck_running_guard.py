"""Regression guard: stuck-running 12h timeout in routes.ts must stay.

When a run has been status='running' for >12 hours with no terminal signal,
the GET /api/workflows/runs/:id handler force-marks it as 'failed'. Without
this guard, runs whose Nextflow JVM died (container restart, OOM, gunicorn
worker recycle) show 'running' in the UI indefinitely.

Auto-commit/sync scripts have silently stripped this guard at least twice:
  - 2026-05-27 cb27e14c8 first added
  - 2026-06-02 stripped → re-added with this test

If you see this test fail, restore the guard. The expected location is in
frontend/server/routes.ts inside app.get("/api/workflows/runs/:id", ...).
"""
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ROUTES = REPO_ROOT / "frontend" / "server" / "routes.ts"


def test_routes_has_stuck_running_guard():
    assert ROUTES.exists(), f"routes.ts not found at {ROUTES}"
    text = ROUTES.read_text()
    # Three required markers:
    # 1. The constant naming the threshold
    # 2. The guard log message string
    # 3. The user-facing errorMessage hint about publishDir-gap fallback
    required = [
        "STUCK_RUNNING_MS",
        "stuck-running guard",
        "publishDir-gap fallback",
    ]
    missing = [m for m in required if m not in text]
    assert not missing, (
        f"frontend/server/routes.ts is missing stuck-running guard markers: {missing}. "
        f"This guard force-marks runs as 'failed' after 12h of 'running' with no terminal "
        f"signal. Without it, dead Nextflow runs stay 'running' forever in the UI. "
        f"See history at top of test file. Restore the guard block inside "
        f'app.get("/api/workflows/runs/:id", ...) handler.'
    )
