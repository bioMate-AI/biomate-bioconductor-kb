"""Unit tests for galaxy.ai.scope_guard (on-prem deployment-scope enforcement).

Pure-stdlib; runnable either under pytest or directly:  python3 test_scope_guard.py
Proves: fail-safe OFF without a manifest; in/out-of-scope by path (exact + suffix)
and by name; tool/instrument allow-lists; raw-upload fail-closed (+ opt-in);
result filtering; and that a missing/garbage manifest fails safe (enforcement OFF).
"""

import json
import os
import tempfile

import scope_guard as sg  # colocated module


def _reset():
    """Clear the env + the module's manifest cache between cases."""
    for k in ("BIOMATE_SCOPE_MANIFEST", "BIOMATE_SCOPE_ALLOW_UPLOADS"):
        os.environ.pop(k, None)
    sg._cache.update({"path": None, "mtime": None, "data": None})


def _write_manifest(tmp, obj):
    p = os.path.join(tmp, "manifest.json")
    with open(p, "w", encoding="utf-8") as fh:
        json.dump(obj, fh)
    os.environ["BIOMATE_SCOPE_MANIFEST"] = p
    sg._cache.update({"path": None, "mtime": None, "data": None})  # force re-read
    return p


MANIFEST = {
    "workflows": {
        "by_nextflow_path": [
            "nextflow_nfcore/subworkflows/transcriptomics/rnaseq/main.nf",
            "biomni_workflows/nfcore/sarek/main.nf",
        ],
        "by_name": ["nf-core/rnaseq", "nf-core/sarek"],
    },
    "tools_allowlist": ["fastqc", "star", "salmon"],
    "instruments": ["illumina_novaseq"],
}


def test_enforcement_off_without_manifest():
    _reset()
    assert sg.enforcement_enabled() is False
    assert sg.is_workflow_in_scope(nextflow_path="anything/at/all/main.nf") is True
    sg.assert_in_scope_or_raise(nextflow_path="anything/main.nf")  # no raise
    sg.assert_in_scope_or_raise(file_content="process x {}")        # no raise (off)


def test_enforcement_on_in_scope_by_path():
    _reset()
    with tempfile.TemporaryDirectory() as tmp:
        _write_manifest(tmp, MANIFEST)
        assert sg.enforcement_enabled() is True
        # exact
        assert sg.is_workflow_in_scope(
            nextflow_path="nextflow_nfcore/subworkflows/transcriptomics/rnaseq/main.nf") is True
        # absolute container path → suffix match
        assert sg.is_workflow_in_scope(
            nextflow_path="/app/lib/galaxy/webapps/galaxy/api/nextflow_nfcore/"
                          "subworkflows/transcriptomics/rnaseq/main.nf") is True
        # trailing-component suffix
        assert sg.is_workflow_in_scope(nextflow_path="rnaseq/main.nf") is True
        sg.assert_in_scope_or_raise(nextflow_path="rnaseq/main.nf")  # no raise


def test_out_of_scope_path_rejected():
    _reset()
    with tempfile.TemporaryDirectory() as tmp:
        _write_manifest(tmp, MANIFEST)
        assert sg.is_workflow_in_scope(
            nextflow_path="biomni_workflows/nfcore/cryoem/main.nf") is False
        raised = False
        try:
            sg.assert_in_scope_or_raise(nextflow_path="biomni_workflows/nfcore/cryoem/main.nf")
        except sg.ScopeError as e:
            raised = True
            assert e.status_code == 409
            assert e.payload["error"] == "OUT_OF_SCOPE"
        assert raised, "expected ScopeError for out-of-scope path"


def test_in_scope_by_name():
    _reset()
    with tempfile.TemporaryDirectory() as tmp:
        _write_manifest(tmp, MANIFEST)
        assert sg.is_workflow_in_scope(name="nf-core/rnaseq") is True
        assert sg.is_workflow_in_scope(name="NF-CORE/RNASEQ") is True  # case-insensitive
        assert sg.is_workflow_in_scope(name="nf-core/cryoem") is False


def test_tool_and_instrument_allowlist():
    _reset()
    with tempfile.TemporaryDirectory() as tmp:
        _write_manifest(tmp, MANIFEST)
        assert sg.is_tool_in_scope("STAR") is True
        assert sg.is_tool_in_scope("cellranger") is False
        assert sg.is_instrument_in_scope("illumina_novaseq") is True
        assert sg.is_instrument_in_scope("pacbio_revio") is False


def test_raw_upload_fail_closed_then_opt_in():
    _reset()
    with tempfile.TemporaryDirectory() as tmp:
        _write_manifest(tmp, MANIFEST)
        # default: uploads rejected even though a path is given
        raised = False
        try:
            sg.assert_in_scope_or_raise(
                nextflow_path="rnaseq/main.nf", file_content="process x {}")
        except sg.ScopeError:
            raised = True
        assert raised, "raw upload must be rejected by default on a scoped deployment"
        # opt-in: uploads allowed, but still must be in scope by path
        os.environ["BIOMATE_SCOPE_ALLOW_UPLOADS"] = "1"
        sg.assert_in_scope_or_raise(nextflow_path="rnaseq/main.nf", file_content="process x {}")
        # opt-in + out-of-scope path → still rejected
        raised2 = False
        try:
            sg.assert_in_scope_or_raise(
                nextflow_path="cryoem/main.nf", file_content="process x {}")
        except sg.ScopeError:
            raised2 = True
        assert raised2, "opt-in uploads still must be in scope"


def test_filter_workflows():
    _reset()
    with tempfile.TemporaryDirectory() as tmp:
        _write_manifest(tmp, MANIFEST)
        rows = [
            {"name": "nf-core/rnaseq", "nextflow_path": "rnaseq/main.nf"},
            {"name": "nf-core/cryoem", "nextflow_path": "cryoem/main.nf"},
            {"name": "nf-core/sarek", "nextflow_path": "biomni_workflows/nfcore/sarek/main.nf"},
        ]
        kept = sg.filter_workflows(rows)
        names = {r["name"] for r in kept}
        assert names == {"nf-core/rnaseq", "nf-core/sarek"}, names


def test_bad_manifest_fails_safe_off():
    _reset()
    with tempfile.TemporaryDirectory() as tmp:
        p = os.path.join(tmp, "manifest.json")
        with open(p, "w", encoding="utf-8") as fh:
            fh.write("{ this is not valid json ")
        os.environ["BIOMATE_SCOPE_MANIFEST"] = p
        sg._cache.update({"path": None, "mtime": None, "data": None})
        assert sg.enforcement_enabled() is False          # fail-safe OFF
        assert sg.is_workflow_in_scope(nextflow_path="x/main.nf") is True
    # nonexistent path → also OFF
    _reset()
    os.environ["BIOMATE_SCOPE_MANIFEST"] = "/no/such/manifest.json"
    assert sg.enforcement_enabled() is False


if __name__ == "__main__":
    import sys
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    failed = 0
    for fn in fns:
        try:
            fn()
            print(f"PASS {fn.__name__}")
        except Exception as e:  # noqa: BLE001
            failed += 1
            print(f"FAIL {fn.__name__}: {e!r}")
        finally:
            _reset()
    print(f"\n{len(fns) - failed}/{len(fns)} passed")
    sys.exit(1 if failed else 0)
