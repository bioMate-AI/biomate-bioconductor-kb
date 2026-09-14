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


def test_plddt_from_cif(mod):
    # boltz2 / AlphaFold2 / OpenFold2 return an mmCIF whose _atom_site.
    # B_iso_or_equiv column holds per-residue pLDDT — extract it for CA atoms,
    # reading column order from the loop header (order-independent).
    cif = "\n".join([
        "data_model",
        "loop_",
        "_atom_site.group_PDB",
        "_atom_site.label_atom_id",
        "_atom_site.label_comp_id",
        "_atom_site.label_seq_id",
        "_atom_site.B_iso_or_equiv",
        "ATOM N MET 1 55.5",
        "ATOM CA MET 1 60.2",
        "ATOM C MET 1 58.0",
        "ATOM CA LYS 2 72.8",
        "ATOM CA THR 3 88.1",
    ])
    assert mod._plddt_from_cif(cif) == [60.2, 72.8, 88.1]
    # Column order independence + quoted atom id + HETATM handling.
    cif2 = "\n".join([
        "loop_",
        "_atom_site.group_PDB",
        "_atom_site.B_iso_or_equiv",
        "_atom_site.label_atom_id",
        'ATOM 91.0 "CA"',
        "ATOM 12.0 N",
    ])
    assert mod._plddt_from_cif(cif2) == [91.0]
    assert mod._plddt_from_cif("") == []
    assert mod._plddt_from_cif("no atom_site here") == []


def test_plddt_from_structure_prefers_cif_then_pdb(mod):
    cif = "\n".join([
        "loop_", "_atom_site.group_PDB", "_atom_site.label_atom_id",
        "_atom_site.B_iso_or_equiv", "ATOM CA 77.0",
    ])
    assert mod._plddt_from_structure(cif) == [77.0]
    pdb = (
        "ATOM      1  CA  MET A   1      "
        "11.100  22.200  33.300  1.00 65.30           C  "
    )
    assert mod._plddt_from_structure(pdb) == [65.30]  # falls back to PDB


# ── B1 regression: dispatch must trust the client's mode, NOT NVIDIA_API_KEY ──
# The production posture is self_host (a URL, no key). A key-only gate stubbed
# out every inference even with the NIM up. These prove the gate is removed.
def _install_fake_bionemo(effective_mode, boltz2_return):
    """Register a fake galaxy.ai.bionemo_client so the lazy import in
    _dispatch_bionemo resolves to a network-free stub client. We inject only the
    leaf module — the real ``galaxy.ai`` package imports fine and other tests
    (B2) need the real ``galaxy.ai.runs.run_state_store`` under it."""
    import types as _types

    class _FakeClient:
        def _effective_mode(self):
            return effective_mode

        @staticmethod
        def _is_stub(raw):
            return isinstance(raw, dict) and raw.get("_stub") is True

        @staticmethod
        def _stub_reason(model, mode):
            return f"no backend configured for {model!r} (mode {mode})"

        def boltz2(self, sequence):
            return boltz2_return

    fake = _types.ModuleType("galaxy.ai.bionemo_client")
    fake.BioNeMoClient = _FakeClient
    fake.MODE_STUB = "stub"
    sys.modules["galaxy.ai.bionemo_client"] = fake


def test_dispatch_selfhost_not_gated_on_api_key(mod, monkeypatch):
    # No NVIDIA_API_KEY, but the client reports self_host (URL configured) and the
    # NIM is unreachable → we must DISPATCH (and get the self-host unreachable
    # reason), NOT short-circuit with a "key not set" stub.
    monkeypatch.delenv("NVIDIA_API_KEY", raising=False)
    _install_fake_bionemo(
        effective_mode="self_host",
        boltz2_return={"_stub": True, "reason": "self-host unreachable at http://nim:8000"},
    )
    try:
        res = mod._dispatch_bionemo("bionemo:boltz2", mod.STRUCTURE, {"sequence": "MKT"})
    finally:
        sys.modules.pop("galaxy.ai.bionemo_client", None)
    assert res["stub"] is True
    # Proof it went THROUGH dispatch (B5 labelling) rather than the deleted gate:
    assert "self-host unreachable" in res["stub_reason"]
    # And it's still a correctly-shaped structure stub (no fabricated numbers).
    assert res["plddt"] == [] and res["pae"] == [] and res["structureFileRef"] is None


def test_dispatch_stub_mode_uses_client_reason(mod):
    # Nothing configured → client effective mode is stub → surface its own reason.
    _install_fake_bionemo(effective_mode="stub", boltz2_return={})
    try:
        res = mod._dispatch_bionemo("bionemo:boltz2", mod.STRUCTURE, {"sequence": "MKT"})
    finally:
        sys.modules.pop("galaxy.ai.bionemo_client", None)
    assert res["stub"] is True
    assert "no backend configured" in res["stub_reason"]


# ── B2 regression: run registry is the shared cross-worker store ──────────────
def test_run_registry_uses_shared_store(mod):
    # A run written by _new_run/_finish_run must be readable via the same store
    # any worker resolves through get_run_state_store() (InMemory in this env).
    run_id = mod._new_run("bionemo:boltz2", mod.STRUCTURE)
    assert run_id.startswith("inf-")
    store = mod._store()
    assert store.get_run(run_id)["status"] == "running"
    mod._finish_run(run_id, {"plddt": [], "pae": [], "regions": [], "structureFileRef": None})
    out = mod.get_inference_result(run_id)
    assert out["status"] == "completed"
    assert out["evidenceClass"] == mod.STRUCTURE
    # Unknown run → 404 (HTTPException), not a silent empty.
    import pytest as _pytest
    with _pytest.raises(Exception):
        mod.get_inference_result("inf-does-not-exist")
