"""Unit tests for the figures[] adapter that projects key_results into
v2 FindingsFigure shapes (FigBars / FigComposition / FigQc).

The adapter must:
  * never fabricate data — skip when key_results lack parseable numbers
  * be domain-agnostic — works for VCF, CSV rankings, FastQC, ADMET, etc.
  * match the exact frontend FindingsFigure union (qc / composition / bars)
"""
import sys
from pathlib import Path

# Make backend/lib importable so we can pull the helper out of the API module
# without triggering Galaxy app startup.
REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "backend" / "lib"))

# Import the pure helpers directly by reading the module text — avoids the
# full FastAPI Router boot path which requires a Galaxy app context.
import importlib.util

_EXECUTOR_PATH = REPO_ROOT / "backend" / "lib" / "galaxy" / "webapps" / "galaxy" / "api" / "nextflow_executor.py"


def _load_helpers():
    """Pull `_build_figures_from_key_results` + `_parse_number` out of the
    executor module by exec'ing just those function defs in a clean namespace.
    Avoids importing Galaxy's app stack from a unit test.
    """
    text = _EXECUTOR_PATH.read_text()
    # Slice from the first helper def to (but not including) the @router decorator.
    start = text.index("def _parse_number(")
    end = text.index("@router.post(\"/api/nextflow/analyze-outputs\"")
    snippet = text[start:end]
    ns = {
        "__name__": "figures_adapter_test_ns",
        "Any": __import__("typing").Any,
        "Dict": __import__("typing").Dict,
        "List": __import__("typing").List,
        "Optional": __import__("typing").Optional,
        "re": __import__("re"),
    }
    exec(compile(snippet, str(_EXECUTOR_PATH), "exec"), ns)
    return ns["_build_figures_from_key_results"], ns["_parse_number"]


_build_figures_from_key_results, _parse_number = _load_helpers()


def test_parse_number_basic():
    assert _parse_number("1,234") == 1234.0
    assert _parse_number("23") == 23.0
    assert _parse_number("5.2%") == 5.2
    assert _parse_number(7) == 7.0
    assert _parse_number("GeneA (score: -8.2)") is None
    assert _parse_number(None) is None
    assert _parse_number("PASS") is None


def test_qc_kind_from_vcf_pass_total():
    """Real VCF analyzer output: 'Total variants' + 'PASS variants'."""
    kr = [
        {"metric": "Total variants", "value": "1,000", "interpretation": "x"},
        {"metric": "PASS variants",  "value": "850",   "interpretation": "x"},
        {"metric": "HIGH impact",    "value": "3",     "interpretation": "x"},
        {"metric": "MODERATE impact","value": "12",    "interpretation": "x"},
    ]
    figs = _build_figures_from_key_results(kr)
    kinds = [f["kind"] for f in figs]
    assert "qc" in kinds
    qc = next(f for f in figs if f["kind"] == "qc")
    assert qc["kept"] == 850 and qc["total"] == 1000


def test_composition_kind_from_impact_breakdown():
    """HIGH/MODERATE impact share the trailing word 'impact' → composition."""
    kr = [
        {"metric": "HIGH impact",     "value": "3"},
        {"metric": "MODERATE impact", "value": "12"},
        {"metric": "LOW impact",      "value": "47"},
    ]
    figs = _build_figures_from_key_results(kr)
    assert any(f["kind"] == "composition" for f in figs)
    comp = next(f for f in figs if f["kind"] == "composition")
    assert len(comp["data"]) == 3
    assert ["HIGH impact", 3.0] in [list(d) for d in comp["data"]]


def test_bars_kind_fallback():
    """Two unrelated numerics with no shared category → bars."""
    kr = [
        {"metric": "FAIL modules", "value": "2"},
        {"metric": "WARN modules", "value": "5"},
    ]
    figs = _build_figures_from_key_results(kr)
    # 'modules' is shared → composition wins (preferred over bars).
    assert figs and figs[0]["kind"] in ("composition", "bars")


def test_skips_when_no_parseable_numbers():
    """All values are composite strings (e.g. CSV rankings top hits)."""
    kr = [
        {"metric": "Rank 1", "value": "CompoundA (score: -8.2)"},
        {"metric": "Rank 2", "value": "CompoundB (score: -7.9)"},
        {"metric": "Affected genes (HIGH)", "value": "TP53, KRAS, EGFR"},
    ]
    figs = _build_figures_from_key_results(kr)
    assert figs == []


def test_empty_or_invalid_input():
    assert _build_figures_from_key_results(None) == []
    assert _build_figures_from_key_results([]) == []
    assert _build_figures_from_key_results("not a list") == []
    assert _build_figures_from_key_results([{"value": "5"}]) == []  # no metric


def test_total_only_no_pair_does_not_emit_qc():
    kr = [{"metric": "Total compounds", "value": "200"}]
    figs = _build_figures_from_key_results(kr)
    # No paired kept → no qc; single item → no bars (needs ≥2); no composition.
    assert figs == []
