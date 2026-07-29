"""Guard: the canonical data-source registry must stay in sync with the real
federated fan-out. If someone adds a source to federated_query._FETCHERS without
declaring it in galaxy.ai.data_sources (or vice-versa), this fails — turning the
historical silent drift (pubchem single-source-only, omim advertised-but-unbacked)
into a hard CI failure. See docs/20260728_UNIFIED_DATA_SOURCE_REGISTRY.md.

The modules are loaded by file path and the federated_query module is registered
as ``galaxy.ai.federated_query`` in sys.modules, so ``registry_drift`` resolves it
WITHOUT importing Galaxy's heavy package __init__ (which would hang a unit run).
"""
import importlib.util
import os
import sys
import types

_AI_DIR = os.path.join(os.path.dirname(__file__), "..", "lib", "galaxy", "ai")


def _load(mod_name, filename):
    path = os.path.join(_AI_DIR, filename)
    spec = importlib.util.spec_from_file_location(mod_name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[mod_name] = mod
    spec.loader.exec_module(mod)
    return mod


def _registry_and_fq():
    # Stub the galaxy / galaxy.ai packages so the real fully-qualified name
    # resolves to our file-loaded module (no package __init__ side effects).
    fq = _load("federated_query", "federated_query.py")
    sys.modules.setdefault("galaxy", types.ModuleType("galaxy"))
    sys.modules.setdefault("galaxy.ai", types.ModuleType("galaxy.ai"))
    sys.modules["galaxy.ai.federated_query"] = fq
    ds = _load("data_sources", "data_sources.py")
    return ds, fq


def test_registry_federation_matches_fetchers():
    ds, _ = _registry_and_fq()
    drift = ds.registry_drift()
    assert drift.get("in_sync"), (
        "data-source registry drifted from federated_query._FETCHERS: "
        "declared_not_wired=%s wired_not_declared=%s"
        % (drift.get("declared_not_wired"), drift.get("wired_not_declared"))
    )


def test_pubchem_reaches_the_fanout():
    """PubChem must be routable from the federated fan-out, not single-source only."""
    _, fq = _registry_and_fq()
    assert "pubchem" in fq._FETCHERS
    assert "pubchem" in fq.ENTITY_SOURCES["compound"]


def test_mcp_enum_only_advertises_backed_sources():
    """Every id the registry marks mcp must have a handler; omim (unbacked) must not."""
    ds, _ = _registry_and_fq()
    mcp_ids = {s["id"] for s in ds.list_data_sources(surface="mcp")}
    assert "omim" not in mcp_ids, "omim has no handler — must not be MCP-advertised"
    for expected in ("pubchem", "bindingdb", "pharos", "pdbe"):
        assert expected in mcp_ids, "%s should be MCP-advertised (it has a handler)" % expected
