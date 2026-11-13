"""CryoSPARC license scan must match cryosparc_standard_spa path (underscore)."""
import importlib.util
from pathlib import Path

_p = Path(__file__).resolve().parents[1] / "lib/galaxy/webapps/galaxy/api/license_registry.py"
_s = importlib.util.spec_from_file_location("license_registry", _p)
m = importlib.util.module_from_spec(_s)
_s.loader.exec_module(m)


def test_cryosparc_standard_spa_path_detected():
    # Previously `\bcryosparc\b` missed cryosparc_standard_spa (_ is a word char).
    path = "nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf"
    assert "cryosparc" in m.scan_nf_for_tool_ids(path)


def test_structura_biology_path_does_not_false_match_structura():
    # "structura" pattern must not match "structural_biology"
    path = "nextflow_nfcore/subworkflows/structural_biology/foldseek_structure_search/main.nf"
    assert "cryosparc" not in m.scan_nf_for_tool_ids(path)
