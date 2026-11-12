"""
Behavioural tests for the ROUND-3 audit of the dataset profiler (live dev walkthrough, 2026-11-12):
B3 (a valid PDF rated Watch: "Named as PDF, but the content is PDF" + "read as gb18030"), B5 (xlsx
open cost + a first-sheet preview), W2 (decimal-comma column typing), W3 (featureCounts layout),
W4 (nested-table median / row-cap signature, identifier columns), W5 (AnnData layers vs stored
groups), W7 (label / modelling-table rule), W8 (10x set at the folder root), W9 (folder roll-up =
the per-file decision; mixed pairing patterns), P8 (count-safe English), P10 (samplesheets).

Every test fails on the profiler at 12fccee201. Deterministic, no network. To run the same tests
against another copy of the modules (e.g. the old code), point BM_AI_DIR at its galaxy/ai folder
and BM_API_PERCEPTION at its perception.py.

Run standalone (no pytest needed):
    cd backend && python3.9 lib/galaxy/ai/tests/test_dataset_audit_r3_20261112.py
"""
from __future__ import annotations

import importlib.util
import inspect
import json
import os
import sys
import tempfile
import time
import types

_HERE = os.path.dirname(os.path.abspath(__file__))
_AI = os.environ.get("BM_AI_DIR") or os.path.abspath(os.path.join(_HERE, ".."))
_API = os.environ.get("BM_API_PERCEPTION") or os.path.abspath(
    os.path.join(_HERE, "..", "..", "webapps", "galaxy", "api", "perception.py"))


def _load(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


dp = _load("_dp_audit_r3_under_test", os.path.join(_AI, "data_perception.py"))
fp = _load("_fp_audit_r3_under_test", os.path.join(_AI, "folder_profile.py"))
gf = _load("_gf_audit_r3_under_test", os.path.join(_AI, "galaxy_formats.py"))

try:
    import pytest

    @pytest.fixture
    def tmp():
        with tempfile.TemporaryDirectory() as d:
            yield d
except ImportError:  # standalone main() supplies tmp
    pass


def _w(tmp, name, data):
    path = os.path.join(tmp, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb" if isinstance(data, bytes) else "w", **({} if isinstance(data, bytes) else {"newline": ""})) as f:
        f.write(data)
    return path


def _codes(prof):
    return {f["code"]: f for f in prof["findings"]}


def _has(mod: str) -> bool:
    try:
        __import__(mod)
        return True
    except Exception:  # noqa: BLE001
        return False


# ---------------------------------------------------------------------------
# B3 — a binary signature decides; the name/content mismatch never names one format twice
# ---------------------------------------------------------------------------
# The walkthrough's report.pdf: a PDF 1.1 written by R — uncompressed, so all ASCII after a
# 4-byte high-bit comment. The byte heuristic read it as text in GB18030.
_ASCII_PDF = (b"%PDF-1.1\n%\x81\xe2\x81\xe3\x81\xcf\x81\xd3\\r\n1 0 obj\n<<\n/CreationDate (D:20080403110358)\n"
              b"/Title (R Graphics Output)\n/Producer (R 2.6.2)\n>>\nendobj\n" + b"2 0 obj\n<< /Type /Page >>\nendobj\n" * 300
              + b"trailer\n<< /Root 1 0 R >>\n%%EOF\n")


def test_b3_ascii_pdf_is_a_pdf_not_legacy_text(tmp):
    prof = dp.profile_dataset(_w(tmp, "report.pdf", _ASCII_PDF))
    codes = _codes(prof)
    assert prof["format"]["ext"] == "pdf" and prof["format"]["label"] == "PDF", prof["format"]
    assert prof["viewKind"] == "document" and prof["quality"] == "unassessed", prof
    assert "name_content_mismatch" not in codes and "text_encoding_legacy" not in codes, prof["findings"]
    # read_rows decides identically: a PDF is never paged as text rows.
    assert dp.read_rows(os.path.join(tmp, "report.pdf"))["tabular"] is False


# Every signature _sniff_magic knows, behind ASCII-heavy content (the case the byte heuristic gets
# wrong): it is binary, its encoding is never guessed, and its own name is never a "mismatch".
_SIGNATURES = {
    "png": b"\x89PNG\r\n\x1a\n", "jpg": b"\xff\xd8\xff\xe0", "gif": b"GIF89a", "tiff": b"MM\x00*",
    "pdf": b"%PDF-1.4\n", "webp": b"RIFF\x10\x00\x00\x00WEBP", "h5": b"\x89HDF\r\n\x1a\n",
    "pod5": b"\x8bPOD\r\n\x1a\n", "cram": b"CRAM\x03\x00", "bigwig": b"\x26\xfc\x8f\x88",
    "bigbed": b"\xeb\xf2\x89\x87", "sqlite": b"SQLite format 3\x00", "7z": b"7z\xbc\xaf\x27\x1c",
    "npy": b"\x93NUMPY\x01\x00", "parquet": b"PAR1",
}


def test_b3_every_signature_format_is_binary_whatever_its_ascii_share(tmp):
    pad = (b"metadata key=value; description of the content " * 400) + "é".encode("latin-1") * 5
    for ext, magic in _SIGNATURES.items():
        path = _w(tmp, f"x.{ext}", magic + pad)
        d = dp.decide(path, f"x.{ext}")
        assert d.kind in ("binary", "galaxy") and d.encoding is None, (ext, d)
        assert d.mismatch is None, (ext, d.mismatch)
        prof = dp.profile_dataset(path)
        assert not any(c.startswith("text_encoding") for c in _codes(prof)), (ext, prof["findings"])
        assert "name_content_mismatch" not in _codes(prof), (ext, prof["findings"])


def test_b3_mismatch_requires_a_different_format(tmp):
    claim = ("binary", "pdf", "PDF")
    same = dp.Decision("text", "document", "pdf", "PDF", "galaxy", "pdf")
    assert dp._mismatch(claim, same) is None
    other = dp.Decision("text", "document", "txt", "Text", "biomate")
    assert dp._mismatch(claim, other) == ("PDF", "Text")
    # A real contradiction still fires: text named .png.
    prof = dp.profile_dataset(_w(tmp, "fake.png", "this is not an image\n"))
    assert _codes(prof)["name_content_mismatch"]["params"] == {"named": "PNG", "detected": "Text"}, prof["findings"]


class _GalaxyBinaryStub:
    """Galaxy identifying the content as a NON-text datatype (its Image/Binary classes)."""

    GENERIC_EXTS = frozenset({"data", "binary", "txt", "text", "tabular", "tsv"})

    def identify(self, path, name):
        return "eps"

    def is_text_ext(self, ext):
        return False

    def metadata(self, path, ext):
        return {}

    def label_for(self, ext):
        return ext.upper()

    def spec_column_names(self, ext):
        return None

    def view_for_ext(self, ext):
        return "image"


def test_b3_galaxy_binary_identification_wins_over_the_ascii_share(tmp):
    path = _w(tmp, "figure.eps", b"%!PS-Adobe-3.0 EPSF-3.0\n%%BoundingBox: 0 0 10 10\n" + b"0 0 moveto\n" * 200 + b"\xa9\n")
    saved = list(dp._GF_MODULE)
    dp._GF_MODULE[:] = [_GalaxyBinaryStub()]
    try:
        prof = dp.profile_dataset(path)
    finally:
        dp._GF_MODULE[:] = saved
    assert prof["viewKind"] == "image" and prof["format"]["ext"] == "eps", prof
    assert not any(c.startswith("text_encoding") for c in _codes(prof)), prof["findings"]


# ---------------------------------------------------------------------------
# B5 — an xlsx opens with a BOUNDED read and carries a first-sheet preview
# ---------------------------------------------------------------------------
def _workbook(path, rows, header=("sample", "condition", "value"), write_only=True):
    import openpyxl

    wb = openpyxl.Workbook(write_only=write_only)
    ws = wb.create_sheet("data") if write_only else wb.active
    if not write_only:
        ws.title = "data"
    ws.append(list(header))
    for i in range(rows):
        ws.append([f"S{i}", "ctrl" if i % 2 else "trt", i * 0.5])
    if write_only:
        wb.create_sheet("meta").append(["k", "v"])
    wb.save(path)
    return path


def test_b5_xlsx_without_a_stored_dimension_is_not_parsed_whole(tmp):
    if not _has("openpyxl"):
        print("SKIP test_b5_xlsx_without_a_stored_dimension_is_not_parsed_whole (no openpyxl)")
        return
    from openpyxl.worksheet import _reader

    path = _workbook(os.path.join(tmp, "big.xlsx"), 20000)  # write-only: no <dimension> element
    calls = []
    orig = _reader.WorkSheetParser.parse_dimensions

    def counting(self):  # openpyxl's sizing parses a dimensionless sheet to its END
        calls.append(1)
        return orig(self)

    _reader.WorkSheetParser.parse_dimensions = counting
    try:
        t = time.time()
        prof = dp.profile_dataset(path)
        took = time.time() - t
    finally:
        _reader.WorkSheetParser.parse_dimensions = orig
    assert not calls, "openpyxl's whole-sheet dimension scan ran"
    assert took < 3.0, took
    assert prof["format"]["ext"] == "xlsx" and prof["viewKind"] == "document", prof["format"]
    assert prof["columns"] == ["sample", "condition", "value"], prof.get("columns")
    assert len(prof["sampleRows"]) == dp.MAX_PREVIEW_ROWS and prof["sampleRows"][0] == ["S0", "trt", "0"], prof["sampleRows"][:2]
    assert prof["previewSheet"] == "data" and "spreadsheet_preview" in _codes(prof), prof["findings"]
    assert _codes(prof)["spreadsheet_sheets"]["params"]["sheets"] == ["data", "meta"]
    # The sheet stores no size: the profile does not invent one from the preview.
    assert prof["shape"] == {"rows": 0, "cols": 0}, prof["shape"]


def test_b5_xlsx_with_a_dimension_reports_it(tmp):
    if not _has("openpyxl"):
        print("SKIP test_b5_xlsx_with_a_dimension_reports_it (no openpyxl)")
        return
    path = _workbook(os.path.join(tmp, "small.xlsx"), 12, write_only=False)
    meta = gf.metadata(path, "xlsx")
    assert meta["sheets"] == [{"name": "data", "rows": 13, "cols": 3}], meta
    assert meta["preview"]["rows"][0] == ["sample", "condition", "value"] and len(meta["preview"]["rows"]) == 13, meta
    prof = dp.profile_dataset(path)
    assert prof["shape"] == {"rows": 13, "cols": 3} and len(prof["sampleRows"]) == 12, prof


# ---------------------------------------------------------------------------
# W2 — decimal-comma numbers are numbers in the column statistics
# ---------------------------------------------------------------------------
def test_w2_decimal_comma_columns_are_numeric(tmp):
    path = _w(tmp, "eu.csv", "sample;weight_g;conc_mg_ml;ratio\nA;12,5;0,031;1,2\nB;13,1;0,029;1,05\n"
                             "C;11,8;0,040;0,98\nD;12,9;0,035;1,10\n")
    prof = dp.profile_dataset(path)
    assert prof["decimal"] == "," and dp.read_rows(path)["decimal"] == ",", prof
    stats = {c["name"]: c for c in prof["columnStats"]}
    for col in ("weight_g", "conc_mg_ml", "ratio"):
        assert stats[col]["type"] == "numeric", stats[col]
    assert (stats["weight_g"]["min"], stats["weight_g"]["max"]) == (11.8, 13.1), stats["weight_g"]
    assert stats["sample"]["type"] == "text" and stats["sample"]["role"] == "identifier", stats["sample"]
    # A point-decimal table reports no decimal mark on the profile.
    assert "decimal" not in dp.profile_dataset(_w(tmp, "us.csv", "a,b\n1.5,2\n2.5,3\n"))


# ---------------------------------------------------------------------------
# W3 — featureCounts is recognised; its annotation columns are not "near-constant"
# ---------------------------------------------------------------------------
def test_w3_featurecounts_layout(tmp):
    body = ('# Program:featureCounts v2.0.1; Command:"featureCounts" "-a" "genes.gtf"\n'
            "Geneid\tChr\tStart\tEnd\tStrand\tLength\tS1.bam\tS2.bam\n"
            + "".join(f"ENSG{i:011d}\tchr1\t{1 + 1000 * i}\t{800 + 1000 * i}\t+\t800\t{(i * 37) % 300}\t{(i * 53) % 310}\n"
                      for i in range(15)))
    prof = dp.profile_dataset(_w(tmp, "featurecounts.txt", body))
    assert prof["format"]["label"] == "featureCounts counts" and prof["format"]["layout"] == "featurecounts", prof["format"]
    assert prof["quality"] == "good" and "near_constant" not in _codes(prof), prof["findings"]
    roles = {c["name"]: c.get("role") for c in prof["columnStats"]}
    assert all(roles[c] == "annotation" for c in ("Geneid", "Chr", "Start", "End", "Strand", "Length")), roles
    assert roles["S1.bam"] == "measurement", roles  # round 4 (N6): count columns
    # The same name claim (.tsv) keeps the recognised label.
    prof = dp.profile_dataset(_w(tmp, "fc.tsv", body))
    assert prof["format"]["label"] == "featureCounts counts", prof["format"]


def test_w3_column_findings_carry_structured_columns(tmp):
    rows = ["id,constant,mostly_empty"] + [f"{i},x," for i in range(30)]
    prof = dp.profile_dataset(_w(tmp, "w.csv", "\n".join(rows) + "\n"))
    by = _codes(prof)
    assert by["near_constant"]["columns"] == ["constant"], by["near_constant"]
    assert by["high_missing"]["columns"] == ["mostly_empty"], by["high_missing"]


# ---------------------------------------------------------------------------
# W4 — nested-table median and the row-cap signature; identifier columns
# ---------------------------------------------------------------------------
def _nested(tmp, name, sizes):
    recs = [{"source": "epar", "page": 30 + i, "rows": [[f"r{r}", "x"] for r in range(n)]} for i, n in enumerate(sizes)]
    return dp.profile_dataset(_w(tmp, name, "".join(json.dumps(r) + "\n" for r in recs)))


def test_w4_bimodal_table_sizes_are_not_a_row_cap(tmp):
    prof = _nested(tmp, "t.jsonl", [4, 7, 4, 7, 4, 7])
    by = _codes(prof)
    assert by["nested_tables"]["params"]["median_rows"] == 5.5, by["nested_tables"]
    assert "nested_row_cap" not in by, prof["findings"]
    stats = {c["name"]: c for c in prof["columnStats"]}
    assert stats["page"]["role"] == "identifier", stats["page"]
    # A real cap still fires: 70% at the maximum, the rest spread over smaller sizes.
    prof = _nested(tmp, "cap.jsonl", [7] * 14 + [3, 4, 5, 6, 3, 4])
    assert _codes(prof)["nested_row_cap"]["level"] == "watch", prof["findings"]
    assert dp._median([1, 2, 3]) == 2 and dp._median([4, 4, 7, 7]) == 5.5 and dp._median([2, 4]) == 3


def test_w4_identifier_rule(tmp):
    rows = ["sample_count,page,value"] + [f"{(i * 7) % 5},{30 + i // 2},{i * 1.5}" for i in range(20)]
    stats = {c["name"]: c for c in dp.profile_dataset(_w(tmp, "ids.csv", "\n".join(rows) + "\n"))["columnStats"]}
    assert stats["page"].get("role") == "identifier", stats["page"]          # non-decreasing integers
    assert stats["sample_count"].get("role") == "measurement", stats["sample_count"]  # an unordered count
    assert stats["value"].get("role") == "measurement", stats["value"]


# ---------------------------------------------------------------------------
# W5 — AnnData layers (the ``layers`` group) vs the stored top-level groups
# ---------------------------------------------------------------------------
def test_w5_anndata_layers_and_components():
    p = dp.DataProfile()
    meta = {"shape": [5, 4], "obs_layers": ["louvain"], "var_layers": ["gene_ids"],
            "layers_names": ["X", "layers", "obs", "obsm", "var", "varm"], "anndata_layers": ["counts", "spliced"]}
    assert dp._galaxy_meta_findings(p, "h5ad", meta, "AnnData (h5ad)")
    by = _codes({"findings": p.findings})
    assert by["anndata_layers"]["params"] == {"count": 2, "layers": ["counts", "spliced"]}, by
    assert by["anndata_components"]["params"]["components"] == ["X", "layers", "obs", "obsm", "var", "varm"], by
    assert "hdf5_groups" not in by
    assert p.to_dict()["layers"] == ["counts", "spliced"]
    p = dp.DataProfile()
    dp._galaxy_meta_findings(p, "h5ad", dict(meta, anndata_layers=[]), "AnnData (h5ad)")
    assert "anndata_no_layers" in _codes({"findings": p.findings}) and p.to_dict()["layers"] == []


def test_w5_anndata_layers_read_from_the_file(tmp):
    if not _has("h5py"):
        print("SKIP test_w5_anndata_layers_read_from_the_file (no h5py)")
        return
    import h5py

    with_layers, without = os.path.join(tmp, "a.h5ad"), os.path.join(tmp, "b.h5ad")
    for path, layers in ((with_layers, ("counts",)), (without, ())):
        with h5py.File(path, "w") as f:
            f.create_dataset("X", data=[[1, 2], [3, 4]])
            f.create_group("obs")
            f.create_group("var")
            if layers:
                g = f.create_group("layers")
                for name in layers:
                    g.create_dataset(name, data=[[1, 2], [3, 4]])
    assert gf.anndata_layers(with_layers) == ["counts"]
    assert gf.anndata_layers(without) == []


# ---------------------------------------------------------------------------
# W7 — balance / effective N / leakage only for a confident label of a modelling table
# ---------------------------------------------------------------------------
def test_w7_small_sample_sheet_has_no_modelling_statistics(tmp):
    sheet = 'sample_id,condition,notes,read_depth\nS1,control,"plain note",1200000\nS2,treated,"has, a comma",980000\n' \
            'S3,treated,"multi-line\nnote here",1500000\nS4,control,"says ""quoted"" word",1100000\n'
    prof = dp.profile_dataset(_w(tmp, "samples_quoted.csv", sheet))
    assert prof["label"] == {"column": "condition", "confident": False}, prof.get("label")
    for key in ("labelColumn", "classBalance", "effectiveN", "leakage"):
        assert key not in prof, (key, prof)
    assert "label_few_rows" in _codes(prof) and "table_clean_label_unchecked" in _codes(prof), prof["findings"]
    assert prof["quality"] == "good", prof


def test_w7_modelling_table_is_confident(tmp):
    rows = ["feat1,feat2,label"] + [f"{i % 7},{(i * 3) % 11},{'a' if i % 2 else 'b'}" for i in range(50)]
    prof = dp.profile_dataset(_w(tmp, "m.csv", "\n".join(rows) + "\n"))
    assert prof["label"] == {"column": "label", "confident": True} and prof["labelColumn"] == "label", prof
    assert prof["classBalance"] and prof["effectiveN"] == 50, prof
    assert "table_clean" in _codes(prof), prof["findings"]
    # A label with nothing to model beside it (identifier + batch only) is not a modelling target.
    rows = ["sample_id,batch,condition"] + [f"S{i},b{i % 3},{'x' if i % 2 else 'y'}" for i in range(40)]
    prof = dp.profile_dataset(_w(tmp, "design.csv", "\n".join(rows) + "\n"))
    assert prof["label"]["confident"] is False and "classBalance" not in prof and "labelColumn" not in prof, prof
    assert "label_no_features" in _codes(prof), prof["findings"]


# ---------------------------------------------------------------------------
# W8 / W9 / P10 — folder profile
# ---------------------------------------------------------------------------
def test_w8_tenx_set_at_the_folder_root_has_no_dot_dir():
    head = "%%MatrixMarket matrix coordinate integer general\n4 5 8\n"
    out = fp.profile_folder("", ["matrix.mtx", "barcodes.tsv", "features.tsv"], read_head=lambda p: head)
    f = _codes(out)["folder_tenx_recognised"]
    assert f["params"]["dir"] is None, f
    out = fp.profile_folder("", ["matrix.mtx", "barcodes.tsv"], read_head=lambda p: None)
    for code in ("folder_tenx_recognised_nodims", "folder_tenx_incomplete"):
        assert _codes(out)[code]["params"]["dir"] is None, out["findings"]
    out = fp.profile_folder("", ["tenx/matrix.mtx", "tenx/barcodes.tsv", "tenx/features.tsv"], read_head=lambda p: head)
    assert _codes(out)["folder_tenx_recognised"]["params"]["dir"] == "tenx"


def test_w9_mixed_pairing_patterns_are_all_named():
    names = ["pairs/S1_R1.fastq.gz", "pairs/S1_R2.fastq.gz", "WT_1_1.fq.gz", "WT_1_2.fq.gz"]
    out = fp.profile_folder("", names, engine="fallback")
    f = _codes(out)["folder_fastq_pairs"]["params"]
    assert set(f["patterns"]) == {"_R1/_R2", "_1/_2"} and " and " in f["pattern"], f
    assert set(out["fastq"]["patterns"]) == {"Rs", "illumina"}, out["fastq"]


def test_w9_rollup_uses_the_per_file_decision():
    decisions = {"inputs/counts.txt": {"ext": "tsv", "label": "TSV", "viewKind": "table"},
                 "inputs/fc.txt": {"ext": "tsv", "label": "featureCounts counts", "viewKind": "table"}}
    out = fp.profile_folder("inputs", ["inputs/counts.txt", "inputs/fc.txt", "inputs/notes.txt"], decisions=decisions)
    roll = {(r["format"], r["label"]): r for r in out["rollup"]}
    assert roll[("tsv", "TSV")]["count"] == 1 and roll[("tsv", "TSV")]["viewKind"] == "table", out["rollup"]
    assert roll[("tsv", "featureCounts counts")]["count"] == 1, out["rollup"]
    assert roll[("txt", "Text")]["count"] == 1, out["rollup"]  # no decision: labelled by name


def _perception_api():
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
    ai.__path__ = [_AI]  # type: ignore[attr-defined]
    sys.modules["galaxy.ai"] = ai
    sys.modules["galaxy"].__path__ = []  # type: ignore[attr-defined]
    return _load("_perception_r3_under_test", _API)


def test_w9_folder_endpoint_labels_files_by_their_content(tmp):
    P = _perception_api()
    pid = "p-r3"
    objects = {
        f"projects/{pid}/inputs/counts.txt": b"gene_id\tctrl_1\tctrl_2\nG1\t5\t7\nG2\t3\t9\nG3\t1\t2\n",
        f"projects/{pid}/inputs/report.pdf": _ASCII_PDF[:2000],
    }
    saved = P._s3_head
    P._s3_head = lambda bucket, key: objects.get(key)
    try:
        out = P.perception_folder_profile(P.FolderProfileRequest(path="", projectId=pid, files=[
            {"name": n.split("/inputs/")[1], "datasetRef": n} for n in objects]))
    finally:
        P._s3_head = saved
    labels = {r["label"]: r for r in out["rollup"]}
    assert "TSV" in labels and labels["TSV"]["viewKind"] == "table", out["rollup"]
    assert "PDF" in labels and "Text" not in labels, out["rollup"]


def test_p10_samplesheet_keeps_layouts_apart():
    names = ["pairs/S1_R1.fastq.gz", "pairs/S1_R2.fastq.gz", "pairs/S2_R1.fastq.gz", "WT_1_1.fq.gz", "WT_1_2.fq.gz"]
    out = fp.profile_folder("", names, engine="fallback")
    sheet = out["samplesheet"]
    assert sheet["layout"] == "paired" and sheet["pathBase"] == "project inputs", sheet
    assert [r[0] for r in sheet["rows"]] == ["S1", "WT_1"] and all(r[2] for r in sheet["rows"]), sheet["rows"]
    single = sheet["single"]
    assert single["rows"] == [["S2", "pairs/S2_R1.fastq.gz", ""]] and single["layout"] == "single_end", single
    assert single["filename"] == "samplesheet_single_end.csv" and sheet["excluded"] == ["pairs/S2_R1.fastq.gz"]
    f = _codes(out)["folder_samplesheet_single_end"]["params"]
    assert f["rows"] == 1 and f["names"] == ["S2_R1.fastq.gz"], f
    # All single-end: the sheet IS the single-end sheet.
    out = fp.profile_folder("", ["a.fastq.gz", "b.fastq.gz"], engine="fallback")
    assert out["samplesheet"]["layout"] == "single_end" and "single" not in out["samplesheet"], out["samplesheet"]


# ---------------------------------------------------------------------------
# P8 — English templates read correctly for a count of 1
# ---------------------------------------------------------------------------
def test_p8_count_safe_wording():
    one = {"count": 1, "columns": ["a"], "references": 1, "length": 10, "samples": ["s"], "features": 1,
           "comments": 1, "attributes": ["gene_id"], "rows": 1, "cols": 1, "nnz": 1, "field": "integer",
           "density": 100, "column": "c", "tables": 1, "median_rows": 1, "median_cols": 1, "max_rows": 1,
           "distinct": 1, "expected": 1, "pct": 100, "layers": ["counts"], "components": ["X"]}
    for code in ("anndata_obs", "anndata_var", "annotation_features", "alignment_references", "alignment_read_groups",
                 "fasta_empty_records", "fasta_orphan_lines", "mtx_dimensions", "nested_tables", "nested_row_cap",
                 "label_free_text", "ragged_rows", "anndata_layers", "anndata_components", "duplicate_rows"):
        text = dp.finding_text(code, one)
        assert text, code
        for bad in ("1 cell annotation columns", "1 gene annotation columns", "1 feature lines", "1 comment lines",
                    "1 attribute keys", "1 reference sequences", "1 read groups", "1 headers", "1 sequence lines",
                    "1 stored entries", "1 embedded tables", "1 rows", "1 columns", "1 distinct values", "1 fields"):
            assert bad not in text, (code, text)


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for t in tests:
        with tempfile.TemporaryDirectory() as d:
            try:
                t(d) if inspect.signature(t).parameters else t()
                print(f"PASS {t.__name__}")
            except Exception as exc:  # noqa: BLE001 — report every failure, then exit non-zero
                failed += 1
                print(f"FAIL {t.__name__}: {type(exc).__name__}: {str(exc)[:300]}")
    print(f"\n{len(tests) - failed}/{len(tests)} round-3 dataset-audit tests passed.")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
