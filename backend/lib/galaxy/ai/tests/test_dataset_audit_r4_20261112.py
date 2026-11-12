"""
Behavioural tests for the ROUND-4 audit of the dataset profiler (live dev walkthrough on
aefa622172, 2026-11-12):

* N2 — a folder holding ONE format ("top/mageck_count/" with one MAGeCK counts file) was
  "Mixed formats": the kind is now decided from the roll-up (single_format + kindFormat).
* N3 — fake.png holding text: "it is shown and checked as Text" next to "Identified as Text
  (20 B); its contents are not analysed here". One note now, and the generic text label.
* N4 — a 6-record JSON Lines file rated Watch only for per-file metadata columns (source, drug):
  near-constant raises Watch only from NEAR_CONSTANT_MIN_ROWS rows, and never for per-record
  provenance of a record file.
* N5 — duplicate facts: the mtx signal repeated the rows/columns/entries stats; the BAM signal
  repeated the reference-count stat (with "0 bp in total" when the header has no lengths); an xlsx
  whose first rows ARE previewed said "the data values themselves have not been analysed".
* N6 — columnStats roles: genomic coordinate columns of BED-like / featureCounts-like tables are
  ``annotation``; numeric value (count) columns are ``measurement``.

Every test fails on the profiler at aefa622172. Deterministic, no network. To run against another
copy of the modules (e.g. the old code), point BM_AI_DIR at its galaxy/ai folder.

Run standalone (no pytest needed):
    cd backend && python3.9 lib/galaxy/ai/tests/test_dataset_audit_r4_20261112.py
"""
from __future__ import annotations

import importlib.util
import inspect
import json
import os
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


dp = _load("_dp_audit_r4_under_test", "data_perception.py")
fp = _load("_fp_audit_r4_under_test", "folder_profile.py")
gf = _load("_gf_audit_r4_under_test", "galaxy_formats.py")

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


def _once(prof):
    """Each fact once: no finding code appears twice in a profile."""
    codes = [f["code"] for f in prof["findings"]]
    dupes = sorted({c for c in codes if codes.count(c) > 1})
    assert not dupes, (dupes, prof["findings"])


def _has(mod: str) -> bool:
    try:
        __import__(mod)
        return True
    except Exception:  # noqa: BLE001
        return False


# ---------------------------------------------------------------------------
# N2 — folder kind from the roll-up
# ---------------------------------------------------------------------------
_MAGECK = "top/mageck_count/screen_day14_sgrna_counts.count.txt"
_MAGECK_DECISION = {_MAGECK: {"ext": "tsv", "label": "MAGeCK counts", "viewKind": "table"}}


def test_n2_one_file_folder_is_its_format_not_mixed():
    for folder in ("top", "top/mageck_count"):
        out = fp.profile_folder(folder, [_MAGECK], decisions=_MAGECK_DECISION)
        assert out["kind"] == "single_format", (folder, out["kind"])
        assert out["kindFormat"] == {"format": "tsv", "label": "MAGeCK counts", "viewKind": "table"}, out
        assert out["rollup"] == [{"format": "tsv", "label": "MAGeCK counts", "count": 1, "viewKind": "table"}], out


def test_n2_three_same_format_files_and_the_mixed_boundary():
    out = fp.profile_folder("d", ["d/a.csv", "d/b.csv", "d/sub/c.csv"])
    assert out["kind"] == "single_format" and out["kindFormat"]["label"] == "CSV", out
    assert out["rollup"][0]["count"] == 3, out["rollup"]
    # Two formats → mixed (and no kindFormat).
    out = fp.profile_folder("d", ["d/a.csv", "d/b.csv", "d/notes.json"])
    assert out["kind"] == "mixed" and "kindFormat" not in out, out
    # Same extension, two labels the file panel shows (TSV vs featureCounts) → mixed too.
    out = fp.profile_folder("d", ["d/a.tsv", "d/fc.txt"], decisions={
        "d/a.tsv": {"ext": "tsv", "label": "TSV", "viewKind": "table"},
        "d/fc.txt": {"ext": "tsv", "label": "featureCounts counts", "viewKind": "table"}})
    assert out["kind"] == "mixed", out
    # Nothing identified: not "Mixed formats" either.
    out = fp.profile_folder("u", ["u/blob", "u/x.weird"])
    assert out["kind"] == "unrecognised" and "kindFormat" not in out, out
    # The specific kinds are unchanged.
    assert fp.profile_folder("p", ["p/S1_R1.fastq.gz", "p/S1_R2.fastq.gz"])["kind"] == "fastq_set"


# ---------------------------------------------------------------------------
# N3 — text under a media name: one consistent note
# ---------------------------------------------------------------------------
def test_n3_text_named_png_has_one_note(tmp):
    prof = dp.profile_dataset(_w(tmp, "fake.png", "this is not a PNG!!\n"), name="fake.png")
    assert [f["code"] for f in prof["findings"]] == ["name_content_mismatch"], prof["findings"]
    assert prof["viewKind"] == "document" and prof["quality"] == "watch", prof
    # The generic text label: Galaxy's "txt" label, one constant (not BioMate's list-table label).
    assert prof["format"]["label"] == gf.label_for("txt") == getattr(dp, "_TEXT_LABEL", None) == "Text", prof["format"]
    assert prof["findings"][0]["params"] == {"named": "PNG", "detected": "Text"}, prof["findings"][0]
    # A text document under its own name still says what it is (nothing contradicts it).
    prof = dp.profile_dataset(_w(tmp, "notes.md", "# Notes\nsome text\n"), name="notes.md")
    assert "format_identified" in _codes(prof) and "name_content_mismatch" not in _codes(prof), prof["findings"]


# ---------------------------------------------------------------------------
# N4 — near-constant: row floor + per-record provenance of record files
# ---------------------------------------------------------------------------
def _jsonl(n, extra=lambda i: {}):
    return "".join(json.dumps(dict({"source": "epar_table", "drug": "pluvicto", "page": 30 + i,
                                    "value": (i * 37) % 11}, **extra(i))) + "\n" for i in range(n))


def test_n4_small_record_file_is_not_watch_for_metadata_columns(tmp):
    prof = dp.profile_dataset(_w(tmp, "epar_study_tables.jsonl", _jsonl(6)))
    by = _codes(prof)
    assert prof["quality"] != "watch", prof["findings"]
    nc = by["constant_columns"]
    assert nc["level"] == "info" and nc["params"]["expected"] == "few_rows", nc
    assert nc["columns"] == ["source", "drug"], nc
    assert "table_clean_unlabelled" not in by, prof["findings"]  # it would say "no constant column"
    _once(prof)


def test_n4_large_record_file_provenance_is_expected(tmp):
    prof = dp.profile_dataset(_w(tmp, "records.jsonl", _jsonl(40)))
    nc = _codes(prof)["constant_columns"]
    assert prof["quality"] == "good", prof["findings"]
    assert nc["level"] == "info" and nc["params"]["expected"] == "record_metadata" and nc["columns"] == ["source", "drug"], nc
    # A data column that is near-constant in a large record file is still Watch (and the
    # provenance columns are not listed beside it).
    prof = dp.profile_dataset(_w(tmp, "records2.jsonl", _jsonl(150, lambda i: {"flag": "x" if i else "y"})))
    nc = _codes(prof)["near_constant"]
    assert prof["quality"] == "watch" and nc["level"] == "watch" and nc["columns"] == ["flag"], nc
    _once(prof)


def test_n4_tables_below_the_row_floor_and_above_it(tmp):
    rows = ["sample,batch,value"] + [f"S{i},b1,{i * 3}" for i in range(6)]
    prof = dp.profile_dataset(_w(tmp, "small.csv", "\n".join(rows) + "\n"))
    nc = _codes(prof)["constant_columns"]
    assert prof["quality"] == "good" and nc["level"] == "info" and nc["params"]["expected"] == "few_rows", prof["findings"]
    rows = ["sample,batch,value"] + [f"S{i},b1,{i * 3}" for i in range(dp.NEAR_CONSTANT_MIN_ROWS)]
    prof = dp.profile_dataset(_w(tmp, "big.csv", "\n".join(rows) + "\n"))
    nc = _codes(prof)["constant_columns"]
    assert prof["quality"] == "watch" and nc["level"] == "watch" and "expected" not in nc["params"], prof["findings"]


# ---------------------------------------------------------------------------
# N5 — each fact once
# ---------------------------------------------------------------------------
def test_n5_mtx_signal_does_not_repeat_the_stats(tmp):
    mtx = "%%MatrixMarket matrix coordinate integer general\n4 5 8\n" + "".join(
        f"{1 + i % 4} {1 + i % 5} {i + 1}\n" for i in range(8))
    prof = dp.profile_dataset(_w(tmp, "matrix.mtx", mtx))
    stats = {s["code"]: s["value"] for s in prof["stats"]}
    assert stats == {"rows": 4, "columns": 5, "entries": 8}, prof["stats"]
    f = _codes(prof)["mtx_dimensions"]
    text = dp.finding_text("mtx_dimensions", f["params"])
    assert "×" not in text and " 8" not in text and "40" in text and "integer" in text, text
    assert f["params"]["rows"] == 4 and f["params"]["nnz"] == 8, f  # params keep the numbers
    assert "×" not in dp.finding_text("mtx_dense", {"rows": 3, "cols": 3, "field": "real"})
    _once(prof)


def test_n5_bam_reference_count_is_stated_once():
    p = dp.DataProfile()
    dp._galaxy_meta_findings(p, "bam", {"reference_count": 168, "reference_total_length": 0,
                                        "sort_order": "coordinate", "read_group_count": 0}, "BAM")
    codes = [f["code"] for f in p.findings]
    assert p.stats_map["references"] == 168 and "alignment_references" not in codes, p.findings
    assert codes.count("alignment_no_read_groups") == 1, codes
    p = dp.DataProfile()
    dp._galaxy_meta_findings(p, "bam", {"reference_count": 2, "reference_total_length": 3000,
                                        "sort_order": "coordinate"}, "BAM")
    f = [x for x in p.findings if x["code"] == "alignment_references"]
    assert len(f) == 1, p.findings
    text = dp.finding_text("alignment_references", f[0]["params"])
    assert "3,000" in text and " 2 " not in text and "(" not in text, text


def test_n5_xlsx_with_a_preview_does_not_claim_values_were_not_read(tmp):
    meta = {"sheets": [{"name": "data", "rows": 3, "cols": 2}],
            "preview": {"sheet": "data", "rows": [["sample", "value"], ["S1", "1"], ["S2", "2"]]}}
    orig = dp._galaxy_metadata
    dp._galaxy_metadata = lambda path, ext: meta
    try:
        p = dp._profile_galaxy_format(_w(tmp, "s.xlsx", b"PK\x03\x04stub"), "xlsx", 10, "Excel (xlsx)")
    finally:
        dp._galaxy_metadata = orig
    codes = [f["code"] for f in p.findings]
    assert p.sample_rows and "spreadsheet_preview" in codes, codes
    assert "format_metadata_only" not in codes and "format_identified" not in codes, codes
    # Without a preview the metadata-only note stays true and is kept.
    meta = {"sheets": [{"name": "data", "rows": 3, "cols": 2}]}
    dp._galaxy_metadata = lambda path, ext: meta
    try:
        p = dp._profile_galaxy_format(_w(tmp, "t.xlsx", b"PK\x03\x04stub"), "xlsx", 10, "Excel (xlsx)")
    finally:
        dp._galaxy_metadata = orig
    assert "format_metadata_only" in [f["code"] for f in p.findings], p.findings


def test_n5_real_xlsx_preview(tmp):
    if not _has("openpyxl"):
        print("SKIP test_n5_real_xlsx_preview (no openpyxl)")
        return
    import openpyxl

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "data"
    for r in [["sample", "value"]] + [[f"S{i}", i] for i in range(5)]:
        ws.append(r)
    path = os.path.join(tmp, "samples.xlsx")
    wb.save(path)
    prof = dp.profile_dataset(path)
    assert prof["sampleRows"], prof
    assert "format_metadata_only" not in _codes(prof), prof["findings"]
    _once(prof)


# ---------------------------------------------------------------------------
# N6 — coordinate columns are annotation, value columns are measurement
# ---------------------------------------------------------------------------
def _roles(prof):
    return {c["name"]: c.get("role") for c in prof["columnStats"]}


def test_n6_featurecounts_roles(tmp):
    rows = ["# Program:featureCounts v2.0.1", "Geneid\tChr\tStart\tEnd\tStrand\tLength\tS1.bam\tS2.bam"] + [
        f"G{i}\tchr1\t{1 + i * 1000}\t{800 + i * 1000}\t+\t800\t{(i * 37) % 400}\t{(i * 53) % 500}" for i in range(15)]
    roles = _roles(dp.profile_dataset(_w(tmp, "featurecounts.txt", "\n".join(rows) + "\n")))
    assert all(roles[c] == "annotation" for c in ("Geneid", "Chr", "Start", "End", "Strand", "Length")), roles
    assert roles["S1.bam"] == roles["S2.bam"] == "measurement", roles


def test_n6_bed_like_table_roles(tmp):
    # A CSV with BED-like columns — not a recognised layout, not a spec file.
    rows = ["chrom,start,end,strand,length,score,gene"] + [
        f"chr{1 + i % 3},{i * 100},{i * 100 + 50 + i},{'+-'[i % 2]},{50 + i},{(i * 7) % 13},g{i}" for i in range(25)]
    roles = _roles(dp.profile_dataset(_w(tmp, "peaks_table.csv", "\n".join(rows) + "\n")))
    assert all(roles[c] == "annotation" for c in ("chrom", "start", "end", "strand", "length")), roles
    assert roles["score"] == "measurement" and roles["gene"] != "annotation", roles
    # Without a chromosome column, "length" / "end" are ordinary values.
    rows = ["length,end,weight"] + [f"{i + 1},{i * 2},{i * 0.5}" for i in range(25)]
    roles = _roles(dp.profile_dataset(_w(tmp, "body.csv", "\n".join(rows) + "\n")))
    assert set(roles.values()) == {"measurement"}, roles


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
    print(f"\n{len(tests) - failed}/{len(tests)} round-4 dataset-audit tests passed.")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
