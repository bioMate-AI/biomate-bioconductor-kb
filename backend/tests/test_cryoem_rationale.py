"""Unit tests for _build_cryoem_rationale() in ai_assistant.py.

Extracts the function via AST so it runs without the full Galaxy/FastAPI stack.
All tests are pure-Python; no network, no DB, no mocking.
"""
import ast
import re
import typing
import sys
import os
import pytest

# ── Extract the function from source ─────────────────────────────────────────

_SOURCE_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "lib", "galaxy", "webapps", "galaxy", "api", "ai_assistant.py",
)


def _load_function():
    with open(_SOURCE_PATH) as f:
        src = f.read()
    tree = ast.parse(src)
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == "_build_cryoem_rationale":
            func_src = ast.get_source_segment(src, node)
            ns = {
                "re": re,
                "List": typing.List,
                "Dict": typing.Dict,
                "Any": typing.Any,
            }
            exec(compile(func_src, _SOURCE_PATH, "exec"), ns)
            return ns["_build_cryoem_rationale"]
    raise ValueError("_build_cryoem_rationale not found in ai_assistant.py")


_fn = _load_function()


# ── Helper ────────────────────────────────────────────────────────────────────

def _call(intent: str):
    result = _fn(intent)
    assert "cryo_em_domain_hints" in result
    assert "cryo_em_guidance" in result
    assert isinstance(result["cryo_em_domain_hints"], list)
    assert isinstance(result["cryo_em_guidance"], list)
    return result


def _param_names(result) -> list:
    return [h["param"] for h in result["cryo_em_domain_hints"]]


def _recommended(result, param: str) -> str:
    for h in result["cryo_em_domain_hints"]:
        if h["param"] == param:
            return h["recommended"]
    return ""


def _guidance_text(result) -> str:
    return " ".join(result["cryo_em_guidance"])


# ── TC-1: Membrane transporter in saposin nanodisc ───────────────────────────

def test_membrane_transporter_saposin_nanodisc():
    """Plain membrane transporter query (no GPCR terms) → membrane_small."""
    result = _call(
        "I want to solve the structure of a membrane transporter in saposin nanodisc at 3 angstrom resolution"
    )
    params = _param_names(result)
    assert "sample_class" in params, "sample_class hint missing"
    assert _recommended(result, "sample_class") == "membrane_small"
    assert "pixel_size" in params, "pixel_size hint missing for membrane_small"
    assert _recommended(result, "pixel_size") == "0.649"
    # 3 Å → 50,000–200,000 particles (tr < 3.5 branch)
    assert "target_resolution_A" in params
    assert "50,000" in _recommended(result, "target_resolution_A") or \
           "50,000" in _guidance_text(result) or \
           "50,000" in result["cryo_em_domain_hints"][-1]["rationale"] or \
           any("50,000" in h["rationale"] for h in result["cryo_em_domain_hints"])


# ── TC-2: GPCR — mu-opioid receptor Gi complex ───────────────────────────────

def test_gpcr_mu_opioid_receptor_gi_complex_in_nanodisc():
    """GPCR with 'Gi complex' keyword must NOT be swallowed by the nanodisc branch."""
    result = _call(
        "run cryoem spa for mu-opioid receptor Gi complex in nanodisc"
    )
    assert _recommended(result, "sample_class") == "gpcr_g_protein", (
        "mu-opioid receptor Gi complex in nanodisc was misclassified — "
        "GPCR check must precede nanodisc/membrane check"
    )
    # Should mention MSP1D1 nanodisc protocol
    rationale = next(
        h["rationale"] for h in result["cryo_em_domain_hints"]
        if h["param"] == "sample_class"
    )
    assert "MSP1D1" in rationale


def test_gpcr_plain_keyword():
    """Bare 'GPCR' keyword → gpcr_g_protein."""
    result = _call("cryo-EM structure of a GPCR at 3.2 angstrom")
    assert _recommended(result, "sample_class") == "gpcr_g_protein"


def test_gpcr_g_protein_phrase():
    """'G protein' two-word phrase → gpcr_g_protein."""
    result = _call("solve structure of beta2 adrenergic receptor G protein complex")
    assert _recommended(result, "sample_class") == "gpcr_g_protein"


# ── TC-3: Drug binding / CaV1.2 ──────────────────────────────────────────────

def test_drug_binding_triggers_dataset_rule():
    """'drug' keyword → DATASET RULE guidance with apo reference requirement."""
    result = _call(
        "solve structure of CaV1.2 ion channel with 3 drug compounds at 3.5 angstrom"
    )
    text = _guidance_text(result)
    assert "apo" in text.lower(), "Dataset rule must mention apo reference"
    assert "4" in text and "\u03c3" in text or "4σ" in text or "4sigma" in text.lower() or \
           "≥ 4" in text, "4σ threshold must appear in guidance"


def test_compound_keyword_also_triggers_dataset_rule():
    """'compound' → same DATASET RULE as 'drug'."""
    result = _call("cryo-EM of ABC transporter with compound library")
    text = _guidance_text(result)
    assert "DATASET RULE" in text


# ── TC-4: Pore-forming ────────────────────────────────────────────────────────

def test_pore_forming_bax_liposome():
    """BAX pore on liposomes → pore_forming with TOPAZ mention."""
    result = _call("determine BAX pore structure on liposomes")
    assert _recommended(result, "sample_class") == "pore_forming"
    rationale = next(
        h["rationale"] for h in result["cryo_em_domain_hints"]
        if h["param"] == "sample_class"
    )
    assert "TOPAZ" in rationale


# ── TC-5: Symmetric / capsid ─────────────────────────────────────────────────

def test_symmetric_hbv_capsid_icosahedral():
    """HBV capsid icosahedral → symmetric; rationale should mention C1."""
    result = _call("structure of HBV capsid icosahedral")
    assert _recommended(result, "sample_class") == "symmetric"
    rationale = next(
        h["rationale"] for h in result["cryo_em_domain_hints"]
        if h["param"] == "sample_class"
    )
    assert "C1" in rationale, "symmetric branch should advise starting in C1"


# ── TC-6: Conformational states ───────────────────────────────────────────────

def test_conformational_states_open_and_closed():
    """'open and closed' → CONFORMATIONAL STATES guidance with 3DVA mention."""
    result = _call("solve open and closed states of sodium channel")
    text = _guidance_text(result)
    assert "3DVA" in text or "3D Variability" in text


def test_single_word_state_does_not_falsely_trigger():
    """Bare 'state' without conformational context must NOT trigger the 3DVA guidance."""
    result = _call("analyze oxidation state of iron-sulfur cluster by cryo-EM")
    text = _guidance_text(result)
    assert "3DVA" not in text, (
        "The word 'state' alone should not trigger CONFORMATIONAL STATES guidance"
    )


# ── TC-7: Non-cryo-EM query ───────────────────────────────────────────────────

def test_non_cryoem_query_universal_rules_still_present():
    """Any query gets universal rules (function is invoked only for cryo-EM workflows,
    but we still verify the universal block fires unconditionally)."""
    result = _call("analyze my WGS data with GATK germline variant calling")
    text = _guidance_text(result)
    assert "FSC" in text, "Universal rules (FSC 0.143) must always be injected"
    assert "MolProbity" in text


def test_non_cryoem_query_no_false_positive_sample_class():
    """WGS query should produce no cryo_em_domain_hints."""
    result = _call("analyze my WGS data with GATK germline variant calling")
    assert len(result["cryo_em_domain_hints"]) == 0, (
        "Non-cryo-EM query should produce 0 hints, got: "
        + str(_param_names(result))
    )


def test_non_cryoem_query_no_resolution_false_positive():
    """A sentence with standalone 'a' and a number must not trigger resolution hint."""
    result = _call("use at least 3 a priori defined cell populations for analysis")
    # Resolution regex must NOT match "3 a" — bare 'a\b' was removed
    assert "target_resolution_A" not in _param_names(result), (
        "Bare 'a' in text caused a false-positive resolution hit"
    )


# ── TC-8: Resolution extraction ───────────────────────────────────────────────

def test_resolution_2_2_angstrom_over_one_million():
    """2.2 angstrom → > 1,000,000 particles (tr < 2.5 branch)."""
    result = _call("cryo-EM structure at 2.2 angstrom resolution")
    assert "target_resolution_A" in _param_names(result)
    hint = next(h for h in result["cryo_em_domain_hints"] if h["param"] == "target_resolution_A")
    assert hint["recommended"] == "2.2"
    assert "1,000,000" in hint["rationale"]


def test_resolution_3_5_angstrom_bucket():
    """3.5 angstrom → 20,000–50,000 particles (3.5 is not < 3.5, falls to < 4.5 bucket)."""
    result = _call("solve structure of CaV1.2 at 3.5 angstrom")
    hint = next(h for h in result["cryo_em_domain_hints"] if h["param"] == "target_resolution_A")
    assert hint["recommended"] == "3.5"
    # Boundary: 3.5 is NOT < 3.5, so it should land in the 20,000–50,000 bucket
    assert "20,000" in hint["rationale"]


def test_resolution_extracted_via_word_resolution():
    """Fallback: '3 resolution' in text when angstrom not mentioned."""
    result = _call("target resolution 3 resolution for the project")
    hint_params = _param_names(result)
    assert "target_resolution_A" in hint_params


def test_resolution_uppercase_angstrom_not_matched():
    """The regex is applied on lowercased intent so 'Angstrom' is matched correctly."""
    result = _call("cryo-EM at 2.8 Angstrom resolution")
    hint_params = _param_names(result)
    assert "target_resolution_A" in hint_params
    hint = next(h for h in result["cryo_em_domain_hints"] if h["param"] == "target_resolution_A")
    assert hint["recommended"] == "2.8"


# ── TC-9: Heterogeneity depth ─────────────────────────────────────────────────

def test_heterogeneous_keyword_triggers_depth_hint():
    """'heterogeneous' keyword → heterogeneity hint."""
    result = _call("cryo-EM of a highly heterogeneous spliceosome complex")
    assert "heterogeneity" in _param_names(result)
    hint = next(h for h in result["cryo_em_domain_hints"] if h["param"] == "heterogeneity")
    assert hint["recommended"] == "medium"
    assert "3DVA" in hint["rationale"]


def test_conformational_ensemble_triggers_depth_hint():
    """'conformational ensemble' → heterogeneity hint."""
    result = _call("cryo-EM to map the conformational ensemble of a kinase")
    assert "heterogeneity" in _param_names(result)


# ── TC-10: Large RNP ──────────────────────────────────────────────────────────

def test_ribosome_class():
    """Ribosome → large_rna_protein class."""
    result = _call("cryo-EM structure of the human 80S ribosome")
    assert _recommended(result, "sample_class") == "large_rna_protein"


def test_spliceosome_class():
    """Spliceosome → large_rna_protein class."""
    result = _call("solve spliceosome complex by cryo-EM")
    assert _recommended(result, "sample_class") == "large_rna_protein"


# ── TC-11: Return structure ───────────────────────────────────────────────────

def test_return_keys_always_present():
    """Function always returns both keys regardless of input."""
    for intent in ["", "hello", "cryo-EM SPA", "GPCR nanodisc"]:
        result = _fn(intent)
        assert "cryo_em_domain_hints" in result
        assert "cryo_em_guidance" in result


def test_all_hints_have_required_fields():
    """Every hint dict must have param, recommended, rationale, tool."""
    result = _call(
        "cryo-EM of mu-opioid receptor Gi complex in nanodisc, heterogeneous, "
        "at 3.0 angstrom resolution with drug compound"
    )
    for hint in result["cryo_em_domain_hints"]:
        assert "param" in hint, f"Missing 'param' in {hint}"
        assert "recommended" in hint, f"Missing 'recommended' in {hint}"
        assert "rationale" in hint, f"Missing 'rationale' in {hint}"
        assert "tool" in hint, f"Missing 'tool' in {hint}"
        assert hint["tool"] == "CryoSPARC"


# ── TC-12: Pre-cryo-EM checklist (G1-G5) ─────────────────────────────────────

def test_new_project_triggers_precryoem_checklist():
    result = _fn("I want to determine the structure of VMAT2 membrane transporter")
    guidance_text = " ".join(result["cryo_em_guidance"])
    assert "G1 PURITY" in guidance_text or "PRE-CRYO-EM" in guidance_text


def test_existing_data_suppresses_checklist():
    result = _fn("I already collected cryo-EM movies and want to reprocess them")
    guidance_text = " ".join(result["cryo_em_guidance"])
    assert "PRE-CRYO-EM" not in guidance_text


def test_empiar_suppresses_checklist():
    result = _fn("process EMPIAR-10061 beta-galactosidase dataset")
    guidance_text = " ".join(result["cryo_em_guidance"])
    assert "PRE-CRYO-EM" not in guidance_text
