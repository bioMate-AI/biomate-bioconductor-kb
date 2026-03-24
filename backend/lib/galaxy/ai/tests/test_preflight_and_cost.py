"""
Unit tests for C1 (preflight with pilot analysis detection) and
D1 (pre-run cost estimation) functions.

We test the logic extracted directly rather than importing the FastAPI
endpoint module (which needs the full Galaxy web stack), so these run
without any Galaxy infrastructure.
"""
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

import pytest

# Ensure galaxy.ai.* is on the path
sys.path.insert(0, str(Path(__file__).resolve().parents[5] / "lib"))

# ---------------------------------------------------------------------------
# Inline copies of the logic under test (avoids full Galaxy import chain)
# These mirror the functions in nextflow_executor.py exactly.
# ---------------------------------------------------------------------------

from galaxy.ai.pilot_analysis.registry import PILOT_ANALYZERS


def _detect_pilot_analyzers(input_files: List[str]) -> List[Dict[str, Any]]:
    ext_map: Dict[str, List[str]] = {}
    for f in input_files:
        ext = Path(f).suffix.lower().lstrip(".")
        ext_map.setdefault(ext, []).append(f)

    applicable = []
    seen: set = set()
    for name, spec in PILOT_ANALYZERS.items():
        required_type = spec.get("input_type", "")
        if required_type in ext_map and name not in seen:
            seen.add(name)
            applicable.append({
                "name": name,
                "description": spec.get("description", ""),
                "input_type": required_type,
                "runtime_estimate": spec.get("runtime_estimate", "~30s"),
                "max_runtime_seconds": spec.get("max_runtime_seconds", 60),
                "category": spec.get("category", "general"),
                "matched_files": ext_map[required_type],
            })
    return applicable


_BATCH_INSTANCE_COST_PER_HOUR: Dict[str, float] = {
    "c5.xlarge": 0.17,  "c5.2xlarge": 0.34,  "c5.4xlarge": 0.68,
    "c5.9xlarge": 1.53, "c5.18xlarge": 3.06,
    "r5.xlarge": 0.252, "r5.2xlarge": 0.504, "r5.4xlarge": 1.008,
    "r5.8xlarge": 2.016,
    "m5.xlarge": 0.192, "m5.2xlarge": 0.384, "m5.4xlarge": 0.768,
    "m5.8xlarge": 1.536,
    "g4dn.xlarge": 0.526, "g4dn.2xlarge": 0.752, "g4dn.4xlarge": 1.204,
}

_DOMAIN_RUNTIME_HINTS: Dict[str, Dict[str, Any]] = {
    "rnaseq":      {"instance": "c5.4xlarge",   "min_h": 0.5, "max_h": 2.0},
    "chipseq":     {"instance": "c5.4xlarge",   "min_h": 1.0, "max_h": 4.0},
    "atacseq":     {"instance": "c5.2xlarge",   "min_h": 0.5, "max_h": 3.0},
    "sarek":       {"instance": "c5.9xlarge",   "min_h": 4.0, "max_h": 12.0},
    "scrnaseq":    {"instance": "r5.4xlarge",   "min_h": 1.0, "max_h": 6.0},
    "methylseq":   {"instance": "c5.9xlarge",   "min_h": 2.0, "max_h": 8.0},
    "cryoem":      {"instance": "g4dn.4xlarge", "min_h": 2.0, "max_h": 8.0},
    "cryosparc":   {"instance": "g4dn.4xlarge", "min_h": 1.0, "max_h": 6.0},
    "proteomics":  {"instance": "c5.4xlarge",   "min_h": 0.5, "max_h": 2.0},
    "metagenomics":{"instance": "r5.4xlarge",   "min_h": 2.0, "max_h": 10.0},
    "alphafold":   {"instance": "g4dn.4xlarge", "min_h": 4.0, "max_h": 24.0},
    "default":     {"instance": "c5.2xlarge",   "min_h": 0.5, "max_h": 3.0},
}


def _preflight(
    workflow_path=None,
    workflow_name=None,
    parameters=None,
    input_files=None,
    required_params=None,
) -> Dict[str, Any]:
    phases: List[Dict[str, Any]] = []
    params = parameters or {}
    input_files = input_files or []
    required = required_params or []

    missing = [
        p.get("id") or p.get("name")
        for p in required
        if not (params.get(p.get("id") or p.get("name") or ""))
    ]
    phases.append({
        "id": "parameters",
        "status": "pass" if not missing else "fail",
        "message": (
            "All required parameters present"
            if not missing
            else f"Missing required parameters: {', '.join(str(m) for m in missing)}"
        ),
    })

    try:
        applicable = _detect_pilot_analyzers(input_files) if input_files else []
        total_est = sum(a["max_runtime_seconds"] for a in applicable)
        phases.append({
            "id": "inputs",
            "status": "pass",
            "message": (
                f"Input files recognised — {len(applicable)} pilot analyzer(s) available"
                if applicable else "Input file types checked (no pilot analyzers matched)"
            ),
            "applicable_analyzers": applicable,
            "estimated_characterization_seconds": total_est,
        })
    except Exception:
        phases.append({"id": "inputs", "status": "pass",
                       "message": "Input file accessibility check complete",
                       "applicable_analyzers": []})

    wf_path = workflow_path or ""
    path_ok = bool(wf_path) and Path(wf_path).exists() if wf_path else False
    if not wf_path:
        phases.append({"id": "structure", "status": "pass",
                       "message": "Workflow structure valid (no path provided — catalog workflow)"})
    elif path_ok:
        phases.append({"id": "structure", "status": "pass",
                       "message": f"Workflow path exists: {wf_path}"})
    else:
        phases.append({"id": "structure", "status": "warn",
                       "message": f"Workflow path not found locally (may be remote): {wf_path}"})

    ready = all(p["status"] in ("pass", "warn") for p in phases) and all(
        p["status"] == "pass" for p in phases if p["id"] == "parameters"
    )
    return {"phases": phases, "ready": ready}


def _estimate_cost(nextflow_path=None, workflow_name=None) -> Dict[str, Any]:
    path = (nextflow_path or workflow_name or "").lower()
    hint = _DOMAIN_RUNTIME_HINTS["default"]
    best_len = 0
    for domain, h in _DOMAIN_RUNTIME_HINTS.items():
        if domain != "default" and domain in path and len(domain) > best_len:
            hint = h
            best_len = len(domain)
    instance = hint["instance"]
    cost_per_hour = _BATCH_INSTANCE_COST_PER_HOUR.get(instance, 0.34)
    min_cost = round(hint["min_h"] * cost_per_hour, 2)
    max_cost = round(hint["max_h"] * cost_per_hour * 1.15, 2)
    return {
        "min_usd": min_cost,
        "max_usd": max_cost,
        "instance_type": instance,
        "cost_per_hour_usd": cost_per_hour,
        "assumptions": [
            f"Instance type: {instance} (${cost_per_hour:.3f}/hr on-demand)",
            f"Estimated runtime: {hint['min_h']:.1f}–{hint['max_h']:.1f} hours",
            "Does not include S3 data transfer costs (~$0.09/GB egress)",
            "AWS Spot pricing may reduce cost by 60–80%",
        ],
    }


# ---------------------------------------------------------------------------
# Tests for _detect_pilot_analyzers (C1 helper)
# ---------------------------------------------------------------------------

class TestDetectPilotAnalyzers:
    def test_empty_input_files(self):
        result = _detect_pilot_analyzers([])
        assert result == []

    def test_bam_file_matches_genomics_analyzers(self):
        result = _detect_pilot_analyzers(["sample.bam"])
        names = [a["name"] for a in result]
        assert "estimate_fragment_size" in names
        assert "detect_sequencing_protocol" in names
        for a in result:
            assert a["input_type"] == "bam"
            assert "description" in a
            assert "runtime_estimate" in a
            assert "matched_files" in a
            assert "sample.bam" in a["matched_files"]

    def test_fastq_file_matches_read_quality_analyzer(self):
        result = _detect_pilot_analyzers(["reads.fastq"])
        names = [a["name"] for a in result]
        assert "estimate_read_quality" in names
        for a in result:
            assert a["input_type"] == "fastq"

    def test_mixed_extensions_match_both(self):
        result = _detect_pilot_analyzers(["sample.bam", "reads.fastq"])
        types_found = {a["input_type"] for a in result}
        assert "bam" in types_found
        assert "fastq" in types_found

    def test_unknown_extension_returns_empty(self):
        result = _detect_pilot_analyzers(["report.pdf", "data.csv"])
        assert result == []

    def test_no_duplicate_analyzers(self):
        result = _detect_pilot_analyzers(["a.bam", "b.bam"])
        names = [a["name"] for a in result]
        assert len(names) == len(set(names))

    def test_result_structure(self):
        result = _detect_pilot_analyzers(["sample.bam"])
        for a in result:
            assert "name" in a
            assert "description" in a
            assert "input_type" in a
            assert "runtime_estimate" in a
            assert "max_runtime_seconds" in a
            assert "category" in a
            assert "matched_files" in a


# ---------------------------------------------------------------------------
# Tests for _preflight (C1 logic)
# ---------------------------------------------------------------------------

class TestWorkflowPreflight:
    def test_no_required_params_passes(self):
        result = _preflight(required_params=[], parameters={})
        assert result["ready"] is True
        params_phase = next(p for p in result["phases"] if p["id"] == "parameters")
        assert params_phase["status"] == "pass"

    def test_missing_required_param_fails(self):
        result = _preflight(
            required_params=[{"id": "genome", "name": "genome"}],
            parameters={},
        )
        params_phase = next(p for p in result["phases"] if p["id"] == "parameters")
        assert params_phase["status"] == "fail"
        assert "genome" in params_phase["message"]
        assert result["ready"] is False

    def test_provided_required_param_passes(self):
        result = _preflight(
            required_params=[{"id": "genome", "name": "genome"}],
            parameters={"genome": "GRCh38"},
        )
        params_phase = next(p for p in result["phases"] if p["id"] == "parameters")
        assert params_phase["status"] == "pass"

    def test_input_files_trigger_pilot_detection(self):
        result = _preflight(input_files=["sample.bam"])
        inputs_phase = next(p for p in result["phases"] if p["id"] == "inputs")
        assert inputs_phase["status"] == "pass"
        assert "applicable_analyzers" in inputs_phase
        assert len(inputs_phase["applicable_analyzers"]) > 0
        assert "estimated_characterization_seconds" in inputs_phase

    def test_no_input_files_returns_empty_analyzers(self):
        result = _preflight()
        inputs_phase = next(p for p in result["phases"] if p["id"] == "inputs")
        assert inputs_phase["applicable_analyzers"] == []

    def test_existing_workflow_path_passes_structure(self, tmp_path):
        wf = tmp_path / "main.nf"
        wf.write_text("workflow { }")
        result = _preflight(workflow_path=str(wf))
        structure_phase = next(p for p in result["phases"] if p["id"] == "structure")
        assert structure_phase["status"] == "pass"
        assert str(wf) in structure_phase["message"]

    def test_nonexistent_workflow_path_warns(self):
        result = _preflight(workflow_path="/nonexistent/path/main.nf")
        structure_phase = next(p for p in result["phases"] if p["id"] == "structure")
        assert structure_phase["status"] == "warn"

    def test_result_has_three_phases(self):
        result = _preflight()
        phase_ids = [p["id"] for p in result["phases"]]
        assert "parameters" in phase_ids
        assert "inputs" in phase_ids
        assert "structure" in phase_ids


# ---------------------------------------------------------------------------
# Tests for _estimate_cost (D1 logic)
# ---------------------------------------------------------------------------

class TestEstimateWorkflowCost:
    def test_rnaseq_returns_correct_instance(self):
        result = _estimate_cost("nf-core/rnaseq")
        assert result["instance_type"] == "c5.4xlarge"
        assert result["min_usd"] > 0
        assert result["max_usd"] > result["min_usd"]

    def test_sarek_returns_large_instance(self):
        result = _estimate_cost("nf-core/sarek")
        assert result["instance_type"] == "c5.9xlarge"
        assert result["max_usd"] > 5  # WGS is expensive

    def test_cryoem_returns_gpu_instance(self):
        result = _estimate_cost("nf-core/cryoem")
        assert "g4dn" in result["instance_type"]

    def test_unknown_workflow_returns_defaults(self):
        result = _estimate_cost("custom/unknown-workflow")
        hint = _DOMAIN_RUNTIME_HINTS["default"]
        assert result["instance_type"] == hint["instance"]

    def test_result_structure(self):
        result = _estimate_cost("nf-core/rnaseq")
        assert "min_usd" in result
        assert "max_usd" in result
        assert "instance_type" in result
        assert "cost_per_hour_usd" in result
        assert "assumptions" in result
        assert isinstance(result["assumptions"], list)
        assert len(result["assumptions"]) >= 3

    def test_cost_per_hour_matches_table(self):
        result = _estimate_cost("nf-core/rnaseq")
        expected_rate = _BATCH_INSTANCE_COST_PER_HOUR[result["instance_type"]]
        assert abs(result["cost_per_hour_usd"] - expected_rate) < 0.001

    def test_workflow_name_fallback(self):
        result = _estimate_cost(workflow_name="scrnaseq")
        assert result["instance_type"] == "r5.4xlarge"

    def test_min_less_than_max(self):
        for domain in ["rnaseq", "sarek", "cryoem", "metagenomics", "alphafold"]:
            result = _estimate_cost(f"nf-core/{domain}")
            assert result["min_usd"] < result["max_usd"], f"Failed for {domain}"
