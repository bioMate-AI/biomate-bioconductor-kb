"""
Shape tests for the Models + Inference API (models_inference.py).

These assert the EXACT response CONTRACT the new Models UI + DL viewers bind to,
independent of whether BioNeMo NIMs are reachable (stub payloads must have the
same shape as real ones).

The module is loaded in isolation with a stubbed ``Router`` so the test does not
require the full Galaxy webapp stack (which pulls in a2wsgi / gunicorn wiring).
"""
import importlib.util
import os
import sys
import types

import pytest

_MODULE_PATH = os.path.join(
    os.path.dirname(__file__),
    "..", "..", "..", "..",
    "lib", "galaxy", "webapps", "galaxy", "api", "models_inference.py",
)


def _load_module():
    """Load models_inference.py with a stubbed api-package Router."""
    pkg_name = "galaxy.webapps.galaxy.api"

    class _StubRouter:
        def __init__(self, *a, **k):
            pass

        def get(self, *a, **k):
            def deco(f):
                return f

            return deco

        def post(self, *a, **k):
            def deco(f):
                return f

            return deco

    # Only stub the api package if the real one can't be imported (a2wsgi absent).
    if pkg_name not in sys.modules:
        try:
            import galaxy.webapps.galaxy.api  # noqa: F401
        except Exception:
            for name in ["galaxy", "galaxy.webapps", "galaxy.webapps.galaxy"]:
                if name not in sys.modules:
                    m = types.ModuleType(name)
                    m.__path__ = []  # mark as package
                    sys.modules[name] = m
            stub = types.ModuleType(pkg_name)
            stub.Router = _StubRouter
            sys.modules[pkg_name] = stub

    spec = importlib.util.spec_from_file_location(
        "galaxy.webapps.galaxy.api.models_inference",
        os.path.abspath(_MODULE_PATH),
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture(scope="module")
def mod():
    return _load_module()


# ── GET /api/models row shape ────────────────────────────────────────────────
def test_catalog_row_shape(mod):
    required = {"id", "name", "family", "version", "origin", "usedByCount"}
    for row in mod._catalog():
        assert required <= set(row), row
        assert isinstance(row["usedByCount"], int)


def test_bionemo_catalog_present(mod):
    ids = {r["id"] for r in mod._bionemo_catalog()}
    # Structure + genomic evidence classes are both represented.
    assert "bionemo:boltz2" in ids
    assert "bionemo:evo2_7b" in ids
    for r in mod._bionemo_catalog():
        assert r["origin"] == "self-host"


# ── evidence class routing ───────────────────────────────────────────────────
def test_evidence_class_routing(mod):
    assert mod._evidence_class_for("bionemo:boltz2") == mod.STRUCTURE
    assert mod._evidence_class_for("bionemo:alphafold2") == mod.STRUCTURE
    assert mod._evidence_class_for("bionemo:evo2_7b") == mod.GENOMIC
    assert mod._evidence_class_for("custom:campaignA/myScorer") == mod.CHEMICAL


# ── stub payloads: correct shape per evidence class, labelled, no fake numbers ─
def test_structure_stub_shape(mod):
    s = mod._stub_result(mod.STRUCTURE, reason="unreachable")
    assert s["stub"] is True and "stub_reason" in s
    assert set(s) >= {"structureFileRef", "plddt", "pae", "regions"}
    assert s["plddt"] == [] and s["pae"] == [] and s["regions"] == []
    assert s["structureFileRef"] is None


def test_genomic_stub_shape(mod):
    g = mod._stub_result(mod.GENOMIC, reason="unreachable")
    assert g["stub"] is True
    assert set(g) >= {"locus", "tracks", "flagged"}
    assert g["tracks"] == [] and g["flagged"] == []


def test_chemical_stub_shape_no_fabricated_scores(mod):
    c = mod._stub_result(mod.CHEMICAL, reason="not loaded", smiles_list=["CCO", "c1ccccc1"])
    assert c["stub"] is True
    assert len(c["hits"]) == 2
    for hit in c["hits"]:
        assert set(hit) >= {"id", "smiles", "score", "confidence", "herg", "drugLike", "verdict"}
        # Stub NEVER fabricates a real score.
        assert hit["score"] is None
        assert hit["verdict"] in {"accepted", "flagged", "rejected", "held"}
        assert hit["confidence"] in {"high", "medium", "low"}


# ── helpers ──────────────────────────────────────────────────────────────────
def test_interface_kind_mapping(mod):
    assert mod._custom_interface_kind("docker") == "container"
    assert mod._custom_interface_kind("rest") == "rest"
    assert mod._custom_interface_kind("python") == "python"
    assert mod._custom_interface_kind("anything-else") == "python"


def test_parse_custom_id(mod):
    assert mod._parse_custom_id("custom:c1/foo") == ("c1", "foo")
    assert mod._parse_custom_id("custom:c1/foo/bar") == ("c1", "foo/bar")
    assert mod._parse_custom_id("bionemo:boltz2") is None
    assert mod._parse_custom_id("custom:no-slash") is None


def test_plddt_from_pdb(mod):
    line = (
        "ATOM      1  CA  MET A   1      "
        "11.100  22.200  33.300  1.00 87.65           C  "
    )
    assert mod._plddt_from_pdb(line) == [87.65]
    assert mod._plddt_from_pdb("") == []
    assert mod._plddt_from_pdb("not a pdb") == []
