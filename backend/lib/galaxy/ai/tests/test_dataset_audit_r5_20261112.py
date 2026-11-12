"""
Behavioural tests for the ROUND-5 audit of the dataset profiler (live dev walkthrough on
4ea6bb7fa7, 2026-11-12):

* 1 — confounded / nested design vs leakage: design_600.tsv's "donor" (30 donors × 20 samples,
  every donor in ONE condition) was ``leaked_feature`` + plan "drop donor before modelling". A
  grouping column nested within the groups is a confounded design (``group_nested``, no plan);
  a crossed donor is nothing; a one-to-one recoding of the label stays ``leaked_feature``; a batch
  that only partly lines up keeps ``batch_confound``.
* 2 — count matrices (genes × samples) said "No group column (e.g. condition) was found, so group
  sizes were not checked": not said of a wide matrix; sample columns whose names form groups are
  stated (``sample_groups_from_names``).
* 3 — each fact once: VCF counts (signal + note + plan), AnnData / loom shape numbers beside the
  stats, an xlsx sheet name in two findings, a FASTQ orphan restated as a "mixed layout".
* 4 — columnStats roles: BED / GTF coordinates (no columnStats before) are ``annotation``; a JSON
  Lines "page" is an ``identifier`` also when its numbers restart (an extract of several
  documents) and in a one-record file (no columnStats before).
* 5 — the unprofilable note in plain words.

Every test fails on the profiler at cdd43e9dd2. Deterministic, no network. To run against another
copy of the modules (e.g. the old code), point BM_AI_DIR at its galaxy/ai folder.

Run standalone (no pytest needed):
    cd backend && python3.9 lib/galaxy/ai/tests/test_dataset_audit_r5_20261112.py
"""
from __future__ import annotations

import importlib.util
import inspect
import json
import os
import random
import re
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


dp = _load("_dp_audit_r5_under_test", "data_perception.py")
fp = _load("_fp_audit_r5_under_test", "folder_profile.py")

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


def _tsv(tmp, name, header, rows):
    return _w(tmp, name, "\t".join(header) + "\n" + "".join("\t".join(str(c) for c in r) + "\n" for r in rows))


def _codes(prof):
    return {f["code"]: f for f in prof["findings"]}


def _once(prof):
    codes = [f["code"] for f in prof["findings"]]
    dupes = sorted({c for c in codes if codes.count(c) > 1})
    assert not dupes, (dupes, prof["findings"])


def _roles(prof):
    return {c["name"]: c.get("role") for c in prof.get("columnStats") or []}


# ---------------------------------------------------------------------------
# 1 — nested grouping column = confounded design, not leakage
# ---------------------------------------------------------------------------
def _design(donor_of):
    """600 samples, condition alternating ctrl/treat, batch B1…B6 crossing the conditions;
    expression / mito_pct are noise."""
    rng = random.Random(600)
    rows = []
    for i in range(600):
        cond = "ctrl" if i % 2 == 0 else "treat"
        rows.append([f"S{i + 1:04d}", cond, f"B{i // 100 + 1}", donor_of(i), rng.randint(1800, 2250),
                     round(rng.uniform(1.5, 12), 2)])
    return rows


_HEAD = ["sample_id", "condition", "batch", "donor", "expression", "mito_pct"]
_NESTED = ("Each value of “donor” occurs in only one group of “condition”, so donor and condition effects "
           "cannot be separated — a confounded design; dropping the column does not fix it.")


def test_1_nested_donor_is_a_confounded_design_not_leakage(tmp):
    # design_600.tsv: donor D01…D30, each donor's 20 samples all in ONE condition.
    prof = dp.profile_dataset(_tsv(tmp, "design_600.tsv", _HEAD, _design(lambda i: f"D{i % 30 + 1:02d}")))
    by = _codes(prof)
    assert "leaked_feature" not in by and "leaked_id" not in by, prof["findings"]
    f = by["group_nested"]
    assert f["level"] == "watch" and f["section"] == "leakage", f
    assert f["params"] == {"column": "donor", "label": "condition"}, f
    assert dp.finding_text("group_nested", f["params"]) == _NESTED
    assert prof["leakage"]["detail"] == _NESTED, prof["leakage"]
    # Dropping the column does not fix a design: no drop plan (nor any other plan).
    assert not any(f["code"] == "drop_leaky_column" for f in prof["findings"]) and not prof["planImpact"], prof
    assert prof["quality"] == "watch"
    _once(prof)


def test_1_crossed_donor_and_id_column_raise_nothing(tmp):
    # Each donor gives samples in BOTH conditions (a paired / crossed design): nothing to report.
    prof = dp.profile_dataset(_tsv(tmp, "crossed.tsv", _HEAD, _design(lambda i: f"D{(i // 2) % 30 + 1:02d}")))
    by = _codes(prof)
    assert not {"group_nested", "leaked_feature", "leaked_id", "batch_confound"} & set(by), prof["findings"]
    # A unique sample ID naming the condition is an identifier, not a nested grouping.
    rows = [[f"{'ctrl' if i % 2 == 0 else 'treat'}_{i:03d}", "ctrl" if i % 2 == 0 else "treat", (i * 7) % 50]
            for i in range(60)]
    prof = dp.profile_dataset(_tsv(tmp, "ids.tsv", ["sample_id", "condition", "value"], rows))
    assert "group_nested" not in _codes(prof) and "drop_leaky_column" not in _codes(prof), prof["findings"]
    assert _roles(prof)["sample_id"] == "identifier", prof["columnStats"]


def test_1_label_recoding_stays_leaked_feature_and_partial_batch_stays_batch_confound(tmp):
    # A one-to-one recoding of the label (grp A = ctrl, B = treat) IS the label: leaked feature + drop.
    rows = [["ctrl" if i % 2 == 0 else "treat", "A" if i % 2 == 0 else "B", (i * 7) % 50] for i in range(60)]
    prof = dp.profile_dataset(_tsv(tmp, "recode.tsv", ["condition", "grp", "value"], rows))
    by = _codes(prof)
    assert by["leaked_feature"]["params"]["column"] == "grp" and "drop_leaky_column" in by, prof["findings"]
    assert "group_nested" not in by
    # A measured value that separates the groups is leakage, not a grouping (even with repeats).
    rows = [["ctrl" if i % 2 == 0 else "treat", 10 + (i % 6) * 2 + (i % 2), (i * 7) % 50] for i in range(60)]
    by = _codes(dp.profile_dataset(_tsv(tmp, "leak.tsv", ["condition", "score", "value"], rows)))
    assert by["leaked_feature"]["params"]["column"] == "score" and "group_nested" not in by, by
    # Integer donor numbers are a grouping: nested.
    rows = [["ctrl" if d <= 5 else "treat", d, (i * 7) % 50] for d in range(1, 11) for i in range(6)]
    by = _codes(dp.profile_dataset(_tsv(tmp, "donor_int.tsv", ["condition", "donor", "value"], rows)))
    assert by["group_nested"]["params"]["column"] == "donor" and "leaked_feature" not in by, by
    # A batch NESTED in the groups (B1–B3 ctrl only, B4–B6 treat only): the confounded design,
    # without the covariate plan (a nested batch is collinear with the group).
    rows = [["ctrl" if b <= 3 else "treat", f"B{b}", (i * 7) % 50] for b in range(1, 7) for i in range(10)]
    prof = dp.profile_dataset(_tsv(tmp, "nested_batch.tsv", ["condition", "batch", "value"], rows))
    by = _codes(prof)
    assert by["group_nested"]["params"] == {"column": "batch", "label": "condition"}, prof["findings"]
    assert "batch_confound" not in by and "batch_covariate" not in by, prof["findings"]
    # A batch that lines up with the groups only PARTLY (one sample of 60 off): batch_confound kept.
    rows = [["ctrl" if b <= 3 else "treat", f"B{b}", (i * 7) % 50] for b in range(1, 7) for i in range(10)]
    rows[0][0] = "treat"
    prof = dp.profile_dataset(_tsv(tmp, "partial_batch.tsv", ["condition", "batch", "value"], rows))
    by = _codes(prof)
    assert "batch_confound" in by and "group_nested" not in by, prof["findings"]


# ---------------------------------------------------------------------------
# 2 — wide count matrices: no "no group column" note; groups from sample names
# ---------------------------------------------------------------------------
def test_2_count_matrix_states_sample_groups_not_a_missing_group_column(tmp):
    rows = [[f"ENSG{i:011d}", 1800 + i, 1900 + i, 2000 + i, 2100 + 2 * i] for i in range(40)]
    prof = dp.profile_dataset(_tsv(tmp, "counts.tsv", ["gene_id", "ctrl_1", "ctrl_2", "treat_1", "treat_2"], rows))
    by = _codes(prof)
    assert "table_clean_unlabelled" not in by, prof["findings"]
    assert not any("group column" in n for n in prof["notes"]), prof["notes"]
    g = by["sample_groups_from_names"]
    assert g["level"] == "info" and g["params"] == {"groups": [{"name": "ctrl", "n": 2}, {"name": "treat", "n": 2}]}, g
    assert "Sample columns form groups by name: ctrl (2) · treat (2)." in prof["notes"], prof["notes"]
    assert prof["quality"] == "good"
    # WT_1 / KO_2 naming, no feature word in the first column's name.
    rows = [[f"row{i}", i, i + 1, i + 2, i + 3] for i in range(30)]
    prof = dp.profile_dataset(_tsv(tmp, "wt_ko.tsv", ["x", "WT_1", "WT_2", "KO_1", "KO_2"], rows))
    assert _codes(prof)["sample_groups_from_names"]["params"]["groups"] == [{"name": "WT", "n": 2}, {"name": "KO", "n": 2}]
    _once(prof)


def test_2_tool_count_layouts_never_say_no_group_column(tmp):
    fc = ("# Program:featureCounts v2.0.1\nGeneid\tChr\tStart\tEnd\tStrand\tLength\tS1.bam\tS2.bam\n"
          + "".join(f"G{i}\tchr1\t{i * 1000 + 1}\t{i * 1000 + 800}\t+\t800\t{(i * 37) % 500}\t{(i * 53) % 450}\n"
                    for i in range(15)))
    mageck = "sgRNA\tGene\tsample\n" + "".join(f"sg{i}\tGENE{i // 2}\t{1900 + i * 7}\n" for i in range(30))
    salmon = "Name\tLength\tEffectiveLength\tTPM\tNumReads\n" + "".join(
        f"ENST{i:011d}\t{1000 + i}\t{850.5 + i}\t{(i * 3.7) % 50:.3f}\t{(i * 11) % 200}\n" for i in range(30))
    rsem = "gene_id\ttranscript_id(s)\tlength\teffective_length\texpected_count\tTPM\tFPKM\n" + "".join(
        f"G{i}\tT{i}\t{1000 + i}\t{850.5 + i}\t{(i * 11) % 200}.00\t{(i * 3.7) % 50:.2f}\t{(i * 2.1) % 30:.2f}\n"
        for i in range(30))
    for name, text in (("featurecounts.txt", fc), ("lib.count.txt", mageck), ("quant.sf", salmon),
                       ("a.genes.results", rsem)):
        prof = dp.profile_dataset(_w(tmp, name, text))
        by = _codes(prof)
        assert prof["format"].get("layout"), (name, prof["format"])
        assert "table_clean_unlabelled" not in by, (name, prof["findings"])
        assert not any("group column" in n for n in prof["notes"]), (name, prof["notes"])
        assert "sample_groups_from_names" not in by, (name, prof["findings"])  # S1/S2, one sample
    # A samples × measurements table keeps its note: a group column could exist there.
    prof = dp.profile_dataset(_w(tmp, "eu.csv", "sample;weight_g;conc_mg_ml;ratio\nA;12,5;0,031;1,2\n"
                                                 "B;13,1;0,029;1,05\nC;11,8;0,040;0,98\nD;12,9;0,035;1,1\n"))
    assert "table_clean_unlabelled" in _codes(prof), prof["findings"]


# ---------------------------------------------------------------------------
# 3 — each fact once
# ---------------------------------------------------------------------------
def test_3_vcf_counts_stated_once(tmp):
    vcf = ("##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tS1\n"
           + "".join(f"chr1\t{100 + i}\t.\tA\tT\t50\tPASS\t.\tGT\t0/1\n" for i in range(30)))
    prof = dp.profile_dataset(_w(tmp, "1.vcf", vcf))
    assert [f["code"] for f in prof["findings"]] == ["vcf_records"], prof["findings"]
    assert not prof["planImpact"] and not prof["notes"], prof
    assert prof["stats"] == [{"code": "variants", "value": 30}, {"code": "samples", "value": 1}], prof["stats"]


def test_3_anndata_and_loom_shape_findings_do_not_repeat_the_stats():
    p = dp.DataProfile()
    assert dp._galaxy_meta_findings(p, "h5ad", {"shape": [2700, 32738]}, "AnnData (h5ad)")
    text = " ".join(p.signal_summary or [])
    assert p.stats_map == {"cells": 2700, "genes": 32738} and "cells" in text, (p.stats_map, text)
    assert not re.search(r"\d", text), text
    p = dp.DataProfile()
    assert dp._galaxy_meta_findings(p, "loom", {"shape": [500, 40]}, "Loom")
    assert not re.search(r"\d", " ".join(p.signal_summary or [])), p.signal_summary


def _xlsx_profile(tmp, meta):
    orig = dp._galaxy_metadata
    dp._galaxy_metadata = lambda path, ext: meta
    try:
        return dp._profile_galaxy_format(_w(tmp, "s.xlsx", b"PK\x03\x04stub"), "xlsx", 10, "Excel (xlsx)")
    finally:
        dp._galaxy_metadata = orig


def _mentions(p, word):
    return sum(1 for line in (p.notes or []) + (p.signal_summary or []) if word in line)


def test_3_xlsx_sheet_name_stated_once(tmp):
    preview = {"sheet": "Sample-spreadsheet-file", "rows": [["sample", "value"], ["S1", "1"], ["S2", "2"]]}
    p = _xlsx_profile(tmp, {"sheets": [{"name": "Sample-spreadsheet-file", "rows": 3, "cols": 2}], "preview": preview})
    codes = [f["code"] for f in p.findings]
    assert "spreadsheet_preview" in codes and "spreadsheet_sheets" not in codes, codes
    assert _mentions(p, "Sample-spreadsheet-file") == 1, (p.notes, p.signal_summary)
    preview = {"sheet": "data", "rows": [["sample", "value"], ["S1", "1"]]}
    p = _xlsx_profile(tmp, {"sheets": [{"name": "data"}, {"name": "meta"}], "preview": preview})
    codes = [f["code"] for f in p.findings]
    assert codes.count("spreadsheet_preview_sheets") == 1 and "spreadsheet_sheets" not in codes \
        and "spreadsheet_preview" not in codes, codes
    f = [x for x in p.findings if x["code"] == "spreadsheet_preview_sheets"][0]
    assert f["params"] == {"count": 2, "sheets": ["data", "meta"], "sheet": "data", "rows": 1}, f
    assert dp.finding_text(f["code"], f["params"]) == \
        "Sheets (2): data, meta; the preview shows the first rows of “data” (rows shown: 1)."
    # No preview: the sheet list is the one statement.
    p = _xlsx_profile(tmp, {"sheets": [{"name": "data"}, {"name": "meta"}]})
    assert [f["code"] for f in p.findings][:1] == ["spreadsheet_sheets"], p.findings


def test_3_folder_orphan_mate_stated_once():
    names = ["pairs/S1_R1.fastq.gz", "pairs/S1_R2.fastq.gz", "pairs/S2_R1.fastq.gz"]
    out = fp.profile_folder("pairs", names, engine="fallback")
    codes = [f["code"] for f in out["findings"]]
    assert codes.count("folder_fastq_orphan") == 1 and "folder_fastq_mixed_layout" not in codes, codes
    # A folder with a FASTQ that has no read naming at all still says it mixes layouts.
    out = fp.profile_folder("m", ["m/S1_R1.fastq.gz", "m/S1_R2.fastq.gz", "m/plain.fastq.gz"], engine="fallback")
    assert "folder_fastq_mixed_layout" in [f["code"] for f in out["findings"]], out["findings"]


# ---------------------------------------------------------------------------
# 4 — columnStats roles for coordinates and record positions
# ---------------------------------------------------------------------------
def test_4_bed_and_gtf_coordinates_are_annotation(tmp):
    bed = "".join(f"chr{1 + i % 3}\t{1000 * i}\t{1000 * i + 150}\tCCDS{i}.1\t0\t{'+-'[i % 2]}\n" for i in range(20))
    prof = dp.profile_dataset(_w(tmp, "1.bed", bed))
    r = _roles(prof)
    assert all(r[c] == "annotation" for c in ("Chrom", "Start", "End", "Strand")), prof.get("columnStats")
    assert r["Name"] == "identifier", r
    gtf = "".join(f'chr1\tsrc\texon\t{100 * i + 1}\t{100 * i + 90}\t.\t+\t.\tgene_id "g{i}";\n' for i in range(20))
    r = _roles(dp.profile_dataset(_w(tmp, "a.gtf", gtf)))
    assert all(r[c] == "annotation" for c in ("Seqname", "Start", "End", "Strand", "Feature")), r


def test_4_jsonl_page_is_an_identifier_in_extracts(tmp):
    # Two documents concatenated: page numbers restart (30, 31, 34, 2, 3, 5 …).
    recs = [{"source": "epar_table", "drug": d, "page": pg, "value": (k * 37) % 11}
            for k, (d, pg) in enumerate([("a", 30), ("a", 31), ("a", 34), ("b", 2), ("b", 3), ("b", 5)] * 4)]
    prof = dp.profile_dataset(_w(tmp, "ext.jsonl", "".join(json.dumps(r) + "\n" for r in recs)))
    assert _roles(prof)["page"] == "identifier", prof.get("columnStats")
    # One record: columnStats are still emitted for its scalar columns.
    prof = dp.profile_dataset(_w(tmp, "one.jsonl", json.dumps({"source": "x", "page": 30, "rows": [["a"]]}) + "\n"))
    assert prof.get("columnStats"), prof
    assert _roles(prof)["page"] == "identifier", prof["columnStats"]


# ---------------------------------------------------------------------------
# 5 — unprofilable in plain words
# ---------------------------------------------------------------------------
def test_5_unprofilable_plain_words(tmp):
    with open(os.path.join(tmp, "mystery.bin"), "wb") as fh:
        fh.write(bytes(range(256)) * 40)
    prof = dp.profile_dataset(os.path.join(tmp, "mystery.bin"), name="mystery.bin")
    f = _codes(prof)["unprofilable"]
    text = dp.finding_text("unprofilable", f["params"])
    assert text == "This file type cannot be read here (mystery.bin); only its size is reported.", text
    assert not re.search(r"leakage|balance", " ".join(prof["notes"])), prof["notes"]


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
    print(f"\n{len(tests) - failed}/{len(tests)} round-5 dataset-audit tests passed.")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
