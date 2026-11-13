"""A null-default param is required only unless the workflow's own code handles its absence."""
import importlib.util
from pathlib import Path

_p = Path(__file__).resolve().parents[1] / "lib" / "galaxy" / "ai" / "nf_param_requirement.py"
_s = importlib.util.spec_from_file_location("nf_param_requirement", _p)
m = importlib.util.module_from_spec(_s); _s.loader.exec_module(m)
REQ = m.null_param_is_required
ROOT = Path(__file__).resolve().parents[1] / "biomni_workflows"


def test_optional_by_elvis_and_null_checks():
    src = "def bc = params.box_center ?: ''\ndef c = params.control_edge_expected != null ? 1 : 0\nif (params.seed) { x }"
    assert REQ(src, "box_center") is False
    assert REQ(src, "control_edge_expected") is False
    assert REQ(src, "seed") is False


def test_required_when_enforced():
    assert REQ("if (!params.receptor) { error 'params.receptor is required' }\nparams.receptor ?: ''", "receptor") is True
    assert REQ('if (!params.input_structure) {\n  exit 1, "Please provide --input_structure"\n}', "input_structure") is True
    assert REQ("ERROR: --receptor is required (path)", "receptor") is True


def test_no_evidence_keeps_required():
    assert REQ("Channel.fromPath(params.ligand)", "ligand") is True


def test_demo_elvis_still_required_for_clinic():
    """CryoSPA: params.movies_path ?: test_data must NOT look optional to clinic users."""
    src = 'def movies_path_str = params.movies_path ?: "${baseDir}/test_data"\n'
    assert REQ(src, "movies_path") is True
    # Empty-string elvis remains optional (real absence handling, not demo data).
    assert REQ("def bc = params.box_center ?: ''\n", "box_center") is False


def test_real_cryo_movies_path_required():
    cryo = (
        ROOT / "nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf"
    ).read_text()
    assert REQ(cryo, "movies_path") is True


def test_real_md_workflows():
    gmx = (ROOT / "nextflow_nfcore/subworkflows/drug_discovery/gromacs_protein_md/main.nf").read_text()
    assert REQ(gmx, "box_center") is False and REQ(gmx, "box_size") is False
    assert REQ(gmx, "receptor") is True
    fep = (ROOT / "nfcore/gromacs_pmx_fep/main.nf").read_text()
    assert REQ(fep, "control_edge_expected") is False
    assert REQ(fep, "receptor") is True
