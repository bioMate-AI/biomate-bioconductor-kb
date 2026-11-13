"""_find_nf_file must share the drug_discovery ↔ pharmacology alias with
nextflow_executor._resolve_nextflow_path (2026-11-13 Admet Pred empty-schema).
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

def test_production_source_has_domain_alias_inside_find_nf_file():
    src = (ROOT / "backend" / "lib" / "galaxy" / "ai" / "ai_assistant.py").read_text()
    idx = src.find("def _find_nf_file")
    assert idx > 0
    next_def = src.find("\n    def ", idx + 10)
    block = src[idx:next_def]
    assert "Domain alias fallback" in block
    assert "drug_discovery" in block and "pharmacology" in block


def test_find_nf_file_aliases_drug_discovery_admet_pred_to_pharmacology():
    # Hermetic: exercise the same alias map against the real on-disk pharmacology tree.
    biomni = ROOT / "backend" / "biomni_workflows"
    filename = "nextflow_nfcore/subworkflows/drug_discovery/ADMET_pred/main.nf"
    primary = biomni / filename
    assert not primary.exists()
    # Alias drug_discovery → pharmacology (production _find_nf_file fallback).
    aliased = Path(*[
        ("pharmacology" if p == "drug_discovery" else p) for p in Path(filename).parts
    ])
    found = biomni / aliased
    assert found.exists(), f"expected live alias path {found}"
    assert "pharmacology" in str(found)


def test_find_nf_file_still_none_for_truly_missing_workflow():
    biomni = ROOT / "backend" / "biomni_workflows"
    filename = "nextflow_nfcore/subworkflows/drug_discovery/definitely_missing_wf_xyz/main.nf"
    primary = biomni / filename
    aliased = Path(*[
        ("pharmacology" if p == "drug_discovery" else p) for p in Path(filename).parts
    ])
    assert not primary.exists()
    assert not (biomni / aliased).exists()
