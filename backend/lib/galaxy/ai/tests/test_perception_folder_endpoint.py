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

try:  # under pytest the tests take a temp directory as ``d`` (main() supplies it standalone)
    import pytest

    @pytest.fixture
    def d():
        with tempfile.TemporaryDirectory() as tmp:
            yield tmp
except ImportError:
    pass


def _w(d, name, data):
    path = os.path.join(d, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    return path


class _FakeS3:
    """Stands in for the ranged S3 GET: serves local bytes for project keys and records every
    object the endpoint asked for."""

    def __init__(self, objects):
        self.objects = objects
        self.calls = []

    def __call__(self, bucket, key):
        self.calls.append((bucket, key))
        data = self.objects.get(key)
        return data[: P._HEAD_BYTES] if data is not None else None


def _with_s3(fake, fn):
    saved = P._s3_head
    P._s3_head = fake
    try:
        return fn()
    finally:
        P._s3_head = saved


def test_folder_profile_endpoint(d):
    # A gzipped 10x matrix larger than the 64 KB head: dims still come from the partial read.
    body = "%%MatrixMarket matrix coordinate integer general\n% big\n33538 5 200000\n" + "".join(
        f"{i % 33538 + 1} {i % 5 + 1} {i % 7 + 1}\n" for i in range(200000))
    blob = gzip.compress(body.encode())
    assert len(blob) > P._HEAD_BYTES
    pid = "0b7c6f3e-1d2a-4c5b-9e8f-112233445566"
    key = f"projects/{pid}/inputs/tenx/matrix.mtx.gz"
    fake = _FakeS3({key: blob})
    req = P.FolderProfileRequest(path="tenx", projectId=pid, files=[
        {"name": "tenx/matrix.mtx.gz", "datasetRef": key},
        {"name": "tenx/barcodes.tsv.gz", "datasetRef": f"projects/{pid}/inputs/tenx/barcodes.tsv.gz"},
        {"name": "tenx/features.tsv.gz", "datasetRef": f"projects/{pid}/inputs/tenx/features.tsv.gz"},
    ])
    out = _with_s3(fake, lambda: P.perception_folder_profile(req))
    assert out["kind"] == "tenx_matrix", out
    s = out["tenx"]["sets"][0]
    assert (s["genes"], s["cells"], s["nnz"]) == (33538, 5, 200000), s
    # Each validated project object's head is read ONCE, by its key (round 3, W9: the roll-up is
    # labelled by each file's content decision; the matrix's dims reuse the same head).
    assert sorted(fake.calls) == sorted((P._default_bucket(), f["datasetRef"]) for f in req.files), fake.calls

    names = ["pairs/S1_R1.fastq.gz", "pairs/S1_R2.fastq.gz", "pairs/S2_R1.fastq.gz"]
    out = P.perception_folder_profile(P.FolderProfileRequest(path="pairs", files=[{"name": n, "datasetRef": None} for n in names]))
    assert out["kind"] == "fastq_set" and out["fastq"]["pairs"] == 1 and out["fastq"]["orphans"] == ["pairs/S2_R1.fastq.gz"], out
    assert len(out["samplesheet"]["rows"]) == 1 and len(out["samplesheet"]["single"]["rows"]) == 1  # P10
    print("PASS test_folder_profile_endpoint")


def test_folder_profile_reads_only_project_objects(d):
    # S5 (audit 2026-11-12): the endpoint read any files[].datasetRef — a local path, another bucket,
    # another project's key. Only keys under projects/<projectId>/ are read now.
    secret = _w(d, "secret/matrix.mtx", b"%%MatrixMarket matrix coordinate integer general\n7 7 7\n")
    pid, other = "p-1111", "p-2222"
    files_for = lambda ref: [{"name": "x/matrix.mtx", "datasetRef": ref}, {"name": "x/barcodes.tsv", "datasetRef": None},
                             {"name": "x/features.tsv", "datasetRef": None}]
    fake = _FakeS3({f"projects/{other}/x/matrix.mtx": b"%%MatrixMarket matrix coordinate integer general\n9 9 9\n"})
    for ref in (secret, "file://" + secret, "../" + secret, "s3://someone-elses-bucket/projects/p-1111/x/matrix.mtx",
                f"projects/{other}/x/matrix.mtx", f"projects/{pid}/../{other}/x/matrix.mtx", "uploads/x/matrix.mtx"):
        out = _with_s3(fake, lambda: P.perception_folder_profile(
            P.FolderProfileRequest(path="x", projectId=pid, files=files_for(ref))))
        s = out["tenx"]["sets"][0]
        assert "genes" not in s and "cells" not in s, (ref, s)
        assert "folder_tenx_recognised_nodims" in [f["code"] for f in out["findings"]], (ref, out["findings"])
    assert fake.calls == [], fake.calls
    # Without a projectId nothing is read, even a well-formed project key.
    out = _with_s3(fake, lambda: P.perception_folder_profile(
        P.FolderProfileRequest(path="x", files=files_for(f"projects/{other}/x/matrix.mtx"))))
    assert "genes" not in out["tenx"]["sets"][0] and fake.calls == [], fake.calls
    # The project's own key IS read.
    fake.objects[f"projects/{pid}/x/matrix.mtx"] = b"%%MatrixMarket matrix coordinate integer general\n3 4 5\n"
    out = _with_s3(fake, lambda: P.perception_folder_profile(
        P.FolderProfileRequest(path="x", projectId=pid, files=files_for(f"projects/{pid}/x/matrix.mtx"))))
    assert (out["tenx"]["sets"][0]["genes"], out["tenx"]["sets"][0]["cells"]) == (3, 4), out
    assert P.folder_object_ref(f"s3://{P._default_bucket()}/projects/{pid}/x/m.mtx", pid) == (P._default_bucket(), f"projects/{pid}/x/m.mtx")
    print("PASS test_folder_profile_reads_only_project_objects")


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
