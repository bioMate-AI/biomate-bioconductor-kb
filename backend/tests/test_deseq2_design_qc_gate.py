"""Stream-6 design-formula self-correction: verify the new `design formula`
gate emitted by the differentialabundance stub flows through the realized
bioconductor_qc gate pathway (read_bioc_harness_gates).

Run:  cd backend && PYTHONPATH=lib python3 -m pytest tests/test_deseq2_design_qc_gate.py -q
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))

from galaxy.ai.retrievers.qc_gate_reader import read_bioc_harness_gates


# qc_metrics.json exactly as the patched stub emits it when `cell` confounds ~dex.
QC_METRICS = {
    "success": True,
    "process": "DESEQ2_DIFFERENTIAL_ANALYSIS",
    "domain": "transcriptomics",
    "gates_by_label": {
        "differential expression": {
            "gate_row": "deseq2_differential_expression",
            "metric_name": "n_significant_genes",
            "metric_value": 2724,
            "passes": True,
            "status": "2724 genes significant",
        },
        "design formula": {
            "gate_row": "bioc_deseq2_design_blocking",
            "metric_name": "blocked_covariate_significant_genes",
            "metric_value": 9123,            # genes varying by the blocking factor 'cell'
            "passes": False,
            "blocking_var": "cell",
            "status": "Confounder 'cell' omitted from naive design ~dex; re-fit as ~cell+dex",
        },
    },
}


def test_design_formula_gate_fires_as_fail():
    gates = read_bioc_harness_gates(QC_METRICS)
    rows = {g[0]: g for g in gates}
    assert "bioc_deseq2_design_blocking" in rows, "design gate not surfaced"
    g = rows["bioc_deseq2_design_blocking"]
    # tuple shape: (gate_row, value, threshold, passes, level, message)
    assert g[3] is False            # passes == False
    assert g[4] == "FAIL"           # level
    assert float(g[1]) == 9123.0    # numeric metric (must be float-able)
    # the pre-existing DE gate still passes
    assert rows["deseq2_differential_expression"][3] is True


def test_no_confounder_means_no_design_gate():
    m = {"gates_by_label": {
        "differential expression": {
            "gate_row": "deseq2_differential_expression",
            "metric_name": "n_significant_genes", "metric_value": 2000, "passes": True,
        }}}
    gates = read_bioc_harness_gates(m)
    rows = {g[0] for g in gates}
    assert "bioc_deseq2_design_blocking" not in rows


if __name__ == "__main__":
    import pytest, sys as _s
    _s.exit(pytest.main([__file__, "-q"]))
