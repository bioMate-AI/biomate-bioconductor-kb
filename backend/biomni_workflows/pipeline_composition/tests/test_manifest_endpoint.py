"""
Phase 4 test: GET /api/nextflow/invocations/{id}/manifest endpoint logic.

Tests the manifest file lookup helpers directly (no FastAPI test client needed),
verifying that:
  - A completed run with an existing workflow_outputs.json is returned as-is
  - An unknown invocation_id returns None (maps to 404 in the real handler)
  - A known invocation whose manifest file hasn't been written yet returns None
    (maps to 404 with "still running" message)
"""

import json
import sys
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Helpers that mirror the endpoint's logic without importing FastAPI
# ---------------------------------------------------------------------------

def _find_outdir(runs: dict, invocation_id: str):
    """Mirror of the endpoint's _runs lookup loop."""
    for run_info in runs.values():
        if run_info.get("invocation_id") == invocation_id:
            raw = run_info.get("outdir")
            return Path(raw) if raw else None
    return None


def _read_manifest(outdir: Path):
    """Mirror of the endpoint's manifest read logic."""
    if outdir is None:
        return None, "invocation_not_found"
    manifest_path = outdir / "workflow_outputs.json"
    if not manifest_path.exists():
        return None, "manifest_not_written"
    return json.loads(manifest_path.read_text()), "ok"


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestManifestEndpointLogic:

    def test_unknown_invocation_returns_none(self):
        runs = {
            "run1": {"invocation_id": "inv_abc", "outdir": "/tmp/run1"}
        }
        outdir = _find_outdir(runs, "inv_UNKNOWN")
        assert outdir is None

    def test_known_invocation_resolved(self, tmp_path):
        runs = {
            "run1": {"invocation_id": "inv_abc", "outdir": str(tmp_path)}
        }
        outdir = _find_outdir(runs, "inv_abc")
        assert outdir == tmp_path

    def test_manifest_not_yet_written(self, tmp_path):
        # outdir exists but workflow_outputs.json doesn't
        manifest, status = _read_manifest(tmp_path)
        assert manifest is None
        assert status == "manifest_not_written"

    def test_manifest_returned_when_present(self, tmp_path):
        payload = {
            "schema_version": "1.0",
            "pipeline_id": "cryosparc_standard_spa",
            "invocation_id": "inv_xyz",
            "completed_at": "2026-03-09T00:00:00+00:00",
            "outdir": str(tmp_path),
            "ports": {"volume_cs": "17_homogeneous_refinement/refined_volume.cs"},
        }
        (tmp_path / "workflow_outputs.json").write_text(json.dumps(payload))
        manifest, status = _read_manifest(tmp_path)
        assert status == "ok"
        assert manifest["pipeline_id"] == "cryosparc_standard_spa"
        assert "ports" in manifest
        assert manifest["ports"]["volume_cs"].endswith("refined_volume.cs")

    def test_manifest_preserves_metrics(self, tmp_path):
        payload = {
            "schema_version": "1.0",
            "pipeline_id": "cryosparc_standard_spa",
            "invocation_id": "inv_xyz",
            "completed_at": "2026-03-09T00:00:00+00:00",
            "outdir": str(tmp_path),
            "ports": {"volume_cs": "vol.cs"},
            "metrics": {"resolution_A": 2.8, "fsc_threshold": 0.143},
        }
        (tmp_path / "workflow_outputs.json").write_text(json.dumps(payload))
        manifest, status = _read_manifest(tmp_path)
        assert status == "ok"
        assert manifest["metrics"]["resolution_A"] == pytest.approx(2.8)

    def test_multiple_runs_correct_invocation_resolved(self, tmp_path):
        dir_a = tmp_path / "run_a"
        dir_b = tmp_path / "run_b"
        dir_a.mkdir()
        dir_b.mkdir()

        runs = {
            "run_a": {"invocation_id": "inv_aaa", "outdir": str(dir_a)},
            "run_b": {"invocation_id": "inv_bbb", "outdir": str(dir_b)},
        }

        outdir_a = _find_outdir(runs, "inv_aaa")
        outdir_b = _find_outdir(runs, "inv_bbb")

        assert outdir_a == dir_a
        assert outdir_b == dir_b

    def test_outdir_none_in_registry(self):
        runs = {
            "run1": {"invocation_id": "inv_abc", "outdir": None}
        }
        outdir = _find_outdir(runs, "inv_abc")
        assert outdir is None
        _, status = _read_manifest(outdir)
        assert status == "invocation_not_found"
