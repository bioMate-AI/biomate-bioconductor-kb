"""Fabrication guard for drug-discovery + pharmacology Nextflow workflows.

Context (2026-09-22 fabrication sweep): several workflows emitted fake
"predictions" produced by a hash-seeded RNG dressed as real activity/IC50/CLint
values (e.g. ``np.random.default_rng(fp_hash)`` feeding ``predicted_IC50_uM``).
The FEP (``openfe_rbfe``) fix established the pattern: either compute a REAL
value, or apply an HONESTY CONTRACT (null + ``requires_real_model`` / labelled
deterministic heuristic) — never emit fabricated numbers.

This test closes the whole CLASS with a static guard so the fabrication
signature cannot silently return. It scans every ``main.nf`` under the two
subworkflow trees and fails if it finds a molecule/fingerprint-hash-seeded RNG,
which is the tell-tale of "deterministic-but-arbitrary noise dressed as a
prediction".

Legitimate Monte-Carlo simulation (clinical-trial simulation, PK IIV, power
calcs, VPC, bootstrap) uses a FIXED integer seed (``default_rng(42)``,
``random.seed(42)``) and is explicitly allowed.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parents[2]
_SUBWF = _ROOT / "backend" / "biomni_workflows" / "nextflow_nfcore" / "subworkflows"
_TREES = [_SUBWF / "drug_discovery", _SUBWF / "pharmacology"]

# The fabrication signature: an RNG seeded by a molecule/structure/fingerprint
# hash. Seeding an RNG from the *input molecule* is never a legitimate
# simulation — it exists only to make arbitrary noise look like a reproducible
# per-compound "prediction".
_HASH_SEEDED_RNG = re.compile(
    r"(default_rng|np\.random\.seed|random\.seed|RandomState)\s*\(\s*[^)]*"
    r"(hash\s*\(|fp_hash|md5|sha1|sha256|hexdigest|\.digest\()",
    re.IGNORECASE,
)


def _main_nf_files():
    files = []
    for tree in _TREES:
        if tree.exists():
            files.extend(sorted(tree.glob("*/main.nf")))
    return files


def _strip_comment_lines(text: str) -> str:
    """Drop explanatory comment lines so we only flag LIVE code.

    The fixed files intentionally *describe* the old fabrication in comments
    (``# The previous version added np.random.default_rng(fp_hash) ...``); those
    must not trip the guard.
    """
    kept = []
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("#") or stripped.startswith("*") or stripped.startswith("//"):
            continue
        kept.append(line)
    return "\n".join(kept)


def test_workflow_trees_present():
    files = _main_nf_files()
    assert files, f"no workflow main.nf found under {_TREES}"


@pytest.mark.parametrize("nf", _main_nf_files(), ids=lambda p: p.parent.name)
def test_no_hash_seeded_rng_fabrication(nf: Path):
    """No workflow may seed an RNG from a molecule/fingerprint hash (live code)."""
    code = _strip_comment_lines(nf.read_text())
    m = _HASH_SEEDED_RNG.search(code)
    assert m is None, (
        f"{nf.parent.name}/main.nf contains a hash-seeded RNG "
        f"(fabrication signature): {m.group(0)!r}. Replace with a real "
        f"computation or an honesty contract (null + requires_real_model)."
    )


def test_proteome_selectivity_has_honesty_contract():
    """The proteome selectivity fallback must fail loudly, not fabricate IC50s."""
    nf = _SUBWF / "drug_discovery" / "proteome_selectivity_profiling" / "main.nf"
    text = nf.read_text()
    assert "requires_real_model" in text
    assert "descriptor_estimate" not in _strip_comment_lines(text), (
        "the fabricated source='descriptor_estimate' path must be gone from live code"
    )
    # No RNG-based synthetic panel generator remains callable.
    live = _strip_comment_lines(text)
    assert "descriptor_based_panel(" not in live


def test_cyp_ddi_panel_labels_heuristic_and_drops_false_model_claims():
    """CYP IC50 / CLint must be labelled a heuristic, not a 'trained RF QSAR'."""
    nf = _SUBWF / "drug_discovery" / "cyp_ddi_panel" / "main.nf"
    text = nf.read_text()
    live = _strip_comment_lines(text)
    # Honest provenance is emitted.
    assert "physchem_heuristic" in text
    assert "ic50_disclaimer" in text or "ic50_method" in text
    # No live code claims a trained/validated model or fabricated ROC-AUC.
    assert "ROC-AUC" not in live, "remove false accuracy claim from live code"
    assert "Random Forest, trained on ChEMBL" not in live
    # No live hash-seeded RNG.
    assert "default_rng(fp_hash" not in live


def test_hts_demo_plate_is_labelled_synthetic():
    """The HTS demo-plate generator must tag its output as synthetic_demo."""
    nf = _SUBWF / "drug_discovery" / "hts_plate_qc_hit_calling" / "main.nf"
    text = nf.read_text()
    assert "synthetic_demo" in text
    assert "data_source" in text
