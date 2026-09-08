"""
Unit tests for the BioNeMoClient mode switch (self_host | hosted_api | stub).

Covered:
- Mode auto-detection from env (BIONEMO_SELF_HOST_URL / NVIDIA_API_KEY / none).
- Explicit BIONEMO_MODE override, incl. an invalid value falling back to auto.
- stub mode: no network is touched and methods return the correct empty-but-
  typed shapes ('' for esmfold, [] for genmol/molmim, stub dict for boltz2/evo2)
  with an honest reason — never a fabricated result.
- self_host mode: calls POST to <BIONEMO_SELF_HOST_URL>/<per-model-path> and the
  documented return shapes are preserved. A FAKE HTTP layer is injected — no
  real network call is made.
- self_host unreachable: a RequestException degrades to the honest stub shape.
- health(): reports mode/effective_mode and, in self_host, per-model probes.

Run:
  python -m pytest backend/lib/galaxy/ai/tests/test_bionemo_mode_switch.py
"""
import os
import sys
import json
import importlib.util

import pytest

# ---------------------------------------------------------------------------
# Import bionemo_client in isolation (no full galaxy package import needed).
# ---------------------------------------------------------------------------
_HERE = os.path.dirname(__file__)
_CLIENT_PATH = os.path.join(_HERE, "..", "bionemo_client.py")


def _load_module():
    spec = importlib.util.spec_from_file_location("bionemo_client_under_test", _CLIENT_PATH)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


bnm = _load_module()


# ---------------------------------------------------------------------------
# Fake HTTP layer — records requests, returns canned responses. No network.
# ---------------------------------------------------------------------------
class _FakeResponse:
    def __init__(self, status_code=200, json_body=None, headers=None, text=""):
        self.status_code = status_code
        self._json = json_body if json_body is not None else {}
        self.headers = headers or {}
        self.text = text

    def json(self):
        return self._json


class _FakeSession:
    """Stands in for requests.Session. Routes by URL suffix."""

    def __init__(self, routes=None, raise_on=None):
        # routes: dict {url_suffix: _FakeResponse}
        self.routes = routes or {}
        self.raise_on = raise_on  # substring → raise RequestException
        self.headers = {}
        self.calls = []  # list of (method, url, json_payload)

    def _match(self, url):
        for suffix, resp in self.routes.items():
            if url.endswith(suffix) or suffix in url:
                return resp
        return _FakeResponse(status_code=404, text="no route")

    def post(self, url, json=None, headers=None, timeout=None):
        self.calls.append(("POST", url, json))
        if self.raise_on and self.raise_on in url:
            import requests as _rq
            raise _rq.RequestException(f"fake unreachable: {url}")
        return self._match(url)

    def get(self, url, timeout=None):
        self.calls.append(("GET", url, None))
        if self.raise_on and self.raise_on in url:
            import requests as _rq
            raise _rq.RequestException(f"fake unreachable: {url}")
        return self._match(url)


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    """Start every test from a clean BioNeMo env."""
    for k in ("BIONEMO_MODE", "BIONEMO_SELF_HOST_URL", "NVIDIA_API_KEY"):
        monkeypatch.delenv(k, raising=False)
    # Purge any per-model path overrides.
    for k in list(os.environ):
        if k.startswith("BIONEMO_SELF_HOST_PATH_"):
            monkeypatch.delenv(k, raising=False)
    yield


def _client_with_session(session, **kwargs):
    c = bnm.BioNeMoClient(**kwargs)
    c._session = session
    return c


# ===========================================================================
# Mode resolution
# ===========================================================================
def test_mode_auto_stub_when_unset():
    c = bnm.BioNeMoClient()
    assert c.mode == bnm.MODE_STUB


def test_mode_auto_self_host_when_url_set(monkeypatch):
    monkeypatch.setenv("BIONEMO_SELF_HOST_URL", "http://nim.internal:8000")
    c = bnm.BioNeMoClient()
    assert c.mode == bnm.MODE_SELF_HOST
    assert c.self_host_url == "http://nim.internal:8000"


def test_mode_auto_hosted_when_only_key_set(monkeypatch):
    monkeypatch.setenv("NVIDIA_API_KEY", "nvapi-fake")
    c = bnm.BioNeMoClient()
    assert c.mode == bnm.MODE_HOSTED_API


def test_explicit_mode_wins(monkeypatch):
    monkeypatch.setenv("BIONEMO_SELF_HOST_URL", "http://nim.internal:8000")
    monkeypatch.setenv("BIONEMO_MODE", "stub")
    c = bnm.BioNeMoClient()
    assert c.mode == bnm.MODE_STUB


def test_invalid_mode_falls_back_to_auto(monkeypatch):
    monkeypatch.setenv("NVIDIA_API_KEY", "nvapi-fake")
    monkeypatch.setenv("BIONEMO_MODE", "banana")
    c = bnm.BioNeMoClient()
    assert c.mode == bnm.MODE_HOSTED_API  # auto-detected, not 'banana'


def test_constructor_never_raises_without_key_or_url():
    # The old constructor raised ValueError when NVIDIA_API_KEY was unset.
    # The new one must NOT — stub fallback depends on it.
    c = bnm.BioNeMoClient()
    assert c.mode == bnm.MODE_STUB


# ===========================================================================
# stub mode — no network, honest empty shapes
# ===========================================================================
def test_stub_esmfold_returns_empty_string_no_network():
    session = _FakeSession()
    c = _client_with_session(session, mode="stub")
    assert c.esmfold("MKTAYIAK") == ""
    assert session.calls == []  # no network touched


def test_stub_genmol_returns_empty_list():
    session = _FakeSession()
    c = _client_with_session(session, mode="stub")
    assert c.genmol("c1ccccc1", num_molecules=5) == []
    assert session.calls == []


def test_stub_molmim_returns_empty_list():
    session = _FakeSession()
    c = _client_with_session(session, mode="stub")
    assert c.molmim("c1ccccc1") == []
    assert session.calls == []


def test_stub_boltz2_returns_stub_dict_with_reason():
    session = _FakeSession()
    c = _client_with_session(session, mode="stub")
    out = c.boltz2("MKTAYIAK")
    assert isinstance(out, dict)
    assert out.get("_stub") is True
    assert "reason" in out and out["reason"]
    assert session.calls == []


def test_stub_evo2_returns_stub_dict():
    session = _FakeSession()
    c = _client_with_session(session, mode="stub")
    out = c.evo2_generate("ACGTACGT", num_tokens=10, model="evo2_7b")
    assert out.get("_stub") is True
    assert out.get("sequence", "") == ""  # .get default proves no fabricated seq


def test_hosted_mode_without_key_degrades_to_stub():
    # mode explicitly hosted_api but no key → effective stub, no network.
    session = _FakeSession()
    c = _client_with_session(session, mode="hosted_api", api_key="")
    assert c._effective_mode() == bnm.MODE_STUB
    assert c.genmol("") == []
    assert session.calls == []


# ===========================================================================
# self_host mode — dispatch to <URL>/<path>, shapes preserved
# ===========================================================================
def test_self_host_genmol_posts_to_url_and_returns_molecules():
    mols = [{"smiles": "CCO", "score": 0.9}, {"smiles": "CCN", "score": 0.8}]
    session = _FakeSession(routes={
        "/biology/nvidia/genmol/generate": _FakeResponse(200, {"molecules": mols}),
    })
    c = _client_with_session(
        session, mode="self_host", self_host_url="http://nim.internal:8000")
    out = c.genmol("c1ccccc1", num_molecules=2)
    assert out == mols
    # Verify it actually hit the self-host URL + per-model path.
    assert len(session.calls) == 1
    method, url, payload = session.calls[0]
    assert method == "POST"
    assert url == "http://nim.internal:8000/biology/nvidia/genmol/generate"
    assert payload["smi"] == "c1ccccc1"
    assert payload["num_molecules"] == 2


def test_self_host_molmim_parses_json_string_shape():
    # MolMIM historically returns molecules as a JSON *string*; preserve that.
    inner = json.dumps([{"sample": "CCO", "score": 0.7}])
    session = _FakeSession(routes={
        "/biology/nvidia/molmim/generate": _FakeResponse(200, {"molecules": inner}),
    })
    c = _client_with_session(
        session, mode="self_host", self_host_url="http://nim.internal:8000")
    out = c.molmim("c1ccccc1")
    assert out == [{"sample": "CCO", "score": 0.7}]


def test_self_host_esmfold_returns_pdb_string():
    session = _FakeSession(routes={
        "/v1/biology/nvidia/esmfold": _FakeResponse(200, {"pdbs": ["PDBDATA"]}),
    })
    c = _client_with_session(
        session, mode="self_host", self_host_url="http://nim.internal:8000")
    assert c.esmfold("MKTAYIAK") == "PDBDATA"
    _, url, _ = session.calls[0]
    assert url == "http://nim.internal:8000/v1/biology/nvidia/esmfold"


def test_self_host_boltz2_passes_dict_through():
    raw = {"structures": ["CIFDATA"], "confidence_scores": [0.88]}
    session = _FakeSession(routes={
        "/biology/mit/boltz2/predict": _FakeResponse(200, raw),
    })
    c = _client_with_session(
        session, mode="self_host", self_host_url="http://nim.internal:8000")
    out = c.boltz2("MKTAYIAK")
    assert out == raw
    assert "_stub" not in out


def test_self_host_evo2_dispatches_by_model_name():
    session = _FakeSession(routes={
        "/biology/arc/evo2-40b/generate": _FakeResponse(200, {"sequence": "ACGT"}),
    })
    c = _client_with_session(
        session, mode="self_host", self_host_url="http://nim.internal:8000")
    out = c.evo2_generate("ACGT", num_tokens=4, model="evo2_40b")
    assert out["sequence"] == "ACGT"
    _, url, _ = session.calls[0]
    assert url.endswith("/biology/arc/evo2-40b/generate")


def test_self_host_path_env_override(monkeypatch):
    monkeypatch.setenv("BIONEMO_SELF_HOST_PATH_GENMOL", "/custom/genmol/route")
    session = _FakeSession(routes={
        "/custom/genmol/route": _FakeResponse(200, {"molecules": [{"smiles": "CCO"}]}),
    })
    c = _client_with_session(
        session, mode="self_host", self_host_url="http://nim.internal:8000")
    out = c.genmol("")
    assert out == [{"smiles": "CCO"}]
    _, url, _ = session.calls[0]
    assert url == "http://nim.internal:8000/custom/genmol/route"


def test_self_host_unreachable_degrades_to_stub_shape():
    session = _FakeSession(raise_on="genmol")  # POST raises RequestException
    c = _client_with_session(
        session, mode="self_host", self_host_url="http://nim.internal:8000")
    # genmol returns [] (never fabricated) on an unreachable backend.
    assert c.genmol("c1ccccc1") == []
    # boltz2 returns a stub dict, not a fabricated structure.
    session2 = _FakeSession(raise_on="boltz2")
    c2 = _client_with_session(
        session2, mode="self_host", self_host_url="http://nim.internal:8000")
    out = c2.boltz2("MKTAYIAK")
    assert out.get("_stub") is True
    assert "unreachable" in out.get("reason", "")


def test_self_host_202_polls_task_url():
    calls = {"n": 0}

    class _PollSession(_FakeSession):
        def post(self, url, json=None, headers=None, timeout=None):
            self.calls.append(("POST", url, json))
            return _FakeResponse(202, headers={"location": "http://nim.internal:8000/v1/tasks/abc"})

        def get(self, url, timeout=None):
            self.calls.append(("GET", url, None))
            calls["n"] += 1
            if calls["n"] < 2:
                return _FakeResponse(202)
            return _FakeResponse(200, {"molecules": [{"smiles": "CCO"}]})

    session = _PollSession()
    c = _client_with_session(
        session, mode="self_host", self_host_url="http://nim.internal:8000")
    c.poll_interval = 0  # don't actually sleep
    out = c.genmol("")
    assert out == [{"smiles": "CCO"}]
    assert any(m == "GET" for m, _, _ in session.calls)


# ===========================================================================
# health()
# ===========================================================================
def test_health_stub_reports_unreachable_no_network():
    session = _FakeSession()
    c = _client_with_session(session, mode="stub")
    h = c.health()
    assert h["mode"] == "stub"
    assert h["effective_mode"] == "stub"
    assert h["reachable"] is False
    assert "reason" in h
    assert session.calls == []


def test_health_self_host_probes_models():
    session = _FakeSession(routes={
        "/v1/health/ready": _FakeResponse(200, {}),
        "/biology/mit/boltz2/predict": _FakeResponse(405, {}),   # route exists
        "/biology/nvidia/genmol/generate": _FakeResponse(422, {}),  # route exists
    })
    c = _client_with_session(
        session, mode="self_host", self_host_url="http://nim.internal:8000")
    h = c.health(models=["boltz2", "genmol"])
    assert h["mode"] == "self_host"
    assert h["reachable"] is True
    assert h["models"]["boltz2"]["reachable"] is True
    assert h["models"]["genmol"]["reachable"] is True


def test_health_self_host_gateway_down():
    session = _FakeSession(raise_on="/v1/health/ready")
    c = _client_with_session(
        session, mode="self_host", self_host_url="http://nim.internal:8000")
    h = c.health(models=["boltz2"])
    assert h["reachable"] is False
    assert "reason" in h


def test_health_no_probe_is_config_only():
    session = _FakeSession()
    c = _client_with_session(
        session, mode="self_host", self_host_url="http://nim.internal:8000")
    h = c.health(probe=False)
    assert h["mode"] == "self_host"
    assert h["self_host_url"] == "http://nim.internal:8000"
    assert session.calls == []  # no probe → no network
