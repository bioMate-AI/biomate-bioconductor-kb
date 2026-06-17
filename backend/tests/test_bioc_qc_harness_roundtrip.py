"""End-to-end local round-trip test for BIOC_QC_HARNESS adoption.

Asserts that the Nextflow inject block → R execution → qc_metrics.json
→ read_bioc_harness_gates() chain produces the right audit tuples
across all three compute tiers (matrix-scan, object-aware, declarative)
and that status='not_computed' correctly suppresses tuple emission.

Zero AWS cost; runs locally via Rscript. Catches reader/inject drift
that the static + dynamic R-block tests can't see on their own.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))
from galaxy.ai.retrievers.qc_gate_reader import read_bioc_harness_gates  # noqa: E402


def _run_block(nf_rel: str, fixture_r: str) -> dict:
    src = (ROOT / "backend/biomni_workflows" / nf_rel).read_text()
    m = re.search(
        r'(\.qc_metrics_path\s*<-\s*"qc_metrics\.json".*?)writeLines\(c\(',
        src, re.DOTALL,
    )
    assert m, f"inject block not found in {nf_rel}"
    block = m.group(1).replace(r"\$", "$")
    with tempfile.TemporaryDirectory() as td:
        (Path(td) / "block.R").write_text(fixture_r + "\n" + block)
        r = subprocess.run(
            ["Rscript", "--vanilla", "block.R"],
            cwd=td, capture_output=True, text=True, timeout=15,
        )
        assert r.returncode == 0, f"Rscript failed:\n{r.stderr}"
        return json.loads((Path(td) / "qc_metrics.json").read_text())


def test_matrix_scan_tier_emits_tuple():
    """a4 with synthetic NA-injected matrix → bioc_missing_value_handling tuple."""
    payload = _run_block(
        "nextflow_nfcore/subworkflows/bioconductor/a4/main.nf",
        'set.seed(1); m <- matrix(rnorm(1000), 100, 10); m[sample(1000,20)] <- NA; saveRDS(m, "x.rds")',
    )
    tuples = read_bioc_harness_gates(payload)
    assert len(tuples) == 1
    gate_row, value, _, passes, level, _ = tuples[0]
    assert gate_row == "bioc_missing_value_handling"
    assert value == 0.02
    assert passes is True
    assert level == "GOLD"


def test_not_computed_suppresses_tuple_emission():
    """a4 with empty working dir → status=not_computed → reader emits no tuple.
    Gate row still lands in qc_metrics.json for audit ledger; reader-side
    suppression prevents it from triggering a false advisory.
    """
    payload = _run_block(
        "nextflow_nfcore/subworkflows/bioconductor/a4/main.nf",
        "invisible(NULL)",
    )
    status = payload["gates_by_label"]["missing-value handling"]["status"]
    assert status.startswith("not_computed")
    assert read_bioc_harness_gates(payload) == []


def test_object_aware_tier_with_mock_dgelist():
    """biobroom (TMM + dispersion) with a mock DGEList → both tuples emit.
    Uses class<-'DGEList' to avoid needing edgeR installed locally."""
    fixture = """
    dge <- list(samples = data.frame(norm.factors = c(0.9, 1.0, 1.1, 1.2, 0.8, 1.05)),
                common.dispersion = 0.25)
    class(dge) <- "DGEList"
    saveRDS(dge, "dge.rds")
    """
    payload = _run_block(
        "nextflow_nfcore/subworkflows/bioconductor/biobroom/main.nf",
        fixture,
    )
    tuples = read_bioc_harness_gates(payload)
    gate_rows = sorted(t[0] for t in tuples)
    assert gate_rows == ["bioc_dispersion_size_factor", "bioc_tmm_normalization"]
    by_row = {t[0]: t for t in tuples}
    assert by_row["bioc_tmm_normalization"][1] == 5.0  # 5 of 6 norm factors != 1
    assert by_row["bioc_dispersion_size_factor"][1] == 0.5  # sqrt(0.25) BCV
    assert all(t[3] is True for t in tuples)  # both pass


def test_declarative_tier_file_exists_emits_tuple():
    """batchqc (batch-effect correction) with a corrected_*.rds fixture →
    tuple emits with the declarative gate row."""
    payload = _run_block(
        "nextflow_nfcore/subworkflows/bioconductor/batchqc/main.nf",
        'm <- matrix(rnorm(100), 10, 10); saveRDS(m, "corrected_expr.rds")',
    )
    tuples = read_bioc_harness_gates(payload)
    assert len(tuples) == 1
    gate_row, value, _, passes, _, _ = tuples[0]
    assert gate_row == "bioc_batch_effect_correction"
    assert value == 1  # one corrected_*.rds present
    assert passes is True


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
