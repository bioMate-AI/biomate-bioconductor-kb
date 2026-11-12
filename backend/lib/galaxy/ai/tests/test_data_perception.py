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
    assert any("drop" in pi["effect"] for pi in prof["planImpact"]), prof
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
    sig = " ".join(prof["signalSummary"])
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
    assert prof["quality"] in ("watch", "blocked"), prof
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
    for suffix, text in (("json", '{"bad": }'), ("yaml", "bad: [")):
        p = profile_dataset(_write(tmp, "invalid." + suffix, text))
        assert p["quality"] == "blocked", p
        assert "Could not parse" in p["notes"][0], p
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
        assert any("near-constant" in s for s in (p.signal_summary or [])), p.signal_summary
        assert not any("constant-column issues detected" in n for n in p.notes), p.notes
    print("PASS test_jsonl_records_not_csv")


# ---------------------------------------------------------------------------
# Effective-N reason + structured (localizable) findings — Data panel fixes
# 2026-11-10 (docs/20261110_DATA_PANEL_FIXES.md). The card said "correlation /
# imbalance discounted it" even when the only reduction was duplicate rows.
# ---------------------------------------------------------------------------
def test_effective_n_reason_dedup_without_label(tmp):
    rows = ["a,b"] + [f"{i},{i * 2}" for i in range(40)] + ["1,2"] * 10  # 10 exact duplicates
    path = _write(tmp, "dups.csv", "\n".join(rows) + "\n")
    p = profile_dataset(path)
    assert p["effectiveN"] == 40, p
    assert p["effectiveNReason"] == "dedup", p
    assert p["duplicateRows"] == 10, p
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


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    with tempfile.TemporaryDirectory() as tmp:
        for t in tests:
            t(tmp)
    print(f"\nAll {len(tests)} data-perception tests passed.")


if __name__ == "__main__":
    main()
