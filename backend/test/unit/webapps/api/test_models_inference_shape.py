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


def test_bionemo_catalog_only_owned_compute(mod):
    rows = {r["id"]: r for r in mod._bionemo_catalog()}
    # Boltz-2 runs on BioMate's OWN AWS Batch, so it is advertised with an honest
    # "aws_batch" origin regardless of the BioNeMo client mode (2026-11-12).
    assert "bionemo:boltz2" in rows
    assert rows["bionemo:boltz2"]["origin"] == "aws_batch"
    # Only models BioMate can run on its own compute are advertised: an owned AWS
    # Batch path or a configured self-host NIM. Pure NVIDIA-hosted models are hidden
    # until they have an owned path — never advertise the external hosted endpoint
    # (founder: "why are there still NVIDIA-hosted models", 2026-11-12).
    for r in mod._bionemo_catalog():
        assert r["origin"] in {"aws_batch", "self_host"}, r["origin"]
    # Evo2/OpenFold2 have no owned path yet, so with no self-host NIM configured
    # they are NOT advertised (they would otherwise be hosted_nvidia/unconfigured).
    assert all(rows.get(i, {}).get("origin") in (None, "self_host")
               for i in ("bionemo:evo2_7b", "bionemo:openfold2"))


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


# ── Model-tracks phase: pure shaping helpers (Train / Adapt / Optimise) ───────
# These lock the contract the Train/Adapt/Optimise track UIs bind to, and the
# math the Optimise proposal table depends on — all without a DB.
def test_fmt_num_and_ts(mod):
    assert mod._fmt_num(0.12345) == "0.123"
    assert mod._fmt_num(None) == "—"
    assert mod._fmt_num("not-a-number") == "—"
    # ISO string is truncated to the date; falsy/None → em-dash.
    assert mod._fmt_ts("2026-08-01T12:00:00") == "2026-08-01"
    assert mod._fmt_ts(None) == "—"
    assert mod._fmt_ts(0) == "—"  # unix-epoch-0 treated as unknown (falsy)


def test_confidence_from_ci_bands(mod):
    # Tight CI → high; medium width → medium; wide/None → low/medium fallback.
    assert mod._confidence_from_ci((0.10, 0.15)) == "high"   # width 0.05
    assert mod._confidence_from_ci((0.0, 0.25)) == "medium"  # width 0.25
    assert mod._confidence_from_ci((0.0, 1.0)) == "low"      # width 1.0
    assert mod._confidence_from_ci(None) == "medium"         # unknown → neutral


def test_resolve_score_list_shapes(mod):
    smiles = ["A", "B", "C"]
    # {objective: [per-compound]} → first objective's list, padded to len(smiles).
    assert mod._resolve_score_list({"obj": [0.5, 0.6]}, smiles) == [0.5, 0.6, None]
    # {smiles: score} → aligned by smiles.
    assert mod._resolve_score_list({"A": 1.0, "C": 3.0}, smiles) == [1.0, None, 3.0]
    # empty / non-dict → all-None of the right length (never fabricated).
    assert mod._resolve_score_list({}, smiles) == [None, None, None]
    assert mod._resolve_score_list(None, smiles) == [None, None, None]


def test_ci_at_shapes(mod):
    # dict keyed by smiles
    assert mod._ci_at({"X": (0.1, 0.2)}, "X", 0) == (0.1, 0.2)
    # dict with parallel lo/hi arrays
    assert mod._ci_at({"lo": [0.1], "hi": [0.2]}, "X", 0) == (0.1, 0.2)
    # list-of-pairs indexed positionally
    assert mod._ci_at([(0.1, 0.2)], "X", 0) == (0.1, 0.2)
    # absent → None
    assert mod._ci_at({}, "X", 5) is None


def test_job_status_map(mod):
    # Worker vocab → Train-track/dashboard vocab.
    assert mod._JOB_STATUS_MAP["succeeded"] == "completed"
    assert mod._JOB_STATUS_MAP["failed"] == "failed"
    assert mod._JOB_STATUS_MAP["cancelled"] == "failed"
    assert mod._JOB_STATUS_MAP["running"] == "running"
    assert mod._JOB_STATUS_MAP["queued"] == "queued"


# ── Adapt toggle: persisted on/off override round-trips (no DB, temp JSONL) ────
def test_adapt_toggle_roundtrip(mod, tmp_path, monkeypatch):
    # Point the disabled-set sidecar at a temp file.
    disabled_path = str(tmp_path / "disabled_pairs.jsonl")
    monkeypatch.setattr(mod, "_disabled_pairs_path", lambda: disabled_path)
    monkeypatch.setattr(mod, "_read_all_dpo_pairs", lambda: [
        {"meta": {"row_id": key, "user_id": "owner", "org_id": "project"}} for key in ("p1", "p2")
    ])

    assert mod._load_disabled_pairs() == set()  # nothing disabled initially
    # Flip p1 on→off, then off→on.
    assert mod.toggle_adapt_pair("p1", None, owner_id="owner") == {"id": "p1", "on": False}
    assert mod._load_disabled_pairs() == {"p1"}
    assert mod.toggle_adapt_pair("p1", None, owner_id="owner") == {"id": "p1", "on": True}
    assert mod._load_disabled_pairs() == set()
    # Explicit target (the TogglePairRequest carries on=…).
    req_off = mod.TogglePairRequest(on=False)
    assert mod.toggle_adapt_pair("p2", req_off, owner_id="owner") == {"id": "p2", "on": False}
    assert "p2" in mod._load_disabled_pairs()
    req_on = mod.TogglePairRequest(on=True)
    assert mod.toggle_adapt_pair("p2", req_on, owner_id="owner") == {"id": "p2", "on": True}
    assert "p2" not in mod._load_disabled_pairs()


def test_toggle_requires_pair_id(mod):
    import pytest as _pytest
    with _pytest.raises(Exception):
        mod.toggle_adapt_pair("", None)


# ── B2 regression: run registry is the shared cross-worker store ──────────────
def test_run_registry_uses_shared_store(mod):
    # A run written by _new_run/_finish_run must be readable via the same store
    # any worker resolves through get_run_state_store() (InMemory in this env).
    run_id = mod._new_run("bionemo:boltz2", mod.STRUCTURE, "owner")
    assert run_id.startswith("inf-")
    store = mod._store()
    assert store.get_run(run_id)["status"] == "running"
    mod._finish_run(run_id, {"plddt": [], "pae": [], "regions": [], "structureFileRef": None})
    out = mod.get_inference_result(run_id, owner_id="owner")
    assert out["status"] == "completed"
    assert out["evidenceClass"] == mod.STRUCTURE
    # Unknown run → 404 (HTTPException), not a silent empty.
    import pytest as _pytest
    with _pytest.raises(Exception):
        mod.get_inference_result("inf-does-not-exist")


# Owner boundaries are tested on synthetic stores only.
def test_missing_trusted_owner_is_rejected(mod):
    with pytest.raises(Exception) as error:
        mod.list_models(owner_id=None)
    assert error.value.status_code == 403


def test_private_catalog_matches_durable_owner_binding(mod, tmp_path, monkeypatch):
    import sqlite3
    registry = tmp_path / "campaigns_registry.db"
    with sqlite3.connect(registry) as db:
        db.execute("CREATE TABLE campaigns(campaign_id TEXT, user_id TEXT)")
        db.executemany("INSERT INTO campaigns VALUES (?,?)", [("own", "owner"), ("foreign", "stranger"), ("unbound", "")])
    campaigns = tmp_path / "campaigns"
    campaigns.mkdir()
    for key in ("own", "foreign", "unbound"):
        with sqlite3.connect(campaigns / (key + ".db")) as db:
            db.execute("CREATE TABLE custom_model_registrations(campaign_id TEXT,model_name TEXT,mode TEXT,weight REAL,higher_is_better INTEGER,enabled INTEGER,registered_at TEXT)")
            db.execute("INSERT INTO custom_model_registrations VALUES (?,?, 'python',1,1,1,'2026-11-07')", (key, key + "-private-model"))
    monkeypatch.setenv("BIOMATE_CAMPAIGN_REGISTRY_DB", str(registry))
    monkeypatch.setattr(mod, "_campaign_db_dir", lambda: str(campaigns))
    assert [row['campaign_id'] for row in mod._iter_custom_registrations('owner')] == ['own']
    assert mod._iter_custom_registrations(None) == []
    assert mod._resolve_campaign_ids('foreign', 'owner') == []
    assert mod._resolve_campaign_ids('missing', 'owner') == []
    monkeypatch.setattr(mod, '_bionemo_catalog', lambda: [{'id':'bionemo:public-pretrained'}])
    ids = {row['id'] for row in mod.list_models(owner_id='owner')}
    assert 'bionemo:public-pretrained' in ids
    assert not any('foreign' in value or 'unbound' in value for value in ids)
    with pytest.raises(Exception) as error:
        mod.get_model('custom:foreign:foreign-private-model', owner_id='owner')
    assert error.value.status_code == 404


def test_resolve_campaign_ids_includes_owned_campaign_without_scorer(mod, tmp_path, monkeypatch):
    """Regression: a DMTA campaign the owner owns but that has NO registered
    custom scorer (a peptide/biologic loop that only ran generate-library +
    ingest + propose) must still resolve, so the Optimise track renders its
    proposal rounds instead of its empty state. Previously _resolve_campaign_ids
    read only campaigns carrying a registration, so such a campaign was invisible
    and /api/model-tracks/optimise returned {active: false} despite a real round."""
    import sqlite3
    registry = tmp_path / "campaigns_registry.db"
    with sqlite3.connect(registry) as db:
        db.execute("CREATE TABLE campaigns(campaign_id TEXT, user_id TEXT)")
        db.executemany("INSERT INTO campaigns VALUES (?,?)",
                       [("pep", "owner"), ("foreign", "stranger")])
    campaigns = tmp_path / "campaigns"
    campaigns.mkdir()  # no custom_model_registrations db exists for 'pep'
    monkeypatch.setenv("BIOMATE_CAMPAIGN_REGISTRY_DB", str(registry))
    monkeypatch.setattr(mod, "_campaign_db_dir", lambda: str(campaigns))

    assert mod._iter_custom_registrations('owner') == []          # not visible as a scorer
    assert mod._resolve_campaign_ids('pep', 'owner') == ['pep']   # but IS resolvable
    assert mod._resolve_campaign_ids(None, 'owner') == ['pep']
    assert mod._resolve_campaign_ids('foreign', 'owner') == []    # unowned still excluded


def test_customer_edit_reads_and_toggles_are_owner_bound(mod, tmp_path, monkeypatch):
    rows = [
        {'chosen':'mine', 'rejected':'my draft', 'meta':{'user_id':'owner','org_id':'project','row_id':'mine'}},
        {'chosen':'private stranger text','meta':{'user_id':'stranger','org_id':'project','row_id':'foreign'}},
        {'chosen':'unbound legacy text','meta':{'org_id':'project','row_id':'unbound'}},
    ]
    monkeypatch.setattr(mod, '_read_all_dpo_pairs', lambda: rows)
    monkeypatch.setattr(mod, '_disabled_pairs_path', lambda: str(tmp_path / 'disabled.jsonl'))
    assert [row['chosen'] for row in mod._read_dpo_pairs('project','owner')] == ['mine']
    assert mod._read_dpo_pairs('project',None) == []
    assert mod._read_dpo_pairs('other','owner') == []
    with pytest.raises(Exception) as error:
        mod.toggle_adapt_pair('foreign', None, owner_id='owner')
    assert error.value.status_code == 403
    assert not (tmp_path / 'disabled.jsonl').exists()
    with pytest.raises(Exception) as error:
        mod.retrain_adapt('other-project', owner_id='owner')
    assert error.value.status_code == 409


def test_inference_results_do_not_cross_owners_or_accept_legacy_unowned(mod):
    for actor in ('owner', None):
        run_id = mod._new_run('bionemo:boltz2', mod.STRUCTURE, actor)
        with pytest.raises(Exception) as error:
            mod.get_inference_result(run_id, owner_id='stranger')
        assert error.value.status_code == 403


def test_models_routes_require_admin_bridge_before_trusting_owner_headers():
    import ast
    tree = ast.parse(open(_MODULE_PATH).read())
    routes = [node for node in ast.walk(tree) if isinstance(node, ast.Call)
              and isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name)
              and node.func.value.id == 'router' and node.func.attr in ('get','post')]
    assert routes
    assert all(any(kw.arg == 'require_admin' and isinstance(kw.value, ast.Constant) and kw.value.value is True for kw in node.keywords) for node in routes)


def test_unavailable_pretrained_inference_does_not_become_completed_science(mod, monkeypatch):
    # openfold2 is a genuinely NIM-served model (no aws_batch override), so it
    # exercises the NIM dispatch path. (boltz2 now folds on AWS Batch — see below.)
    monkeypatch.setattr(mod, '_find_catalog_row', lambda model_id, owner_id=None: {'id':model_id})
    monkeypatch.setattr(mod, '_dispatch_bionemo', lambda *args: {'stub':True,'stub_reason':'Model backend not configured'})
    result = mod.infer('bionemo:openfold2', mod.InferRequest(inputs={'sequence':'AA'}), owner_id='owner')
    record = mod.get_inference_result(result['run_id'], owner_id='owner')
    assert record['status'] == 'failed'
    assert 'not configured' in record['error']


def test_aws_batch_model_is_not_served_by_nim_inference(mod, monkeypatch):
    """Boltz-2 (origin_override aws_batch) folds on BioMate's own AWS Batch as a
    tracked structure-fold workflow with the QC auto-loop — never the one-shot
    BioNeMo NIM (the source of the CUDA "illegal memory access" failures). infer()
    refuses it (409) BEFORE any dispatch or run record, and the catalog never shows
    a stale NIM inference failure against it."""
    import pytest
    assert mod._is_aws_batch_model('bionemo:boltz2') is True
    assert mod._is_aws_batch_model('bionemo:openfold2') is False

    monkeypatch.setattr(mod, '_find_catalog_row', lambda model_id, owner_id=None: {'id': model_id, 'name': 'Boltz-2'})
    # If the NIM were ever reached it would blow up — proving we never dispatch.
    def _boom(*a, **k):  # pragma: no cover - must not be called
        raise AssertionError('aws_batch model must not be dispatched to the NIM')
    monkeypatch.setattr(mod, '_dispatch_bionemo', _boom)
    with pytest.raises(Exception) as err:
        mod.infer('bionemo:boltz2', mod.InferRequest(inputs={'sequence': 'AA'}), owner_id='owner')
    assert err.value.status_code == 409

    # A stale NIM inference failure must not be surfaced against an aws_batch model.
    rows = mod._with_last_inference([{'id': 'bionemo:boltz2'}], 'owner')
    assert 'lastInference' not in rows[0]


def test_corrupt_ownership_store_is_unavailable_not_empty_success(mod, tmp_path, monkeypatch):
    path = tmp_path / 'broken.db'
    path.write_text('not sqlite')
    monkeypatch.setenv('BIOMATE_CAMPAIGN_REGISTRY_DB', str(path))
    with pytest.raises(Exception) as error:
        mod._owned_campaign_ids('owner')
    assert error.value.status_code == 503


def test_active_version_uses_registry_record_not_inferred_version_one(mod, tmp_path, monkeypatch):
    import sqlite3
    db_dir = tmp_path / 'campaigns'
    db_dir.mkdir()
    monkeypatch.setattr(mod, '_campaign_db_dir', lambda: str(db_dir))
    with sqlite3.connect(db_dir / 'own.db') as db:
        db.execute('CREATE TABLE custom_model_versions(campaign_id TEXT,model_name TEXT,version INTEGER,status TEXT)')
        db.execute("INSERT INTO custom_model_versions VALUES ('own','classifier',7,'active')")
    assert mod._recorded_active_version('own','classifier') == '7'
    assert mod._recorded_active_version('own','missing') == 'Not recorded'


def test_plddt_from_cif_wrapped_records_real_boltz2(mod):
    # Real Boltz-2 response (health.api.nvidia.com, 2026-11-11) for a 33-residue protein.
    # Most _atom_site records wrap onto a second line (B-factor + model number on the next
    # line); the old line-by-line parser returned ONE value for this file.
    path = os.path.join(os.path.dirname(__file__), "fixtures", "boltz2_wrapped_atom_site.cif")
    with open(path) as f:
        cif = f.read()
    plddt = mod._plddt_from_cif(cif)
    assert len(plddt) == 33
    assert all(0.0 <= v <= 1.0 for v in plddt)
    assert abs(plddt[0] - 0.82203287) < 1e-6
