"""
Unit tests for the rules-first data-perception profiler.

Deterministic, no LLM, no network. Small synthetic datasets written to a tmp
dir; each asserts a specific DataProfile field the frontend consumes.

Run standalone (no pytest needed):
    PYTHONPATH=backend/lib python3.9 backend/lib/galaxy/ai/tests/test_data_perception.py
"""
from __future__ import annotations

import importlib.util
import os
import sys
import tempfile

# Load the profiler module DIRECTLY by file path, without importing the
# galaxy.ai package (whose __init__ pulls heavy ML deps like torch /
# sentence_transformers that aren't needed for the numeric profiler).
_HERE = os.path.dirname(os.path.abspath(__file__))
_MOD_PATH = os.path.abspath(os.path.join(_HERE, "..", "data_perception.py"))
_spec = importlib.util.spec_from_file_location("_data_perception_under_test", _MOD_PATH)
_mod = importlib.util.module_from_spec(_spec)
# Register before exec so dataclass field-type resolution (with
# `from __future__ import annotations`) can find the module in sys.modules.
sys.modules["_data_perception_under_test"] = _mod
_spec.loader.exec_module(_mod)  # type: ignore[union-attr]
profile_dataset = _mod.profile_dataset
profile_to_dataclass = _mod.profile_to_dataclass


# Each test takes a `tmp` directory. When run under pytest this is provided by
# the fixture below; when run standalone via ``main()`` it is a tempfile dir.
# (pytest has no builtin fixture named ``tmp`` — only ``tmp_path`` — so define
# one so the same test bodies work in both run modes.)
try:
    import pytest

    @pytest.fixture
    def tmp():
        with tempfile.TemporaryDirectory() as d:
            yield d
except ImportError:  # pytest not installed — standalone main() supplies tmp.
    pass


def _write(tmp, name, content):
    path = os.path.join(tmp, name)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    return path


# ---------------------------------------------------------------------------
# 1. Clean table -> good, class balance, effective N == rows, no leakage.
# ---------------------------------------------------------------------------
def test_clean_table_good(tmp):
    header = "feat1,feat2,feat3,label"
    lines = [header]
    for i in range(50):
        # two clean groups, no single feature reveals the label
        lbl = "control" if i % 2 == 0 else "treated"
        lines.append(f"{i*3 % 7},{(i*5) % 11},{(i*2) % 13},{lbl}")
    path = _write(tmp, "clean.csv", "\n".join(lines) + "\n")

    prof = profile_dataset(path)
    assert prof["quality"] == "good", prof
    assert prof["shape"] == {"rows": 50, "cols": 4}, prof
    assert "leakage" not in prof, prof
    labels = {c["label"] for c in prof["classBalance"]}
    assert labels == {"control", "treated"}, prof
    assert abs(prof["classBalance"][0]["frac"] - 0.5) < 1e-6, prof
    assert prof["effectiveN"] == 50, prof
    print("PASS test_clean_table_good")


# ---------------------------------------------------------------------------
# 2a. Target leaked into a feature -> watch + leakage detail.
# ---------------------------------------------------------------------------
def test_leaky_feature(tmp):
    header = "feat1,leaky,label"
    lines = [header]
    for i in range(40):
        lbl = "pos" if i % 2 == 0 else "neg"
        # 'leaky' encodes the label directly
        lines.append(f"{i % 5},{1 if lbl == 'pos' else 0},{lbl}")
    path = _write(tmp, "leaky.csv", "\n".join(lines) + "\n")

    prof = profile_dataset(path)
    assert prof["quality"] == "watch", prof
    assert "leakage" in prof, prof
    assert "leaky" in prof["leakage"]["detail"], prof
    # The plan tells you to keep the group-revealing column out of a model (wording 2026-11-12:
    # "leave “leaky” out of any model that predicts the group").
    assert any("leaky" in pi["effect"] and "out of" in pi["effect"] for pi in prof["planImpact"]), prof
    print("PASS test_leaky_feature")


# ---------------------------------------------------------------------------
# 2b. Batch<->label confound -> watch + leakage detail + covariate plan impact.
# ---------------------------------------------------------------------------
def test_batch_label_confound(tmp):
    header = "gene_a,gene_b,batch,outcome"
    lines = [header]
    # batch B1 is all responders, batch B2 is all non-responders -> confound
    for i in range(30):
        batch = "B1" if i < 15 else "B2"
        out = "responder" if batch == "B1" else "nonresponder"
        lines.append(f"{i*7 % 3},{i*11 % 5},{batch},{out}")
    path = _write(tmp, "batch.csv", "\n".join(lines) + "\n")

    prof = profile_dataset(path)
    assert prof["quality"] == "watch", prof
    assert "leakage" in prof, prof
    assert "batch" in prof["leakage"]["detail"].lower(), prof
    assert any("covariate" in pi["effect"] for pi in prof["planImpact"]), prof
    print("PASS test_batch_label_confound")


# ---------------------------------------------------------------------------
# 3. Imbalanced -> classBalance minority + low effective N.
# ---------------------------------------------------------------------------
def test_imbalanced_low_effective_n(tmp):
    header = "x1,x2,label"
    lines = [header]
    # 300 rows: 21 responder (7%), 279 non-responder (93%)
    for i in range(300):
        lbl = "responder" if i < 21 else "nonresponder"
        lines.append(f"{i % 17},{(i * 3) % 29},{lbl}")
    path = _write(tmp, "imbalanced.csv", "\n".join(lines) + "\n")

    prof = profile_dataset(path)
    balance = {c["label"]: c["frac"] for c in prof["classBalance"]}
    assert abs(balance["responder"] - 0.07) < 0.01, prof
    # effective N bounded by minority class: k(=2) * 21 = 42, well below 300
    assert prof["effectiveN"] is not None and prof["effectiveN"] < 100, prof
    assert prof["quality"] == "watch", prof
    assert any("class is 7%" in n or "7%" in n for n in prof["notes"]), prof
    print("PASS test_imbalanced_low_effective_n")


# ---------------------------------------------------------------------------
# 4. Near-constant / high-missing columns -> signalSummary + watch.
# ---------------------------------------------------------------------------
def test_constant_and_missing_columns(tmp):
    header = "const_col,miss_col,feat,label"
    lines = [header]
    for i in range(40):
        lbl = "a" if i % 2 == 0 else "b"
        miss = "" if i % 2 == 0 else "1"  # 50% missing
        lines.append(f"CONST,{miss},{i % 7},{lbl}")
    path = _write(tmp, "signals.csv", "\n".join(lines) + "\n")

    prof = profile_dataset(path)
    assert prof["quality"] == "watch", prof
    sig = " ".join(prof["signalSummary"]).lower()
    assert "near-constant" in sig, prof
    assert "missing" in sig, prof
    print("PASS test_constant_and_missing_columns")


# ---------------------------------------------------------------------------
# 5. FASTQ -> reads shape + single-end note + plan impact.
# ---------------------------------------------------------------------------
def test_fastq_profile(tmp):
    recs = []
    for i in range(10):
        recs.append(f"@read{i}\nACGTACGTAC\n+\nIIIIIIIIII")  # Phred 'I' = 40
    path = _write(tmp, "sample.fastq", "\n".join(recs) + "\n")

    prof = profile_dataset(path)
    assert prof["shape"]["rows"] == 10, prof
    assert prof["shape"]["cols"] == 10, prof  # mean read length
    assert any("single-end" in n.lower() for n in prof["notes"]), prof
    assert any("single-end" in pi["effect"].lower() for pi in prof["planImpact"]), prof
    assert prof["quality"] == "good", prof
    print("PASS test_fastq_profile")


# ---------------------------------------------------------------------------
# 6. VCF -> variant count + sample count.
# ---------------------------------------------------------------------------
def test_vcf_profile(tmp):
    content = (
        "##fileformat=VCFv4.2\n"
        "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tS1\tS2\n"
        "chr1\t100\t.\tA\tT\t50\tPASS\t.\tGT\t0/1\t1/1\n"
        "chr1\t200\t.\tG\tC\t60\tPASS\t.\tGT\t0/0\t0/1\n"
        "chr2\t300\t.\tT\tA\t70\tPASS\t.\tGT\t1/1\t0/1\n"
    )
    path = _write(tmp, "variants.vcf", content)

    prof = profile_dataset(path)
    assert prof["shape"]["rows"] == 3, prof
    assert prof["shape"]["cols"] == 2, prof  # two samples
    assert any("variant" in n.lower() for n in prof["notes"]), prof
    print("PASS test_vcf_profile")


# ---------------------------------------------------------------------------
# 7. Malformed / empty -> blocked, honest note, no fabricated fields.
# ---------------------------------------------------------------------------
def test_blocked_empty_and_missing(tmp):
    # header only, 0 data rows: a readable (empty) table, NOT "cannot read".
    # The header columns must be surfaced so the stat grid shows cols>0, rows=0
    # instead of "—"/blocked, with an honest note and no fabricated analysis.
    path = _write(tmp, "headeronly.csv", "a,b,label\n")
    prof = profile_dataset(path)
    assert prof["quality"] != "blocked", prof
    assert prof.get("shape", {}).get("cols") == 3, prof
    assert prof.get("shape", {}).get("rows") == 0, prof
    assert prof.get("columns") == ["a", "b", "label"], prof
    assert "leakage" not in prof and "classBalance" not in prof, prof

    # missing file still blocks (a real failure, not an empty table)
    prof2 = profile_dataset(os.path.join(tmp, "does_not_exist.csv"))
    assert prof2["quality"] == "blocked", prof2
    print("PASS test_blocked_empty_and_missing")


# ---------------------------------------------------------------------------
# 8. train/test overlap via a split column -> leakage detail.
# ---------------------------------------------------------------------------
def test_train_test_overlap(tmp):
    header = "f1,f2,split,label"
    lines = [header]
    # identical feature-rows in both train and test
    for split in ("train", "test"):
        for i in range(10):
            lbl = "a" if i % 2 == 0 else "b"
            lines.append(f"{i},{i*2},{split},{lbl}")
    path = _write(tmp, "overlap.csv", "\n".join(lines) + "\n")

    prof = profile_dataset(path)
    assert "leakage" in prof, prof
    assert "split" in prof["leakage"]["detail"].lower() or "overlap" in prof["leakage"]["detail"].lower(), prof
    print("PASS test_train_test_overlap")


# ---------------------------------------------------------------------------
# 9. Unknown file type -> watch + honest note, shape only.
# ---------------------------------------------------------------------------
def test_unknown_type_degrades(tmp):
    path = _write(tmp, "mystery.xyz", "some binary-ish text\nwith no delimiter\n")
    prof = profile_to_dataclass(path).to_dict()
    # Identified (plain text) but not analysed: "unassessed", never "good" and never a fake "watch".
    assert prof["quality"] == "unassessed" and prof["viewKind"] == "document", prof
    assert "leakage" not in prof and "classBalance" not in prof, prof
    print("PASS test_unknown_type_degrades")


def test_structured_json_and_yaml(tmp):
    for suffix, text in (("json", '{"samples": [{"id": "A", "value": null}, {"id": "B", "value": 2}]}'),
                         ("yml", "samples:\n  - id: A\n    value: null\n  - id: B\n    value: 2\n")):
        p = profile_dataset(_write(tmp, "structured." + suffix, text))
        assert p["structured"]["keys"] == 5, p
        assert p["structured"]["nulls"] == 1, p
        assert p["structured"]["depth"] == 3, p
        assert "columns" not in p and "effectiveN" not in p, p
    print("PASS test_structured_json_and_yaml")


def test_invalid_structured_file(tmp):
    # Invalid JSON is not JSON: the content (text) decides, and the name/content contradiction is a finding.
    p = profile_dataset(_write(tmp, "invalid.json", '{"bad": }'))
    assert p["format"]["ext"] != "json" and p["viewKind"] == "document", p
    assert p["findings"][0]["code"] == "name_content_mismatch" and p["quality"] == "watch", p
    assert p["findings"][0]["params"] == {"named": "JSON", "detected": "Text"}, p["findings"][0]
    # Nearly any text is YAML syntax-wise, so a YAML parse error is a blocked profile — with a reason
    # in words, never the parser's raw message.
    p = profile_dataset(_write(tmp, "invalid.yaml", "bad: ["))
    assert p["quality"] == "blocked" and p["findings"][0]["code"] == "parse_failed", p
    assert p["findings"][0]["params"]["error"] == "the YAML is not valid", p
    print("PASS test_invalid_structured_file")


def test_yaml_recursive_alias(tmp):
    p = profile_dataset(_write(tmp, "recursive.yml", "loop: &loop [*loop]"))
    assert p["structured"]["nodes"] == 3, p
    print("PASS test_yaml_recursive_alias")


# ---------------------------------------------------------------------------
# JSON Lines -> one row per record (was profiled as CSV: every line split on commas,
# columns like '{"source": "epar_table"'; EPAR dataset test 2026-11-10).
# ---------------------------------------------------------------------------
def test_jsonl_records_not_csv(tmp):
    import json as _json
    lines = [
        {"source": "epar_table", "drug": f"d{i}", "page": i, "headers": ["A, B", ""], "rows": [["x", "y"]]}
        for i in range(30)
    ]
    for name in ("t.jsonl", "t_noext"):  # by extension, and by content sniff
        path = _write(tmp, name, "\n".join(_json.dumps(r) for r in lines) + "\n")
        p = profile_to_dataclass(path)
        assert p.rows == 30, (name, p.rows)
        assert p.cols == 5, (name, p.cols)
        assert p.columns == ["source", "drug", "page", "headers", "rows"], p.columns
        assert p.sample_rows[0][3] == '["A, B",""]', p.sample_rows[0][3]
        # 'source' is constant: flagged, and the note must not also claim "no constant-column issues".
        assert any("near-constant" in s.lower() for s in (p.signal_summary or [])), p.signal_summary
        assert not any("constant-column issues detected" in n for n in p.notes), p.notes
    print("PASS test_jsonl_records_not_csv")


# ---------------------------------------------------------------------------
# Effective-N reason + structured (localizable) findings — Data panel fixes
# 2026-11-10 (docs/20261110_DATA_PANEL_FIXES.md). The card said "correlation /
# imbalance discounted it" even when the only reduction was duplicate rows.
# ---------------------------------------------------------------------------
def test_effective_n_reason_dedup_without_label(tmp):
    # Round 3 (2026-11-12, W7): effective N is a MODELLING notion, reported only with a confident
    # label; an unlabelled table reports its duplicate rows instead (duplicateRows + a finding).
    rows = ["a,b"] + [f"{i},{i * 2}" for i in range(40)] + ["1,2"] * 10  # 10 exact duplicates
    path = _write(tmp, "dups.csv", "\n".join(rows) + "\n")
    p = profile_dataset(path)
    assert "effectiveN" not in p and "label" not in p, p
    assert p["duplicateRows"] == 10, p
    assert [f["params"] for f in p["findings"] if f["code"] == "duplicate_rows"] == [{"count": 10}], p["findings"]
    print("PASS test_effective_n_reason_dedup_without_label")


def test_effective_n_reason_imbalance(tmp):
    rows = ["f1,label"] + [f"{i},neg" for i in range(279)] + [f"{1000 + i},pos" for i in range(21)]
    path = _write(tmp, "imb.csv", "\n".join(rows) + "\n")
    p = profile_dataset(path)
    assert p["effectiveNReason"] == "imbalance", p
    assert p["effectiveN"] == 42, p
    codes = {f["code"]: f for f in p["findings"]}
    assert codes["effective_n_imbalance"]["level"] == "watch", codes
    assert codes["minority_class"]["params"] == {"label": "pos", "pct": 7}, codes
    assert p["quality"] == "watch"
    print("PASS test_effective_n_reason_imbalance")


def test_effective_n_reason_dedup_with_label(tmp):
    # Balanced labels, but most rows are duplicates -> dedup binds, not imbalance.
    rows = ["f1,label"] + ["1,a", "2,b"] * 50
    path = _write(tmp, "dup_lbl.csv", "\n".join(rows) + "\n")
    p = profile_dataset(path)
    assert p["effectiveN"] == 2 and p["effectiveNReason"] == "dedup", p
    assert any(f["code"] == "effective_n_dedup" and f["params"]["duplicates"] == 98 for f in p["findings"]), p
    print("PASS test_effective_n_reason_dedup_with_label")


def test_watch_findings_name_their_columns(tmp):
    # The verdict must be explainable: every watch-level finding carries its code + the columns.
    rows = ["id,constant,mostly_empty"] + [f"{i},x," for i in range(30)]
    path = _write(tmp, "w.csv", "\n".join(rows) + "\n")
    p = profile_dataset(path)
    assert p["quality"] == "watch", p
    watch = [f for f in p["findings"] if f["level"] == "watch"]
    by = {f["code"]: f["params"] for f in watch}
    assert by["near_constant"]["columns"] == ["constant"], by
    assert by["high_missing"]["columns"] == ["mostly_empty"], by
    # Every legacy free-text line has a structured twin (so the UI never shows raw English).
    n_text = len(p["notes"]) + len(p.get("signalSummary", [])) + len(p["planImpact"])
    assert len(p["findings"]) == n_text, (p["findings"], p["notes"])
    print("PASS test_watch_findings_name_their_columns")


def test_blocked_profiles_carry_codes(tmp):
    p = profile_dataset(os.path.join(tmp, "nope.csv"))
    assert p["quality"] == "blocked" and p["findings"][0]["code"] == "file_not_found", p
    empty = _write(tmp, "empty.csv", "")
    assert profile_dataset(empty)["findings"][0]["code"] == "empty_file"
    print("PASS test_blocked_profiles_carry_codes")


def test_profiled_rows_reports_true_total(tmp):
    # Statistics hold at most max_rows rows, but the reported total is the TRUE count.
    path = _write(tmp, "big.csv", "a,b\n" + "".join(f"{i},{i}\n" for i in range(50)))
    header, rows, total = _mod._read_table(path, max_rows=10)
    assert (len(rows), total) == (10, 50), (len(rows), total)
    keys, jrows, jtotal = _mod._read_jsonl(
        _write(tmp, "big.jsonl", "".join('{"k": %d}\n' % i for i in range(50))), max_rows=7)
    assert (keys, len(jrows), jtotal) == (["k"], 7, 50)
    print("PASS test_profiled_rows_reports_true_total")


def test_read_rows_jsonl_matches_profiler(tmp):
    import json as _json
    recs = [{"source": "epar", "drug": f"d{i}", "page": i, "nested": {"x": [1, 2]}} for i in range(25)]
    recs[20]["late_key"] = True  # a key first seen late still becomes a column
    path = _write(tmp, "r.jsonl", "\n".join(_json.dumps(r) for r in recs) + "\nnot json\n")
    page = _mod.read_rows(path, offset=18, limit=5)
    assert page["kind"] == "jsonl" and page["tabular"] is True, page
    assert page["totalRows"] == 25, page
    assert page["columns"] == ["source", "drug", "page", "nested", "late_key"], page["columns"]
    assert [r[2] for r in page["rows"]] == ["18", "19", "20", "21", "22"], page["rows"]
    assert page["rows"][0][3] == '{"x":[1,2]}' and page["rows"][2][4] == "True", page["rows"]
    assert page["skippedLines"] == 1
    # Same cells as the profiler's reader for the same records.
    _, prof_rows, _ = _mod._read_jsonl(path)
    assert page["rows"] == prof_rows[18:23]
    # With known meta the read stops early but returns the identical page.
    known = {"columns": page["columns"], "totalRows": page["totalRows"]}
    assert _mod.read_rows(path, offset=18, limit=5, known=known)["rows"] == page["rows"]
    print("PASS test_read_rows_jsonl_matches_profiler")


def test_read_rows_csv_paging_and_non_tabular(tmp):
    path = _write(tmp, "c.csv", 'a,b\n1,"x, y"\n\n2,z\n3,w\n')
    page = _mod.read_rows(path, offset=1, limit=10)
    assert page["columns"] == ["a", "b"] and page["totalRows"] == 3, page
    assert page["rows"] == [["2", "z"], ["3", "w"]], page["rows"]
    assert _mod.read_rows(path, offset=0, limit=1)["rows"] == [["1", "x, y"]]
    assert _mod.read_rows(path, 0, 10**6)["limit"] == _mod.MAX_ROWS_PAGE
    fq = _write(tmp, "s.fastq", "@r1\nACGT\n+\nIIII\n")
    assert _mod.read_rows(fq)["tabular"] is False
    print("PASS test_read_rows_csv_paging_and_non_tabular")


# ---------------------------------------------------------------------------
# Nested tables in JSON Lines (epar_study_tables.jsonl, 2026-11-11): 69% of 2,281 extracted tables had
# exactly 7 rows because the extractor kept t[1:8]; the profile said nothing about the tables.
# ---------------------------------------------------------------------------
def test_jsonl_nested_tables_row_cap_and_blanks(tmp):
    import json as _json
    recs = []
    for i in range(40):
        n = 7 if i < 28 else 3 + (i % 4)          # 70% at the cap of 7 rows, the rest 3..6
        recs.append({"drug": f"d{i}", "headers": ["Study", "Dose", ""],
                     "rows": [["s%d" % r, "" if r % 2 else "10 mg", ""] for r in range(n)]})
    p = profile_dataset(_write(tmp, "tables.jsonl", "\n".join(_json.dumps(r) for r in recs) + "\n"))
    by = {f["code"]: f for f in p["findings"]}
    assert by["nested_tables"]["params"] == {"column": "rows", "tables": 40, "median_rows": 7,
                                             "median_cols": 3, "max_rows": 7}, by["nested_tables"]
    assert by["nested_row_cap"]["level"] == "watch" and by["nested_row_cap"]["params"]["pct"] == 70, by["nested_row_cap"]
    cells = [c for r in recs for row in r["rows"] for c in row]
    expect_pct = int(round(100 * sum(1 for c in cells if not c) / len(cells)))
    assert by["nested_blank_cells"]["params"]["pct"] == expect_pct, (by["nested_blank_cells"], expect_pct)
    assert p["quality"] == "watch"
    print("PASS test_jsonl_nested_tables_row_cap_and_blanks")


def test_jsonl_nested_tables_no_cap_when_sizes_vary(tmp):
    import json as _json
    recs = [{"rows": [["a", "b"]] * (2 + i % 9)} for i in range(40)]   # 2..10 rows, spread evenly
    p = profile_dataset(_write(tmp, "vary.jsonl", "\n".join(_json.dumps(r) for r in recs) + "\n"))
    codes = [f["code"] for f in p["findings"]]
    assert "nested_tables" in codes and "nested_row_cap" not in codes and "nested_blank_cells" not in codes, codes
    # Lists that are not tables (list of scalars) are not reported as tables.
    p2 = profile_dataset(_write(tmp, "tags.jsonl", "\n".join(_json.dumps({"tags": ["x", "y"]}) for _ in range(10)) + "\n"))
    assert not any(f["code"].startswith("nested_") for f in p2["findings"]), p2["findings"]
    print("PASS test_jsonl_nested_tables_no_cap_when_sizes_vary")


# ---------------------------------------------------------------------------
# Header inference (2026-11-11): line 1 is a header only when the content says so; spec formats
# (BED, narrowPeak, GTF, SMILES, …) have no header row and use their specification's names.
# ---------------------------------------------------------------------------
def test_header_inference_bed_and_peaks(tmp):
    bed = _write(tmp, "a.bed", "browser position chr1\ntrack name=x\nchr1\t100\t200\tA\t0\t+\nchr2\t300\t400\tB\t0\t-\n")
    page = _mod.read_rows(bed)
    assert page["columns"] == ["Chrom", "Start", "End", "Name", "Score", "Strand"], page
    assert page["headerRow"] is False and page["namesSource"] == "spec" and page["totalRows"] == 2, page
    assert page["rows"][0] == ["chr1", "100", "200", "A", "0", "+"], page["rows"]
    prof = profile_dataset(bed)
    codes = [f["code"] for f in prof["findings"]]
    assert "columns_spec" in codes and "classBalance" not in prof and "leakage" not in prof, prof
    assert prof["format"]["ext"] == "bed", prof["format"]
    # BED3 → only the first three spec names; a "#chrom start end" line whose width matches names the columns.
    b3 = _write(tmp, "b3.bed", "#chrom\tbeg\tfin\nchr1\t1\t5\n")
    page = _mod.read_rows(b3)
    assert page["columns"] == ["chrom", "beg", "fin"] and page["namesSource"] == "comment", page
    b3b = _write(tmp, "b3b.bed", "# made by tool v1\nchr1\t1\t5\n")
    assert _mod.read_rows(b3b)["columns"] == ["Chrom", "Start", "End"]
    np_ = _write(tmp, "p.narrowPeak", "chr1\t1\t100\tp1\t0\t.\t5.2\t3.1\t2.0\t50\n")
    page = _mod.read_rows(np_)
    assert page["columns"][-4:] == ["SignalValue", "pValue", "qValue", "Peak"] and page["totalRows"] == 1, page
    # A GFF3 ##FASTA section ends the feature table.
    gff = _write(tmp, "g.gff3", "##gff-version 3\nctg1\t.\tgene\t1\t90\t.\t+\t.\tID=g1\n##FASTA\n>ctg1\nACGT\n")
    page = _mod.read_rows(gff)
    assert page["totalRows"] == 1 and page["columns"][0] == "Seqid", page
    smi = _write(tmp, "s.smi", "CCO ethanol\nc1ccccc1 benzene\n")
    page = _mod.read_rows(smi)
    assert page["columns"] == ["SMILES", "TITLE"] and page["rows"][1] == ["c1ccccc1", "benzene"], page
    print("PASS test_header_inference_bed_and_peaks")


def test_header_inference_generic_tables(tmp):
    cases = [
        ("genes_h.txt", "gene\nTP53\nBRCA1\nEGFR\n", True, ["gene"]),
        ("genes_n.txt", "TP53\nBRCA1\nEGFR\n", False, ["column_1"]),
        ("genes_ws.txt", "Gene Symbol\nTP53\nBRCA1\n", True, ["Gene Symbol"]),
        ("nohead.csv", "1,2.5,x\n3,4.1,y\n5,6.2,z\n", False, ["column_1", "column_2", "column_3"]),
        ("normal.csv", "id,value,group\n1,2.5,x\n3,4.1,y\n", True, ["id", "value", "group"]),
        ("alltext.csv", "name,city\nann,paris\nbob,rome\n", True, ["name", "city"]),
        ("rnames.csv", ",s1,s2\ng1,1,2\ng2,3,4\n", True, ["", "s1", "s2"]),
        ("one_line.csv", "a,b,c\n", True, ["a", "b", "c"]),
    ]
    for name, text, header, cols in cases:
        path = _write(tmp, name, text)
        page = _mod.read_rows(path)
        assert page["headerRow"] is header and page["columns"] == cols, (name, page)
        prof = profile_dataset(path)
        assert prof["shape"]["cols"] == len(cols), (name, prof)
        codes = [f["code"] for f in prof["findings"]]
        assert ("columns_generated" in codes) == (not header), (name, codes)
        if not header:
            assert prof["shape"]["rows"] == text.count("\n"), (name, prof)    # line 1 is data
            assert any(c in codes for c in ("table_clean", "table_clean_unlabelled", "table_summary")), (name, codes)
    print("PASS test_header_inference_generic_tables")


def test_read_rows_spec_mismatch_is_not_tabular(tmp):
    # Named .bed / .gtf but not that format (binary, or lines without integer coordinates): not a
    # table — read_rows says tabular False (the client falls back to the text preview), never raises.
    with open(os.path.join(tmp, "bin.bed"), "wb") as f:
        f.write(b"\x00\x01\x02binary\tjunk\n\x00\x00\n")
    words = _write(tmp, "notes.gtf", "this is\ta note\nnot\tannotation\n")
    assert _mod.read_rows(os.path.join(tmp, "bin.bed"))["tabular"] is False
    # Two tab-separated text columns named .gtf: read as the TSV the content is, never as GTF.
    page = _mod.read_rows(words)
    assert page["tabular"] is True and page["viewKind"] == "table" and page["columns"] == ["this is", "a note"], page
    for path in (os.path.join(tmp, "bin.bed"), words):
        prof = profile_dataset(path)
        mm = [f for f in prof["findings"] if f["code"] == "name_content_mismatch"]
        assert mm and mm[0]["level"] == "watch", prof
        assert prof["format"]["ext"] not in ("bed", "gtf") and prof["viewKind"] not in ("intervals", "annotation"), prof
    # An empty BED (only a track line) is a valid, empty table.
    empty = _write(tmp, "empty.bed", "track name=none\n")
    page = _mod.read_rows(empty)
    assert page["tabular"] is True and page["totalRows"] == 0 and page["headerRow"] is False, page
    print("PASS test_read_rows_spec_mismatch_is_not_tabular")


def test_mtx_header_profile(tmp):
    path = _write(tmp, "matrix.mtx", "%%MatrixMarket matrix coordinate integer general\n%comment\n33538 2700 2286884\n1 1 3\n")
    prof = profile_dataset(path)
    by = {f["code"]: f for f in prof["findings"]}
    assert prof["shape"] == {"rows": 33538, "cols": 2700}, prof
    assert by["mtx_dimensions"]["params"]["nnz"] == 2286884 and by["mtx_dimensions"]["params"]["field"] == "integer", by
    assert prof["format"] == {"ext": "mtx", "label": "Matrix Market", "source": "biomate"}, prof["format"]
    assert _mod.read_rows(path)["tabular"] is False
    print("PASS test_mtx_header_profile")


# ---------------------------------------------------------------------------
# Galaxy datatypes integration — degrade when Galaxy is absent; map metadata → findings.
# ---------------------------------------------------------------------------
class _StubGalaxy:
    GENERIC_EXTS = frozenset({"data", "binary", "txt", "text", "tabular", "tsv"})

    def __init__(self, ident, meta):
        self.ident, self.meta = ident, meta

    def identify(self, path, name=None):
        return self.ident.get(os.path.basename(name or path))

    def metadata(self, path, ext):
        return self.meta.get(ext, {})

    def label_for(self, ext):
        return {"h5ad": "AnnData (h5ad)", "bam": "BAM", "tiff": "TIFF"}.get(ext, (ext or "").upper())

    def spec_column_names(self, ext):
        return None


def _with_galaxy(stub, fn):
    saved = list(_mod._GF_MODULE)
    _mod._GF_MODULE[:] = [stub]
    try:
        return fn()
    finally:
        _mod._GF_MODULE[:] = saved


def test_galaxy_unavailable_fallback(tmp):
    import gzip as _gz
    bam = os.path.join(tmp, "x.bam")
    with open(bam, "wb") as f:
        f.write(_gz.compress(b"BAM\x01" + b"\x00" * 64))  # BGZF-compressed BAM magic
    bed = _write(tmp, "fb.bed", "chr1\t1\t5\n")

    def run():
        p1 = profile_dataset(bam)
        # Identified from its magic bytes without Galaxy; content not analysed → unassessed.
        assert [f["code"] for f in p1["findings"]] == ["format_identified"], p1
        assert p1["format"]["source"] == "biomate" and p1["format"]["ext"] == "bam", p1["format"]
        assert p1["viewKind"] == "alignment" and p1["quality"] == "unassessed", p1
        p2 = profile_dataset(bed)
        assert p2["columns"] == ["Chrom", "Start", "End"] and p2["format"]["ext"] == "bed", p2
        return True

    assert _with_galaxy(None, run)
    # The real module on a host without Galaxy's dependencies: unavailable, never raises.
    gf = _mod._galaxy_formats()
    assert gf is not None
    assert gf.filename_exts("a.OME.tif") == ["ome.tiff", "tiff"] and gf.filename_exts("r.fq.gz")[0] == "fastqsanger.gz"
    if not gf.available():
        assert gf.identify(bed, "fb.bed") is None and gf.metadata(bed, "bed") == {}
    print("PASS test_galaxy_unavailable_fallback")


def test_galaxy_metadata_mapping(tmp):
    files = {}
    for n in ("a.h5ad", "b.bam", "c.fasta", "d.sdf", "e.pdb", "f.xlsx", "g.tiff", "h.loom", "u.bin"):
        p = os.path.join(tmp, n)
        with open(p, "wb") as f:
            f.write(b"\x89HDF\r\n\x1a\n\x00\x00binary")
        files[n] = p
    gtf = _write(tmp, "k.gtf", 'chr1\tsrc\texon\t1\t10\t.\t+\t.\tgene_id "g1"; transcript_id "t1";\n')
    bed = _write(tmp, "m.bed", "chr1\t1\t5\tn\t0\t+\n")
    counts = _write(tmp, "counts.txt", "gene\ts1\ns2\t1\n")
    stub = _StubGalaxy(
        {"a.h5ad": "h5ad", "b.bam": "bam", "c.fasta": "fasta", "d.sdf": "sdf", "e.pdb": "pdb", "f.xlsx": "xlsx",
         "g.tiff": "tiff", "h.loom": "loom", "u.bin": "data", "k.gtf": "gtf", "noext_seq": "fasta", "aln.sam": "sam", "m.bed": "bed", "counts.txt": "mothur.axes"},
        {"h5ad": {"shape": [2700, 32738], "obs_layers": ["index", "n_genes", "louvain"], "var_layers": ["index", "gene_ids"],
                  "obsm_layers": ["X_pca", "X_umap"], "layers_names": ["X", "obs", "obsm", "var"]},
         "bam": {"reference_count": 25, "reference_total_length": 3100000000, "reference_names": ["chr1"],
                 "sort_order": "queryname", "read_group_count": 0, "samples": []},
         "sdf": {"number_of_molecules": 12},
         "pdb": {"chain_ids": ["A", "B"]},
         "xlsx": {"sheets": [{"name": "Plate1", "rows": 97, "cols": 12}, {"name": "Notes", "rows": 3, "cols": 1}]},
         "loom": {"shape": [500, 40], "row_attrs_names": ["Gene"], "col_attrs_names": ["CellID"], "layers_names": [""]},
         "gtf": {"comment_lines": 0, "attribute_types": {"gene_id": "str", "transcript_id": "str"}},
         "bed": {"columns": 6, "strandCol": 6}},
    )

    def codes(p):
        return {f["code"]: f for f in p["findings"]}

    def run():
        h = profile_dataset(files["a.h5ad"])
        c = codes(h)
        assert h["shape"] == {"rows": 2700, "cols": 32738}, h
        assert c["anndata_shape"]["params"] == {"cells": 2700, "genes": 32738}, c
        assert c["anndata_obs"]["params"]["columns"] == ["n_genes", "louvain"], c       # 'index' dropped
        assert c["anndata_embeddings"]["params"]["embeddings"] == ["X_pca", "X_umap"], c
        assert h["format"] == {"ext": "h5ad", "label": "AnnData (h5ad)", "source": "galaxy"}, h["format"]
        # Metadata only: "unassessed" with an info note (not a "watch" that found nothing).
        assert h["quality"] == "unassessed" and c["format_metadata_only"]["level"] == "info", h
        assert h["viewKind"] == "anndata" and h["stats"] == [{"code": "cells", "value": 2700}, {"code": "genes", "value": 32738}], h
        b = codes(profile_dataset(files["b.bam"]))
        assert b["alignment_references"]["params"]["references"] == 25, b
        assert b["alignment_not_coordinate_sorted"]["level"] == "watch" and b["alignment_no_read_groups"]["level"] == "watch", b
        # Galaxy says FASTA for a file BioMate could not classify (no extension) → BioMate's FASTA profile.
        fa = profile_dataset(_write(tmp, "noext_seq", ">s1 x\nACGTACGT\n>s2\nGGCC\n"))
        assert codes(fa)["fasta_sequences"]["params"]["sequences"] == 2 and fa["format"]["source"] == "galaxy", fa
        assert codes(profile_dataset(files["d.sdf"]))["molecules_count"]["params"]["molecules"] == 12
        assert codes(profile_dataset(files["e.pdb"]))["structure_chains"]["params"]["chains"] == ["A", "B"]
        x = profile_dataset(files["f.xlsx"])
        assert codes(x)["spreadsheet_sheets"]["params"]["sheets"] == ["Plate1", "Notes"] and x["shape"]["rows"] == 97, x
        lo = profile_dataset(files["h.loom"])
        assert lo["shape"] == {"rows": 40, "cols": 500} and codes(lo)["loom_shape"]["params"]["genes"] == 500, lo
        t = profile_dataset(files["g.tiff"])
        assert codes(t)["format_identified"]["params"]["format"] == "TIFF" and t["format"]["source"] == "galaxy", t
        u = profile_dataset(files["u.bin"])               # Galaxy says only "data": the HDF5 signature decides
        assert "format_identified" in codes(u) and u["format"] == {"ext": "h5", "label": "HDF5", "source": "biomate"}, u
        assert u["quality"] == "unassessed" and "name_content_mismatch" not in codes(u), u
        g = profile_dataset(gtf)
        gc = codes(g)
        assert gc["annotation_features"]["params"]["attributes"] == ["gene_id", "transcript_id"], gc
        assert g["columns"][-1] == "Attributes" and g["format"]["ext"] == "gtf" and g["format"]["source"] == "galaxy", g
        bd = codes(profile_dataset(bed))
        assert bd["intervals_stranded"]["params"]["column"] == "Strand" and bd["intervals_summary"]["params"]["regions"] == 1, bd
        # A SAM only looks delimited: its extension names no BioMate reader, so Galaxy's identification wins.
        sam = profile_dataset(_write(tmp, "aln.sam", "@HD\tVN:1.6\nr1\t0\tchr1\t1\t60\t4M\t*\t0\t0\tACGT\tIIII\n"))
        assert sam["format"]["ext"] == "sam" and "columns" not in sam and "format_identified" in codes(sam), sam
        # A greedy Galaxy sniff on a plain table never relabels BioMate's analysed table.
        ct = profile_dataset(counts)
        assert ct["format"] == {"ext": "tsv", "label": "TSV", "source": "biomate"}, ct["format"]
        assert ct["viewKind"] == "table", ct
        return True

    assert _with_galaxy(stub, run)
    print("PASS test_galaxy_metadata_mapping")


def test_galaxy_formats_helpers():
    gf = _mod._galaxy_formats()
    m = gf._Meta({"a": type("E", (), {"default": 1})(), "b": type("E", (), {"default": []})()})
    assert m.a == 1 and m.b == [] and m.missing is None and not m.element_is_set("a")
    m.a = 2
    assert m.element_is_set("a") and dict(m.items())["a"] == 2
    assert gf._plain({"x": (1, b"ab"), "y": set()}) == {"x": [1, "ab"], "y": []}
    assert gf.label_for("vcf_bgzip") == "VCF (bgzip)" and gf.label_for(None) == "Unknown"
    print("PASS test_galaxy_formats_helpers")


# ---------------------------------------------------------------------------
# Dev format matrix (2026-11-11): binary files reported "Blocked: line contains NUL"; temp names in
# findings; FASTA "0 sequences"; a plain numeric CSV got label/leakage warnings.
# ---------------------------------------------------------------------------
def test_binary_files_never_reach_text_readers(tmp):
    import gzip as _gz
    samples = {
        "r.bam": _gz.compress(b"BAM\x01\x00\x00\x00\x00chr1\t1,2\n" * 20),     # BGZF/gzip with tab + comma
        "r.cram": b"CRAM\x03\x00\x00\x00,\t\n" + bytes(range(256)),
        "img.tiff": b"II*\x00\x08\x00\x00\x00a,b\tc\n" + b"\x00" * 64,
        "x.csv": b"a,b\n\x00\x01,\x02\n",
    }
    for name, data in samples.items():
        path = os.path.join(tmp, name)
        with open(path, "wb") as f:
            f.write(data)
        prof = profile_dataset(path)
        codes = [f["code"] for f in prof["findings"]]
        assert prof["quality"] != "blocked" and "parse_failed" not in codes, (name, prof)
        assert _mod.read_rows(path)["tabular"] is False, name
    x = profile_dataset(os.path.join(tmp, "x.csv"))
    assert x["findings"][0]["code"] == "name_content_mismatch" and x["findings"][0]["params"]["named"] == "CSV", x
    # Binary past the first block (FITS: an ASCII header with no line breaks, then binary data), and a
    # text table with a NUL far down: neither is "blocked", neither raises in read_rows.
    fits = os.path.join(tmp, "img.fits")
    with open(fits, "wb") as f:
        f.write(b"SIMPLE  =                    T / conforms" + b" " * 9000 + b"\x00\x01" * 100)
    late = os.path.join(tmp, "late.tsv")
    with open(late, "wb") as f:
        f.write(b"a\tb\n" + b"1\t2\n" * 3000 + b"\x00\x00\t\x01\n")
    prof = profile_dataset(fits)
    assert prof["quality"] != "blocked" and _mod.read_rows(fits)["tabular"] is False, prof
    # One NUL line deep in a TSV does not make the file binary: it stays a table, the NULs are
    # dropped and reported (audit R9).
    prof = profile_dataset(late)
    assert prof["viewKind"] == "table" and prof["shape"]["rows"] == 3001, prof
    assert {f["code"]: f for f in prof["findings"]}["nul_bytes"]["params"] == {"lines": 1}, prof["findings"]
    assert _mod.read_rows(late)["tabular"] is True
    # Compressed by magic, whatever the name: bzip2 FASTQ, BGZF VCF named .vcf_bgzip, gzip text .prj.
    import bz2 as _bz2
    fq = os.path.join(tmp, "reads.fastqsanger.bz2")
    with open(fq, "wb") as f:
        f.write(_bz2.compress(b"@r1\nACGT\n+\nIIII\n@r2\nACGA\n+\nIIII\n"))
    vcf = os.path.join(tmp, "calls.vcf_bgzip")
    with open(vcf, "wb") as f:
        f.write(_gz.compress(b"##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\ts1\n1\t5\t.\tA\tG\t.\t.\t.\tGT\t0/1\n"))
    assert {f["code"]: f for f in profile_dataset(fq)["findings"]}["fastq_reads"]["params"]["reads"] == 2
    assert {f["code"]: f for f in profile_dataset(vcf)["findings"]}["vcf_records"]["params"] == {"variants": 1, "samples": 1}
    # UTF-16 text (BOM) is text, not binary.
    u16 = os.path.join(tmp, "u16.tsv")
    with open(u16, "wb") as f:
        f.write("gene\tvalue\nTP53\t1\nEGFR\t2\n".encode("utf-16"))
    page = _mod.read_rows(u16)
    assert page["columns"] == ["gene", "value"] and page["rows"] == [["TP53", "1"], ["EGFR", "2"]], page
    print("PASS test_binary_files_never_reach_text_readers")


def test_findings_use_the_users_filename(tmp):
    with open(os.path.join(tmp, "perception_ab12cd_mystery.bin"), "wb") as fh:
        fh.write(bytes(range(256)) * 40)  # unrecognised binary
    prof = profile_dataset(os.path.join(tmp, "perception_ab12cd_mystery.bin"), name="mystery.bin")
    f = [x for x in prof["findings"] if x["code"] == "unprofilable"][0]
    assert f["params"]["name"] == "mystery.bin" and "perception_" not in " ".join(prof["notes"]), prof
    print("PASS test_findings_use_the_users_filename")


def test_fasta_profile_plain_and_gz(tmp):
    import gzip as _gz
    text = ">s1 desc\nACGTACGTAC\nGGCC\n>s2\nATATAT\n>s3\nGGGGGGGGGGCCCCCCCCCC\n"
    plain = _write(tmp, "ref.fa", text)
    gz = os.path.join(tmp, "ref.fasta.gz")
    with _gz.open(gz, "wt") as f:
        f.write(text)
    for path in (plain, gz):
        prof = profile_dataset(path)
        by = {x["code"]: x["params"] for x in prof["findings"]}
        assert by["fasta_sequences"] == {"sequences": 3, "at_least": False, "total": 40, "unit": "bp", "mean": 13,
                                         "min": 6, "max": 20, "n50": 20}, by
        gc = 5 + 4 + 20   # s1: 5 in ACGTACGTAC + 4 in GGCC; s3: 20
        assert by["fasta_gc"]["pct"] == round(100.0 * gc / 40, 1), by
        assert prof["shape"]["rows"] == 3 and prof["quality"] == "good", prof
        assert prof["format"]["ext"] == "fasta", prof["format"]
    prot = profile_dataset(_write(tmp, "p.faa", ">p1\nMKTLLVLAVLLLSQ\n>p2\n\n"))
    codes = {x["code"]: x for x in prot["findings"]}
    assert "fasta_protein" in codes and codes["fasta_sequences"]["params"]["unit"] == "aa", codes
    assert codes["fasta_empty_records"]["level"] == "watch" and prot["quality"] == "watch", codes
    print("PASS test_fasta_profile_plain_and_gz")


def test_plain_numeric_table_has_no_false_label_or_leakage(tmp):
    # A 7 × 7 grid (x, y) with a unique float per row (z): y reads as a 7-class label, perfectly
    # balanced — not "imbalanced" — and a unique-per-row measurement does not "leak" anything.
    rows = ["x,y,z"] + [f"{i},{j},{((i * 7 + j) * 0.6180339887) % 1:.12f}" for i in range(1, 8) for j in range(1, 8)]
    prof = profile_dataset(_write(tmp, "grid.csv", "\n".join(rows) + "\n"))
    codes = [f["code"] for f in prof["findings"]]
    assert prof["quality"] == "good" and "leakage" not in prof, prof
    assert not any(c in codes for c in ("minority_class", "leaked_id", "leaked_feature")), codes
    # A continuous unique-per-row feature beside a binary label: memorising it is not leakage.
    rows = ["expr,label"] + [f"{i * 0.731:.4f},{'a' if i % 2 else 'b'}" for i in range(60)]
    prof = profile_dataset(_write(tmp, "cont.csv", "\n".join(rows) + "\n"))
    assert "leakage" not in prof, prof
    # Imbalance is still caught for k > 2: 5 / 45 / 50 of 100 rows.
    rows = ["f,label"] + [f"{i % 9},{'r' if i < 5 else ('s' if i < 50 else 't')}" for i in range(100)]
    prof = profile_dataset(_write(tmp, "imb3.csv", "\n".join(rows) + "\n"))
    assert "minority_class" in [f["code"] for f in prof["findings"]], prof
    print("PASS test_plain_numeric_table_has_no_false_label_or_leakage")


def test_folder_context_fastq_layout(tmp):
    # Single vs paired-end is a FOLDER fact: with the folder context the FASTQ profile names its
    # mate (or the missing one) instead of "single-end unless a mate file is present".
    fq = "@r1/1\nACGT\n+\nIIII\n@r2/1\nACGA\n+\nIIII\n"
    path = _write(tmp, "S1_R1.fastq", fq)
    sib = ["pairs/S1_R1.fastq", "pairs/S1_R2.fastq", "pairs/S2_R1.fastq"]
    paired = profile_dataset(path, name="pairs/S1_R1.fastq", context={"name": "pairs/S1_R1.fastq", "siblings": sib})
    codes = {f["code"]: f for f in paired["findings"]}
    assert "fastq_single_file" not in codes and "fastq_single_end" not in codes, codes
    assert codes["fastq_paired_mate"]["params"] == {"read": "1", "sample": "S1", "mate": "S1_R2.fastq"}, codes
    assert "fastq_paired_end" in codes and paired["quality"] == "good", paired
    orphan = profile_dataset(path, name="pairs/S2_R1.fastq", context={"name": "pairs/S2_R1.fastq", "siblings": sib})
    codes = {f["code"]: f for f in orphan["findings"]}
    assert codes["fastq_mate_missing"]["params"] == {"read": "1", "missing": "2", "sample": "S2"}, codes
    assert orphan["quality"] == "watch" and "fastq_single_file" not in codes, orphan
    # No context (a file outside any project folder listing): the honest unknown stays.
    bare = profile_dataset(path)
    assert "fastq_single_file" in [f["code"] for f in bare["findings"]]
    print("PASS test_folder_context_fastq_layout")


def test_folder_context_tenx_headerless(tmp):
    feats = ("ENSG00000243485\tMIR1302-2HG\tGene Expression\nENSG00000237613\tFAM138A\tGene Expression\n"
             "ENSG00000186092\tOR4F5\tGene Expression\n")
    path = _write(tmp, "features.tsv", feats)
    ctx = {"name": "tenx/features.tsv", "siblings": ["tenx/matrix.mtx", "tenx/barcodes.tsv", "tenx/features.tsv"]}
    prof = profile_dataset(path, name="tenx/features.tsv", context=ctx)
    assert prof["shape"]["rows"] == 3 and prof["columns"][:3] == ["feature_id", "feature_name", "feature_type"], prof
    assert prof["sampleRows"][0][0] == "ENSG00000243485", prof["sampleRows"]
    assert "tenx_member_headerless" in [f["code"] for f in prof["findings"]]
    page = _mod.read_rows(path, 0, 10, context=ctx)
    assert page["headerRow"] is False and page["totalRows"] == 3 and page["rows"][0][1] == "MIR1302-2HG", page
    # Without the folder context the generic inference keeps its own (documented) default.
    assert _mod.read_rows(path, 0, 10)["headerRow"] is True
    mtx = _write(tmp, "matrix.mtx", "%%MatrixMarket matrix coordinate integer general\n3 2 2\n1 1 4\n2 2 1\n")
    mprof = profile_dataset(mtx, context={"name": "tenx/matrix.mtx", "siblings": ctx["siblings"]})
    codes = {f["code"]: f for f in mprof["findings"]}
    assert codes["mtx_tenx_set"]["params"] == {"features": "features.tsv", "barcodes": "barcodes.tsv"} and "mtx_orientation" not in codes, codes
    print("PASS test_folder_context_tenx_headerless")


def main():
    import inspect

    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    with tempfile.TemporaryDirectory() as tmp:
        for t in tests:
            t(tmp) if inspect.signature(t).parameters else t()
    print(f"\nAll {len(tests)} data-perception tests passed.")


if __name__ == "__main__":
    main()
