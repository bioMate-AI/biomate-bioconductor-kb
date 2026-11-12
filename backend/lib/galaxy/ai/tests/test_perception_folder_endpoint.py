"""
Endpoint-level test for POST /api/perception/folder_profile and the folderContext plumbing of
/api/perception/profile + /rows (backend/lib/galaxy/webapps/galaxy/api/perception.py).

The real perception module is loaded by file path with the Galaxy web packages stubbed (their
__init__ needs beaker / SQLAlchemy, which a laptop lacks); the handlers then run for real
against local files: a gzipped 10x matrix whose head is decompressed from a partial read, the
FASTQ pairing, and the 10x TSV header decision.

Run standalone:
    cd backend && python3.9 lib/galaxy/ai/tests/test_perception_folder_endpoint.py
"""
from __future__ import annotations

import gzip
import importlib.util
import os
import sys
import tempfile
import types

_HERE = os.path.dirname(os.path.abspath(__file__))
_AI = os.path.abspath(os.path.join(_HERE, ".."))
_API = os.path.abspath(os.path.join(_HERE, "..", "..", "webapps", "galaxy", "api", "perception.py"))


def _load():
    class Router:
        def __init__(self, **_kw):
            pass

        def post(self, *_a, **_kw):
            return lambda fn: fn

        get = post

    for name in ("galaxy", "galaxy.webapps", "galaxy.webapps.galaxy"):
        sys.modules.setdefault(name, types.ModuleType(name))
    api = types.ModuleType("galaxy.webapps.galaxy.api")
    api.Router = Router  # type: ignore[attr-defined]
    sys.modules["galaxy.webapps.galaxy.api"] = api
    ai = types.ModuleType("galaxy.ai")
    ai.__path__ = [_AI]  # type: ignore[attr-defined]  — submodules load from the real files
    sys.modules["galaxy.ai"] = ai
    sys.modules["galaxy"].__path__ = []  # type: ignore[attr-defined]
    spec = importlib.util.spec_from_file_location("_perception_under_test", _API)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["_perception_under_test"] = mod
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


P = _load()


def _w(d, name, data):
    path = os.path.join(d, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    return path


def test_folder_profile_endpoint(d):
    # A gzipped 10x matrix larger than the 64 KB head: dims still come from the partial read.
    body = "%%MatrixMarket matrix coordinate integer general\n% big\n33538 5 200000\n" + "".join(
        f"{i % 33538 + 1} {i % 5 + 1} {i % 7 + 1}\n" for i in range(200000))
    mtx = _w(d, "tenx/matrix.mtx.gz", gzip.compress(body.encode()))
    assert os.path.getsize(mtx) > P._HEAD_BYTES
    bc = _w(d, "tenx/barcodes.tsv.gz", gzip.compress(b"AAAC-1\nAAAG-1\n"))
    ft = _w(d, "tenx/features.tsv.gz", gzip.compress(b"ENSG1\tA\tGene Expression\n"))
    req = P.FolderProfileRequest(path="tenx", files=[
        {"name": "tenx/matrix.mtx.gz", "datasetRef": mtx},
        {"name": "tenx/barcodes.tsv.gz", "datasetRef": bc},
        {"name": "tenx/features.tsv.gz", "datasetRef": ft},
    ])
    out = P.perception_folder_profile(req)
    assert out["kind"] == "tenx_matrix", out
    s = out["tenx"]["sets"][0]
    assert (s["genes"], s["cells"], s["nnz"]) == (33538, 5, 200000), s

    names = ["pairs/S1_R1.fastq.gz", "pairs/S1_R2.fastq.gz", "pairs/S2_R1.fastq.gz"]
    out = P.perception_folder_profile(P.FolderProfileRequest(path="pairs", files=[{"name": n, "datasetRef": None} for n in names]))
    assert out["kind"] == "fastq_set" and out["fastq"]["pairs"] == 1 and out["fastq"]["orphans"] == ["pairs/S2_R1.fastq.gz"], out
    assert len(out["samplesheet"]["rows"]) == 2
    print("PASS test_folder_profile_endpoint")


def test_profile_and_rows_take_folder_context(d):
    fq = _w(d, "S1_R1.fastq", b"@a/1\nACGT\n+\nIIII\n")
    ctx = {"name": "pairs/S1_R1.fastq", "siblings": ["pairs/S1_R2.fastq"]}
    prof = P.perception_profile(P.PerceptionProfileRequest(datasetRef=fq, name="pairs/S1_R1.fastq", folderContext=ctx))
    assert "fastq_paired_mate" in [f["code"] for f in prof["findings"]], prof["findings"]
    ft = _w(d, "features.tsv", b"ENSG1\tA\tGene Expression\nENSG2\tB\tGene Expression\n")
    ctx = {"name": "tenx/features.tsv", "siblings": ["tenx/matrix.mtx", "tenx/barcodes.tsv"]}
    page = P.perception_rows(P.PerceptionRowsRequest(datasetRef=ft, folderContext=ctx))
    assert page["headerRow"] is False and page["totalRows"] == 2 and page["columns"][0] == "feature_id", page
    print("PASS test_profile_and_rows_take_folder_context")


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    with tempfile.TemporaryDirectory() as d:
        for t in tests:
            t(d)
    print(f"\nAll {len(tests)} perception folder endpoint tests passed.")


if __name__ == "__main__":
    main()
