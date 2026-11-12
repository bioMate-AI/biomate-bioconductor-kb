"""
Behavioural tests for the ROUND-2 audit of the dataset profiler (2026-11-12): NEW-4 (long-line
text read as binary), NEW-6 (PDB vocabulary + experimental vs predicted structure), NEW-7 (JSONL
with an invalid first line), NEW-8 (empty/blank agreement, non-UTF-8 text, duplicate column
names), R10 rest (decimal comma), the read_rows ``delimiter`` contract, the single English
template table, and ``order_key`` for unsorted alignments.

Every test fails on the profiler at c4bfb9fd8c. Deterministic, no network; where Galaxy's
identification matters a stub stands in (the real Galaxy path is checked in dev's container).

Run standalone (no pytest needed):
    cd backend && python3.9 lib/galaxy/ai/tests/test_dataset_audit_r2_20261112.py
"""
from __future__ import annotations

import gzip
import importlib.util
import inspect
import json
import os
import subprocess
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_AI = os.environ.get("BM_AI_DIR") or os.path.abspath(os.path.join(_HERE, ".."))


def _load(name: str, fname: str):
    spec = importlib.util.spec_from_file_location(name, os.path.join(_AI, fname))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


dp = _load("_dp_audit_r2_under_test", "data_perception.py")

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


def _with_galaxy(stub, fn):
    saved = list(dp._GF_MODULE)
    dp._GF_MODULE[:] = [stub]
    try:
        return fn()
    finally:
        dp._GF_MODULE[:] = saved


class _GalaxyStub:
    GENERIC_EXTS = frozenset({"data", "binary", "txt", "text", "tabular", "tsv"})

    def __init__(self, ext, text=True):
        self.ext, self.text = ext, text

    def identify(self, path, name):
        return self.ext

    def is_text_ext(self, ext):
        return self.text

    def metadata(self, path, ext):
        return {}

    def label_for(self, ext):
        return ext.upper()

    def spec_column_names(self, ext):
        return None

    def view_for_ext(self, ext):
        return None


# ---------------------------------------------------------------------------
# NEW-4 — text whose first 8 KB holds no line break is text, not binary
# ---------------------------------------------------------------------------
def _wide_csv(cols, rows=3):
    head = "gene," + ",".join(f"TCGA-AB-{j:04d}-01A" for j in range(cols)) + "\n"
    return head + "".join(f"G{i}," + ",".join(str((i * 7 + j) % 101) for j in range(cols)) + "\n" for i in range(rows))


def test_new4_wide_csv_is_a_table_not_binary(tmp):
    for cols in (1000, 5000):  # first line ≈ 17 KB and ≈ 85 KB (beyond the 64 KB head)
        path = _w(tmp, f"wide{cols}.csv", _wide_csv(cols))
        prof = dp.profile_dataset(path)
        assert prof["viewKind"] == "table" and prof["format"]["ext"] == "csv", (cols, prof["format"], prof["viewKind"])
        assert "name_content_mismatch" not in _codes(prof), (cols, prof["findings"])
        assert prof["shape"] == {"rows": 3, "cols": cols + 1}, prof["shape"]
        page = dp.read_rows(path)
        assert page["tabular"] is True and len(page["columns"]) == cols + 1 and page["totalRows"] == 3, cols


def test_new4_minified_json_and_long_jsonl_records_are_text(tmp):
    doc = json.dumps({"genes": [{"id": f"ENSG{i:011d}", "v": i} for i in range(700)]})  # ≈ 20 KB, one line
    assert len(doc) > 20_000 and "\n" not in doc
    prof = dp.profile_dataset(_w(tmp, "min.json", doc))
    assert prof["viewKind"] == "json" and prof["format"]["ext"] == "json", prof
    assert "name_content_mismatch" not in _codes(prof), prof["findings"]
    recs = "".join(json.dumps({"i": i, "text": "y" * 15_000}) + "\n" for i in range(3))  # 15 KB records
    path = _w(tmp, "long.jsonl", recs)
    prof = dp.profile_dataset(path)
    assert prof["viewKind"] == "records" and prof["shape"] == {"rows": 3, "cols": 2}, prof
    assert "name_content_mismatch" not in _codes(prof), prof["findings"]
    assert dp.read_rows(path)["tabular"] is True


def test_new4_binary_is_judged_on_the_bytes(tmp):
    # Binary bytes still decide: NUL / control bytes / undecodable high bytes beside control bytes.
    for name, data in (("rand.csv", bytes(range(256)) * 64),
                       ("hi.csv", bytes(range(1, 256)) * 40)):
        prof = dp.profile_dataset(_w(tmp, name, data))
        assert prof["viewKind"] == "binary" and dp.read_rows(os.path.join(tmp, name))["tabular"] is False, (name, prof)
    # A text datatype identified by Galaxy is honoured (control-byte-separated values Galaxy sniffed).
    rs = "".join(f"a\x1eb\x1e{i}\n" for i in range(200))
    path = _w(tmp, "rs.csv", "x,y\n" + rs)
    prof = _with_galaxy(_GalaxyStub("csv"), lambda: dp.profile_dataset(path))
    assert prof["viewKind"] == "table", prof
    # Legacy 8-bit text whose bytes are mostly non-ASCII (Cyrillic, Windows-1251) is text, its
    # encoding reported — not binary.
    ru = "ген;образец;значение\n" + "".join(f"ТП53;опухоль;{i}\n" for i in range(50))
    prof = dp.profile_dataset(_w(tmp, "ru.csv", ru.encode("cp1251")))
    assert prof["viewKind"] == "table" and "text_encoding_legacy" in _codes(prof), prof


# ---------------------------------------------------------------------------
# NEW-6 — complete wwPDB record vocabulary; experimental vs predicted
# ---------------------------------------------------------------------------
_XRAY_PDB = """HEADER    HYDROLASE                               01-JAN-00   1ABC
TITLE     A SMALL X-RAY STRUCTURE
COMPND    MOL_ID: 1;
SOURCE    MOL_ID: 1;
KEYWDS    HYDROLASE
EXPDTA    X-RAY DIFFRACTION
AUTHOR    A.N.OTHER
REVDAT   1   01-JAN-00 1ABC    0
REMARK   2 RESOLUTION.    1.80 ANGSTROMS.
SEQRES   1 A    2  LEU GLY
HET    HOH  A 101       1
HELIX    1   1 LEU A    1  GLY A    2  1                                   2
SHEET    1   A 2 LEU A   1  GLY A   2  0
CRYST1   50.000   60.000   70.000  90.00  90.00  90.00 P 21 21 21    4
ORIGX1      1.000000  0.000000  0.000000        0.00000
SCALE1      0.020000  0.000000  0.000000        0.00000
ATOM      1  N   LEU A   1      11.104  12.200  13.300  1.00 45.00           N
ANISOU    1  N   LEU A   1     5000   4000   3000    100    200    300       N
ATOM      2  CA  LEU A   1      11.900  12.500  13.000  1.00 62.00           C
ATOM      3  CA  GLY A   2      12.900  13.500  14.000  1.00 30.00           C
TER       4      GLY A   2
HETATM    5  O   HOH A 101      20.000  20.000  20.000  1.00 25.00           O
CONECT    5    5
MASTER        0    0    1    1    1    0    0    6    4    1    1    1
END
"""


def test_new6_xray_pdb_is_a_structure_and_experimental(tmp):
    for name in ("xr.pdb", "xr.txt"):
        prof = dp.profile_dataset(_w(tmp, name, _XRAY_PDB))
        assert prof["viewKind"] == "structure" and prof["format"]["ext"] == "pdb", (name, prof["viewKind"], prof["format"])
        assert prof["structure"]["predicted"] is False and prof["structure"]["method"] == "X-RAY DIFFRACTION", prof
        assert prof["structure"]["method_key"] == "xray" and prof["structure"]["bfactor"] == "displacement", prof
        assert _codes(prof)["structure_experimental"]["params"]["method_key"] == "xray", prof["findings"]
    # A partial PDB: a ligand's HETATM + CONECT records only.
    lig = ("HETATM    1  C1  LIG A   1       1.000   2.000   3.000  1.00  0.00           C\n"
           "HETATM    2  O1  LIG A   1       1.500   2.500   3.500  1.00  0.00           O\n"
           "CONECT    1    2\nEND\n")
    prof = dp.profile_dataset(_w(tmp, "lig.pdb", lig))
    assert prof["viewKind"] == "structure", prof


def test_new6_predicted_models_are_marked_predicted(tmp):
    af = ("HEADER                                            01-JUL-21                     \n"
          "TITLE     ALPHAFOLD MONOMER V2.0 PREDICTION FOR PROTEIN P12345\n"
          "ATOM      1  N   MET A   1      11.104  12.200  13.300  1.00 91.20           N\n"
          "ATOM      2  CA  MET A   1      11.900  12.500  13.000  1.00 88.10           C\nEND\n")
    prof = dp.profile_dataset(_w(tmp, "AF-P12345-F1-model_v4.pdb", af))
    s = prof["structure"]
    assert s["predicted"] is True and s["predictor"] == "ALPHAFOLD" and s["bfactor"] == "confidence", s
    assert _codes(prof)["structure_predicted"]["params"]["predictor"] == "ALPHAFOLD", prof["findings"]
    theo = "EXPDTA    THEORETICAL MODEL\n" + af.split("\n", 2)[2]
    s = dp.profile_dataset(_w(tmp, "model.pdb", theo))["structure"]
    assert s["predicted"] is True and s["method"] == "THEORETICAL MODEL", s
    # No header at all: the backend does not guess.
    bare = af.split("\n", 2)[2]
    s = dp.profile_dataset(_w(tmp, "bare.pdb", bare))["structure"]
    assert s["predicted"] is None and s["bfactor"] is None, s
    # mmCIF: _exptl.method.
    cif = ("data_1ABC\n_entry.id 1ABC\n_exptl.method 'ELECTRON MICROSCOPY'\nloop_\n_atom_site.group_PDB\n"
           "_atom_site.id\nATOM 1\n")
    prof = dp.profile_dataset(_w(tmp, "1abc.cif", cif))
    assert prof["viewKind"] == "structure" and prof["structure"]["method_key"] == "em", prof


# ---------------------------------------------------------------------------
# NEW-7 — JSON Lines decided from the majority of lines, not the first line
# ---------------------------------------------------------------------------
def test_new7_jsonl_with_an_invalid_first_line(tmp):
    good = [json.dumps({"a": i, "b": i * 2}) for i in range(20)]
    for name in ("bad_first.jsonl", "bad_first.txt"):
        path = _w(tmp, name, "\n".join(["oops, not json"] + good) + "\n")
        prof = dp.profile_dataset(path)
        assert prof["viewKind"] == "records" and prof["format"]["ext"] == "jsonl", (name, prof["format"], prof["findings"])
        assert prof["shape"] == {"rows": 20, "cols": 2} and _codes(prof)["jsonl_skipped_lines"]["params"] == {"count": 1}, prof
        assert "name_content_mismatch" not in _codes(prof), prof["findings"]
        page = dp.read_rows(path)
        assert page["tabular"] is True and page["skippedLines"] == 1 and page["columns"] == ["a", "b"], page
    # Bad lines in the minority anywhere: still JSON Lines, the bad ones reported.
    lines = ['{"a":1}', "not json", '{"a":2}', '{"a":3}', '{"a":4']
    prof = dp.profile_dataset(_w(tmp, "two_bad.jsonl", "\n".join(lines) + "\n"))
    assert prof["viewKind"] == "records" and _codes(prof)["jsonl_skipped_lines"]["params"] == {"count": 2}, prof


# ---------------------------------------------------------------------------
# NEW-8 — empty/blank agreement, encodings, duplicate column names
# ---------------------------------------------------------------------------
def test_new8_empty_and_blank_files_agree_with_read_rows(tmp):
    cases = {"empty.csv": b"", "blank.csv": "\n\n  \n", "empty.csv.gz": gzip.compress(b""),
             "nl.txt": b"\n", "empty.jsonl": b""}
    for name, data in cases.items():
        path = _w(tmp, name, data)
        prof = dp.profile_dataset(path)
        page = dp.read_rows(path)
        assert prof["quality"] == "blocked" and prof["viewKind"] == "unknown", (name, prof)
        assert page["tabular"] is False and page["viewKind"] == prof["viewKind"], (name, page)


def test_new8_latin1_and_gb18030_tables_are_decoded_not_replaced(tmp):
    latin = "name,city,value\nJosé,Málaga,1\nFrançois,Besançon,2\nJürgen,Köln,3\n"
    path = _w(tmp, "latin.csv", latin.encode("latin-1"))
    prof = dp.profile_dataset(path)
    assert prof["quality"] == "watch", prof
    assert _codes(prof)["text_encoding_legacy"]["params"] == {"encoding": "windows-1252"}, prof["findings"]
    assert prof["sampleRows"][0] == ["José", "Málaga", "1"], prof["sampleRows"]
    page = dp.read_rows(path)
    assert page["rows"][1] == ["François", "Besançon", "2"] and page["encoding"] == "windows-1252", page
    gb = "基因,样本,值\nTP53,肿瘤,1\nEGFR,正常,2\nKRAS,肿瘤,3\n"
    path = _w(tmp, "gbk.csv", gb.encode("gb18030"))
    prof = dp.profile_dataset(path)
    assert prof["columns"] == ["基因", "样本", "值"] and prof["viewKind"] == "table", prof
    assert _codes(prof)["text_encoding_legacy"]["params"] == {"encoding": "gb18030"}, prof["findings"]
    assert dp.read_rows(path)["encoding"] == "gb18030"


def test_new8_damaged_utf8_is_counted_not_rated_good(tmp):
    body = "gene,note\n" + "".join(f"G{i},naïve café\n" for i in range(50))
    path = _w(tmp, "damaged.csv", body.encode() + b"G99,bad\xff\xfebyte\n")
    prof = dp.profile_dataset(path)
    assert prof["quality"] == "watch", prof
    assert _codes(prof)["text_encoding_replaced"]["params"] == {"count": 2}, prof["findings"]
    assert "text_encoding_legacy" not in _codes(prof)
    assert dp.read_rows(path)["encoding"] == "utf-8"


def test_new8_duplicate_column_names_are_a_watch_finding(tmp):
    prof = dp.profile_dataset(_w(tmp, "dup.csv", "a,a,b\n1,2,3\n4,5,6\n7,8,9\n"))
    f = _codes(prof)["duplicate_column_names"]
    assert f["level"] == "watch" and f["params"] == {"count": 1, "columns": ["a"]} and prof["quality"] == "watch", prof


# ---------------------------------------------------------------------------
# R10 — decimal comma in semicolon-separated files
# ---------------------------------------------------------------------------
def test_r10_decimal_comma_numbers_are_numeric(tmp):
    # A continuous decimal-comma "target" is a measurement, not 12 class labels.
    rows = "".join(f"s{i};{i % 4},{i};{'ab'[i % 2]}\n" for i in range(12))
    path = _w(tmp, "score.csv", "sample;target;grp\n" + rows)
    prof = dp.profile_dataset(path)
    assert not prof.get("classBalance") and "table_clean" not in _codes(prof), prof
    assert prof["decimal"] == "," and dp.read_rows(path)["decimal"] == ",", prof
    # Headerless semicolon file whose commas are decimal marks: split on ';', not ','.
    path = _w(tmp, "nohdr.csv", "x;1,5;2,25\ny;3,1;4,75\nz;5,0;6,5\nw;7,0;8,5\n")
    page = dp.read_rows(path)
    assert page["delimiter"] == ";" and page["rows"][0] == ["x", "1,5", "2,25"], page
    # A comma CSV keeps "." as its decimal mark.
    assert dp.read_rows(_w(tmp, "dot.csv", "a,b\n1.5,2\n3.5,4\n"))["decimal"] == "."


# ---------------------------------------------------------------------------
# read_rows contract — the exact delimiter
# ---------------------------------------------------------------------------
def test_read_rows_returns_the_delimiter(tmp):
    cases = {"t.tsv": ("a\tb\n1\t2\n3\t4\n", "\t"), "c.csv": ("a,b\n1,2\n3,4\n", ","),
             "s.csv": ("a;b\nx;2\ny;4\n", ";"), "p.txt": ("a|b\nx|2\ny|4\n", "|"),
             "m.smi": ("CCO ethanol\nCCN ethylamine\n", " "),
             "r.bed": ("chr1\t1\t5\nchr1\t9\t12\n", "\t")}
    for name, (text, delim) in cases.items():
        page = dp.read_rows(_w(tmp, name, text))
        assert page["tabular"] is True and page["delimiter"] == delim, (name, page)
    page = dp.read_rows(_w(tmp, "j.jsonl", '{"a":1}\n{"a":2}\n'))
    assert "delimiter" in page and page["delimiter"] is None, page


# ---------------------------------------------------------------------------
# Copy — ONE English template table, equal to the en locale
# ---------------------------------------------------------------------------
# Codes whose en wording the backend changed this round (the client's locale adopts it).
# Backend English and the en locale are one wording (2026-11-12 round 3b): no exemptions.
_BACKEND_AHEAD_OF_LOCALE = frozenset()


def _en_locale():
    rel = "frontend/client/src/locales/en/common.json"
    root = os.path.abspath(os.path.join(_HERE, "..", "..", "..", "..", ".."))
    path = os.path.join(root, rel)
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)["perception"]["msg"]
    out = subprocess.run(["git", "-C", root, "show", f"HEAD:{rel}"], capture_output=True, text=True, check=True)
    return json.loads(out.stdout)["perception"]["msg"]


def test_copy_one_template_table_equal_to_the_en_locale():
    src = inspect.getsource(dp)
    assert "_EN_TEXT.update(" not in src and src.count("_EN_TEXT: Dict[str, str] = {") == 1
    assert dp.finding_text("split_overlap", {"count": 3}) == \
        "Feature rows that appear in more than one split: 3 — train/test overlap."
    locale = _en_locale()
    differ = sorted(k for k, v in dp._EN_TEXT.items()
                    if k in locale and locale[k] != v and k not in _BACKEND_AHEAD_OF_LOCALE)
    assert not differ, differ
    assert not any("(s)" in v for v in dp._EN_TEXT.values())


# ---------------------------------------------------------------------------
# order_key for an alignment that is not coordinate-sorted
# ---------------------------------------------------------------------------
def test_alignment_order_key():
    for so, key in (("queryname", "queryname"), ("unsorted", "unsorted"), ("unknown", "unknown"),
                    ("by-tag", "unknown")):
        p = dp.DataProfile()
        dp._galaxy_meta_findings(p, "bam", {"reference_count": 1, "sort_order": so}, "BAM")
        f = _codes({"findings": p.findings})["alignment_not_coordinate_sorted"]
        assert f["params"]["order_key"] == key and f["params"]["order"] == so and f["params"]["order_words"], f


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
    print(f"\n{len(tests) - failed}/{len(tests)} round-2 dataset-audit tests passed.")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
