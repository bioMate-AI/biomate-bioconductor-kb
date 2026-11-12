"""
Behavioural tests for the 2026-11-12 committee audit of the dataset profiler
(docs/20261112_DATASET_PANEL_AUDIT.md: P1–P3, R2–R12, U4, the backend copy, and the panel
contract: ``quality: "unassessed"``, content-first ``viewKind``, per-kind ``stats``,
``name_content_mismatch``, read_rows ≡ profile).

Every test reproduces an audit finding and fails on the profiler before the fix. Deterministic,
no network; Galaxy's datatypes are not needed (where Galaxy metadata matters a stub stands in).

Run standalone (no pytest needed):
    cd backend && python3.9 lib/galaxy/ai/tests/test_dataset_audit_20261112.py
"""
from __future__ import annotations

import bz2
import gzip
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


dp = _load("_dp_audit_under_test", "data_perception.py")
fp = _load("_fp_audit_under_test", "folder_profile.py")

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


def _prof(path, **kw):
    return dp.profile_dataset(path, **kw)


# ---------------------------------------------------------------------------
# P1 / R11 — FASTQ pairing
# ---------------------------------------------------------------------------
def _sheet(names, **kw):
    out = fp.profile_folder("p", names, engine="fallback", **kw)
    return out, [tuple(r) for r in out["samplesheet"]["rows"]]


def test_p1_novogene_replicates_pair_within_replicate():
    _out, rows = _sheet(["p/WT_1_1.fq.gz", "p/WT_1_2.fq.gz", "p/WT_2_1.fq.gz", "p/WT_2_2.fq.gz"])
    assert rows == [("WT_1", "p/WT_1_1.fq.gz", "p/WT_1_2.fq.gz"), ("WT_2", "p/WT_2_1.fq.gz", "p/WT_2_2.fq.gz")], rows


def test_p1_marker_inside_the_sample_name_is_not_a_read_number():
    out, rows = _sheet(["p/S_R10_R1.fastq", "p/S_R10_R2.fastq"])
    assert rows == [("S_R10", "p/S_R10_R1.fastq", "p/S_R10_R2.fastq")], rows
    _out, rows = _sheet(["p/ctrl_1_R1.fastq.gz", "p/ctrl_1_R2.fastq.gz", "p/ctrl_2_R1.fastq.gz", "p/ctrl_2_R2.fastq.gz"])
    assert [r[0] for r in rows] == ["ctrl_1", "ctrl_2"] and all(r[2] for r in rows), rows


def test_r11_lanes_are_runs_of_one_sample():
    out, rows = _sheet([f"p/S1_L00{lane}_R{r}_001.fastq.gz" for lane in (1, 2) for r in (1, 2)])
    assert rows == [("S1", "p/S1_L001_R1_001.fastq.gz", "p/S1_L001_R2_001.fastq.gz"),
                    ("S1", "p/S1_L002_R1_001.fastq.gz", "p/S1_L002_R2_001.fastq.gz")], rows
    assert _codes(out)["folder_fastq_sample_runs"]["params"] == {"sample": "S1", "n": 2}
    assert out["fastq"]["verdict"] == "paired"


def test_r11_index_reads_are_not_samples():
    out, rows = _sheet([f"p/S1_L001_{x}_001.fastq.gz" for x in ("R1", "R2", "I1", "I2")])
    assert rows == [("S1", "p/S1_L001_R1_001.fastq.gz", "p/S1_L001_R2_001.fastq.gz")], rows
    assert out["fastq"]["verdict"] == "paired" and out["fastq"]["indexReads"] == [
        "p/S1_L001_I1_001.fastq.gz", "p/S1_L001_I2_001.fastq.gz"], out["fastq"]
    assert _codes(out)["folder_fastq_index_reads"]["params"]["n"] == 2
    lay = fp.fastq_layout("p/S1_L001_I1_001.fastq.gz", ["p/S1_L001_R1_001.fastq.gz", "p/S1_L001_R2_001.fastq.gz"])
    assert lay["status"] == "index" and lay["read"] == "I1", lay


def test_p1_galaxy_failure_is_recorded_and_the_fixed_pairing_used():
    class Raising:
        @staticmethod
        def auto_pair(elements):
            raise ValueError("list.remove(x): x not in list")

    class Ok:
        @staticmethod
        def auto_pair(elements):  # what Galaxy returns for a plain S1_R1/S1_R2 pair
            class R:
                paired = [type("P", (), {"name": "S1", "forward": elements[0], "reverse": elements[1]})()]
                unpaired = []
            return R

    els = [fp._Element(name=n, path="p/" + n) for n in ("WT_1_1.fq.gz", "WT_1_2.fq.gz")]
    pairs, unpaired, _ft, engine, why = fp.auto_pair(els, galaxy=Raising)
    assert engine == "fallback" and why == "galaxy_error:ValueError" and len(pairs) == 1 and not unpaired, (engine, why)
    els = [fp._Element(name=n, path="p/" + n) for n in ("S1_R1.fq", "S1_R2.fq")]
    assert fp.auto_pair(els, galaxy=Ok)[3:] == ("galaxy", None)


# ---------------------------------------------------------------------------
# P2 — corrupt / truncated compression never raises
# ---------------------------------------------------------------------------
def test_p2_corrupt_gzip_is_blocked_not_an_exception(tmp):
    z = bytearray(gzip.compress(("gene,S1\n" + "".join(f"G{i},{i * 0.37:.3f}\n" for i in range(3000))).encode()))
    for i in range(30, 60):
        z[i] ^= 0xFF
    for name in ("corrupt.csv.gz", "corrupt.fastq.gz", "corrupt.bin"):
        path = _w(tmp, name, bytes(z))
        prof = _prof(path)
        assert prof["quality"] == "blocked" and prof["viewKind"] == "unknown", (name, prof)
        assert prof["findings"][0]["code"] in ("compressed_unreadable", "compressed_corrupt"), (name, prof["findings"])
        page = dp.read_rows(path)
        assert page["tabular"] is False and page["reason"] == "unreadable", (name, page)
    whole = gzip.compress(("gene,S1\n" + "".join(f"G{i},{i}\n" for i in range(20000))).encode())
    prof = _prof(_w(tmp, "trunc.csv.gz", whole[: len(whole) // 2]))
    assert prof["quality"] == "watch" and "compressed_truncated" in _codes(prof), prof["findings"]


# ---------------------------------------------------------------------------
# P3 — JSON Lines: BOM and skipped lines
# ---------------------------------------------------------------------------
def test_p3_jsonl_bom_keeps_record_one_and_skipped_lines_are_reported(tmp):
    prof = _prof(_w(tmp, "bom.jsonl", '﻿{"a": 1, "b": 2}\n{"a": 3, "b": 4}\n'.encode("utf-8")))
    assert prof["shape"]["rows"] == 2 and prof["sampleRows"][0] == ["1", "2"], prof
    prof = _prof(_w(tmp, "skip.jsonl", "".join(json.dumps({"k": i, "v": i % 3}) + "\n" for i in range(20)) + "{broken\n"))
    f = _codes(prof)["jsonl_skipped_lines"]
    assert f["level"] == "watch" and f["params"] == {"count": 1} and prof["viewKind"] == "records", prof


# ---------------------------------------------------------------------------
# R2 — comment lines, delimiter over several lines, prose is not a table
# ---------------------------------------------------------------------------
def test_r2_featurecounts_comment_line_and_delimiter(tmp):
    fc = '# Program:featureCounts v2.0.1; Command:"featureCounts" "-o" "counts.txt"\n' \
         "Geneid\tChr\tStart\tEnd\tStrand\tLength\tS1.bam\tS2.bam\n" + \
         "".join(f"G{i}\tchr1\t{100 * i}\t{100 * i + 50}\t+\t50\t{i * 3}\t{i * 7}\n" for i in range(1, 30))
    path = _w(tmp, "featurecounts.txt", fc)
    prof = _prof(path)
    assert prof["columns"][:2] == ["Geneid", "Chr"] and prof["shape"] == {"rows": 29, "cols": 8}, prof
    assert _codes(prof)["comment_lines_skipped"]["params"] == {"count": 1}
    page = dp.read_rows(path, 0, 2)
    assert page["skipLines"] == 1 and page["headerRow"] is True and page["rows"][0][0] == "G1", page
    semi = _prof(_w(tmp, "semi.csv", "gene;S1;S2\nA;1,5;2,0\nB;3,1;4,2\nC;5,0;6,9\n"))
    assert semi["columns"] == ["gene", "S1", "S2"] and semi["sampleRows"][0] == ["A", "1,5", "2,0"], semi
    log = _prof(_w(tmp, "run.log", "Starting the pipeline, version 2.1, on host a\n"
                   "Loaded 12 samples, 3 conditions, from sheet.csv\nFinished in 3 minutes, all good\n"))
    assert log["viewKind"] == "document" and "columns" not in log, log


# ---------------------------------------------------------------------------
# R3 — header inference
# ---------------------------------------------------------------------------
def test_r3_numeric_and_year_headers(tmp):
    for name, text, cols in (
        ("years.csv", "country,1990,2000,2010\nUS,1,2,3\nCN,4,5,6\nDE,7,8,9\n", ["country", "1990", "2000", "2010"]),
        ("nums.tsv", "gene\t1\t2\t3\nTP53\t10\t20\t30\nEGFR\t11\t21\t31\n", ["gene", "1", "2", "3"]),
    ):
        prof = _prof(_w(tmp, name, text))
        assert prof["columns"] == cols and prof["shape"]["rows"] == text.count("\n") - 1, (name, prof)
    # A headerless numeric matrix stays headerless.
    prof = _prof(_w(tmp, "m.csv", "5,6,7\n1,2,3\n4,5,6\n"))
    assert prof["shape"]["rows"] == 3 and "columns_generated" in _codes(prof), prof


def test_r3_same_case_single_column_headers(tmp):
    for name, text, first in (("symbol.txt", "SYMBOL\nTP53\nEGFR\nBRCA1\n", "TP53"),
                              ("mouse.txt", "Gene\nTrp53\nActb\nGapdh\n", "Trp53"),
                              ("ensembl.txt", "ENSEMBL\nENSG00000141510\nENSG00000146648\n", "ENSG00000141510")):
        prof = _prof(_w(tmp, name, text))
        assert prof["columns"] == [text.split("\n")[0]] and prof["sampleRows"][0] == [first], (name, prof)
    # A list without a header keeps its first gene.
    prof = _prof(_w(tmp, "genes.txt", "MYC\nTP53\nEGFR\n"))
    assert prof["shape"]["rows"] == 3, prof


def test_r3_bom_and_blank_first_line(tmp):
    prof = _prof(_w(tmp, "bom.csv", "﻿label,x\na,1\nb,2\na,3\nb,4\n".encode("utf-8")))
    assert prof["columns"] == ["label", "x"], prof["columns"]
    prof = _prof(_w(tmp, "blank_first.csv", "\nsample,val\nS1,1\nS2,2\n"))
    assert prof["quality"] != "blocked" and prof["columns"] == ["sample", "val"] and prof["shape"]["rows"] == 2, prof
    vcf = _prof(_w(tmp, "bom.vcf", "﻿##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n"
                   "1\t10\t.\tA\tG\t50\tPASS\t.\n".encode("utf-8")))
    assert _codes(vcf)["vcf_records"]["params"]["variants"] == 1, vcf


# ---------------------------------------------------------------------------
# R4 — tiny tables are not "Good"
# ---------------------------------------------------------------------------
def test_r4_header_only_one_line_one_byte(tmp):
    for name, text in (("h.tsv", "gene_id\tC1\tC2\n"), ("one.csv", "5,6,7\n"), ("x.csv", "x"), ("onerow.csv", "a,b\n1,2\n")):
        prof = _prof(_w(tmp, name, text))
        assert prof["quality"] == "watch", (name, prof)
        assert not any(f["code"] in ("table_clean", "table_clean_unlabelled", "near_constant", "constant_columns") for f in prof["findings"]), (name, prof)
    assert _codes(_prof(_w(tmp, "h2.tsv", "gene_id\tC1\n")))["header_only"]["level"] == "watch"
    assert _prof(_w(tmp, "nl.txt", "\n\n"))["quality"] == "blocked"


# ---------------------------------------------------------------------------
# R5 — label detection: whole tokens, categorical values, most label-like
# ---------------------------------------------------------------------------
def _table(tmp, name, header, rows):
    return _w(tmp, name, ",".join(header) + "\n" + "".join(",".join(map(str, r)) + "\n" for r in rows))


def test_r5_substrings_are_not_label_tokens(tmp):
    assert dp._find_col(["gene_symbol", "S1"], dp._LABEL_NAME_TOKENS) is None
    assert dp._find_col(["length", "width"], dp._BATCH_NAME_TOKENS) is None
    assert dp._find_col(["patientID", "x"], dp._BATCH_NAME_TOKENS) == 0
    rows = [[f"S{i}", "RNA" if i < 90 else "ATAC", 60 + i % 17] for i in range(100)]
    prof = _prof(_table(tmp, "assay.csv", ["sample", "assay", "weight_kg"], rows))
    assert "classBalance" not in prof and "minority_class" not in _codes(prof), prof


def test_r5_continuous_columns_are_not_classes(tmp):
    rows = [[f"S{i}", round((i * 7919 % 100) / 10.1, 1), i % 13] for i in range(1000)]
    prof = _prof(_table(tmp, "resp.csv", ["sample_id", "response", "x1"], rows))
    assert "classBalance" not in prof and "effective_n_imbalance" not in _codes(prof), prof
    rows = [[f"c{i}", i % 50, i % 16, i * 0.01] for i in range(300)]
    prof = _prof(_table(tmp, "spatial.csv", ["cell_id", "x", "y", "expr"], rows))
    assert "classBalance" not in prof, prof


def test_r5_most_label_like_column_wins(tmp):
    rows = [[f"P{i}", ["never", "former", "current"][i % 3], "case" if i < 20 else "control"] for i in range(200)]
    prof = _prof(_table(tmp, "smoke.csv", ["patient_id", "smoking_status", "diagnosis"], rows))
    labels = {c["label"] for c in prof["classBalance"]}
    assert labels == {"case", "control"}, prof["classBalance"]
    assert _codes(prof)["minority_class"]["params"]["label"] == "case", prof["findings"]


# ---------------------------------------------------------------------------
# R6 — no contradictions
# ---------------------------------------------------------------------------
def test_r6_clean_note_never_beside_a_watch_and_names_only_checks_run(tmp):
    rows = [[f"S{i}", "ctrl" if i < 3 else "trt", "b1" if i < 3 else "b2", i % 3 + 1] for i in range(6)]
    prof = _prof(_table(tmp, "design.csv", ["sample", "condition", "batch", "replicate"], rows))
    codes = _codes(prof)
    assert "batch_confound" in codes and "table_clean" not in codes and "table_clean_unlabelled" not in codes, codes
    rows = [[i, i * 2, i % 5] for i in range(50)]
    prof = _prof(_table(tmp, "nolabel.csv", ["a", "b", "c"], rows))
    assert "table_clean_unlabelled" in _codes(prof) and "table_clean" not in _codes(prof), prof["findings"]
    assert "not checked" in " ".join(prof["notes"]), prof["notes"]


def test_r6_effective_n_imbalance_only_under_the_imbalance_rule(tmp):
    rows = [[f"P{i}", 40 + i % 30, "MF"[i % 2], "R" if i < 65 else "NR"] for i in range(100)]
    prof = _prof(_table(tmp, "b6535.csv", ["patient_id", "age", "sex", "response"], rows))
    assert "effective_n_imbalance" not in _codes(prof) and prof["effectiveN"] == 100, prof
    rows = [[f"P{i}", 40 + i % 30, "R" if i < 92 else "NR"] for i in range(100)]
    prof = _prof(_table(tmp, "b928.csv", ["patient_id", "age", "response"], rows))
    assert "minority_class" in _codes(prof) and "effective_n_imbalance" in _codes(prof), prof["findings"]


# ---------------------------------------------------------------------------
# R7 / contract (e) — read_rows decides exactly like the profile
# ---------------------------------------------------------------------------
def test_r7_rows_only_for_tabular_views_and_identical_to_profile(tmp):
    files = {
        "aln.sam": "@HD\tVN:1.6\tSO:unsorted\nr1\t0\tchr1\t1\t60\t4M\t*\t0\t0\tACGT\tIIII\nr2\t16\tchr1\t9\t60\t4M\t*\t0\t0\tGGCC\tIIII\n",
        "prot.pdb": "HEADER    PEPTIDE\nATOM      1  N   LEU A   1      11.1  12.2  13.3  1.00 20.00           N\n"
                    "ATOM      2  CA  LEU A   1      11.9  12.5  13.0  1.00 20.00           C\nEND\n",
        "reads.txt": "@r1\nACGT\n+\nIIII\n@r2\nGGCC\n+\nIIII\n",
        "t.csv": "a,b\n1,2\n3,4\n",
        "r.jsonl": '{"a": 1}\n{"a": 2}\n',
        "x.bed": "chr1\t1\t5\nchr1\t9\t12\n",
        "notes.md": "# Title\n\nSome words here, and more words.\n",
    }
    expect = {"aln.sam": "alignment", "prot.pdb": "structure", "reads.txt": "reads", "t.csv": "table",
              "r.jsonl": "records", "x.bed": "intervals", "notes.md": "document"}
    for name, text in files.items():
        path = _w(tmp, name, text)
        prof = _prof(path)
        page = dp.read_rows(path)
        assert prof["viewKind"] == expect[name], (name, prof["viewKind"])
        assert page["viewKind"] == prof["viewKind"], (name, page, prof["viewKind"])
        assert page["tabular"] is (prof["viewKind"] in ("table", "records", "intervals", "annotation")), (name, page)


# ---------------------------------------------------------------------------
# R8 / R9 / contract (d) — content first; the name is only a claim
# ---------------------------------------------------------------------------
def test_r8_r9_name_content_mismatch(tmp):
    cases = {
        "fake.png": (b"this is not a png!!\n", "PNG", "document"),
        "rand.png": (bytes(range(1, 21)) + b"\x00" * 9000, "PNG", "binary"),
        "prose.fastq": ("this is not fastq at all\nreally not\nnope\nno\n", "FASTQ", "document"),
        "table.vcf": ("a,b\n1,2\n3,4\n", "VCF", "table"),
        "table.fastq": ("a,b\n1,2\n3,4\n5,6\n", "FASTQ", "table"),
    }
    for name, (data, named, view) in cases.items():
        prof = _prof(_w(tmp, name, data))
        f = prof["findings"][0]
        assert f["code"] == "name_content_mismatch" and f["level"] == "watch", (name, prof["findings"])
        assert f["params"]["named"] == named and f["params"]["detected"] == prof["format"]["label"], (name, f, prof["format"])
        assert prof["viewKind"] == view and prof["format"]["ext"] not in (name.rsplit(".", 1)[1], "fastqsanger"), (name, prof)
    # A real PNG named .png is an image, unassessed, no mismatch.
    png = _prof(_w(tmp, "ok.png", b"\x89PNG\r\n\x1a\n" + b"\x00" * 40))
    assert png["viewKind"] == "image" and png["quality"] == "unassessed" and png["format"]["ext"] == "png", png
    # FASTQ content validation: quality length must match the sequence.
    fq = _prof(_w(tmp, "half.fastq", "@r1\nACGTACGT\n+\nII\n@r2\nACGT\n+\nIIII\n"))
    assert fq["viewKind"] == "reads" and _codes(fq)["fastq_malformed_records"]["params"]["count"] == 1, fq


def test_r9_one_nul_deep_in_a_csv_is_not_binary(tmp):
    path = _w(tmp, "nul.csv", ("a,b\n" + "1,2\n" * 5000 + "3,\x004\n").encode())
    prof = _prof(path)
    assert prof["viewKind"] == "table" and prof["shape"]["rows"] == 5001, prof
    assert _codes(prof)["nul_bytes"]["params"] == {"lines": 1}
    assert dp.read_rows(path)["tabular"] is True


# ---------------------------------------------------------------------------
# R10 — ragged rows, h5ad -1 shape, FASTA cap, IUPAC, BED header line
# ---------------------------------------------------------------------------
def test_r10_ragged_rows_are_reported_not_truncated(tmp):
    path = _w(tmp, "ragged.csv", "a,b\n1,2,3\n4,5,6\n7,8,9\n")
    prof = _prof(path)
    assert _codes(prof)["ragged_rows"]["params"] == {"count": 3, "expected": 2}, prof["findings"]
    assert prof["columns"] == ["a", "b", "column_3"] and dp.read_rows(path)["columns"] == ["a", "b", "column_3"]


def test_r10_h5ad_negative_shape_uses_obs_var_sizes(tmp):
    path = _w(tmp, "a.h5ad", b"\x89HDF\r\n\x1a\n" + b"\x00" * 64)

    class Stub:
        GENERIC_EXTS = frozenset({"data", "binary", "txt", "text", "tabular", "tsv"})

        def identify(self, path, name):
            return "h5ad"

        def metadata(self, path, ext):
            return {"shape": [-1, -1], "obs_size": 2700, "var_size": 32738, "obs_layers": ["n_genes"]}

        def label_for(self, ext):
            return "AnnData (h5ad)"

        def spec_column_names(self, ext):
            return None

    saved = list(dp._GF_MODULE)
    dp._GF_MODULE[:] = [Stub()]
    try:
        prof = _prof(path)
    finally:
        dp._GF_MODULE[:] = saved
    assert prof["stats"] == [{"code": "cells", "value": 2700}, {"code": "genes", "value": 32738}], prof
    assert prof["viewKind"] == "anndata" and prof["quality"] == "unassessed", prof


def test_r10_fasta_cap_holds_inside_one_record_and_iupac_is_nucleotide(tmp):
    path = _w(tmp, "chr.fa", ">chr1\n" + ("ACGTACGTAC" * 6 + "\n") * 2000)
    saved = dp.MAX_FASTA_BYTES
    dp.MAX_FASTA_BYTES = 10_000
    try:
        prof = _prof(path)
    finally:
        dp.MAX_FASTA_BYTES = saved
    f = _codes(prof)["fasta_sequences"]["params"]
    assert f["at_least"] is True and f["total"] < 10_000, f
    assert prof["stats"][0] == {"code": "sequences", "value": 1, "atLeast": True}, prof["stats"]
    iupac = _codes(_prof(_w(tmp, "iupac.fa", ">r\nACGTRYKMSWACGTACGT\n")))
    assert iupac["fasta_sequences"]["params"]["unit"] == "bp" and "fasta_protein" not in iupac, iupac
    prot = _codes(_prof(_w(tmp, "p.fa", ">p\nMKTAYIAKQRQISFVKSHFSRQ\n")))
    assert prot["fasta_sequences"]["params"]["unit"] == "aa"


def test_r10_bed_column_name_line_is_the_header_not_a_row(tmp):
    path = _w(tmp, "hdr.bed", "chrom\tstart\tend\nchr1\t10\t20\nchr1\t30\t40\n")
    prof = _prof(path)
    assert prof["columns"] == ["chrom", "start", "end"] and prof["shape"]["rows"] == 2, prof
    page = dp.read_rows(path)
    assert page["rows"] == [["chr1", "10", "20"], ["chr1", "30", "40"]] and page["totalRows"] == 2, page


# ---------------------------------------------------------------------------
# R12 — bounded memory on wide matrices
# ---------------------------------------------------------------------------
def test_r12_wide_matrix_holds_a_bounded_number_of_cells(tmp):
    width = 400
    path = _w(tmp, "wide.tsv", "gene\t" + "\t".join(f"S{j}" for j in range(width)) + "\n" +
              "".join(f"G{i}\t" + "\t".join(str((i * j) % 97) for j in range(width)) + "\n" for i in range(300)))
    saved = dp.MAX_PROFILE_CELLS
    dp.MAX_PROFILE_CELLS = 20_000
    try:
        header, rows, total = dp._read_table(path)
        prof = _prof(path)
    finally:
        dp.MAX_PROFILE_CELLS = saved
    assert total == 300 and sum(len(r) for r in rows) <= 20_000 and len(rows) < 300, (len(rows), total)
    assert prof["shape"]["rows"] == 300 and prof["profiledRows"] == len(rows), prof
    assert _codes(prof)["profiled_subset"]["params"] == {"profiled": len(rows), "rows": 300}


# ---------------------------------------------------------------------------
# U4 / contract (a)(b)(c) — unassessed verdict, view kinds, stats per kind
# ---------------------------------------------------------------------------
def test_u4_unassessed_not_watch_for_files_not_analysed(tmp):
    for name, data, view in (("img.png", b"\x89PNG\r\n\x1a\n" + b"\x00" * 64, "image"),
                             ("doc.pdf", b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n" + b"\x00" * 64, "document"),
                             ("a.zip", b"PK\x03\x04" + b"\x00" * 64, "archive"),
                             ("cfg.json", '{"a": [1, 2], "b": null}', "json"),
                             ("m.mtx", "%%MatrixMarket matrix coordinate integer general\n3 2 2\n1 1 4\n2 2 1\n", "matrix")):
        prof = _prof(_w(tmp, name, data))
        assert prof["quality"] == "unassessed" and prof["viewKind"] == view, (name, prof)
        assert all(f["level"] == "info" for f in prof["findings"]), (name, prof["findings"])


def test_contract_stats_per_kind(tmp):
    def stats(name, data):
        return {s["code"]: s["value"] for s in _prof(_w(tmp, name, data))["stats"]}

    assert stats("t.csv", "a,b\n1,2\n3,4\n5,6\n") == {"rows": 3, "columns": 2}
    assert stats("r.fastq", "@r1\nACGT\n+\nIIII\n@r2\nACG\n+\nIII\n") == {"reads": 2, "read_length": 4}
    assert stats("v.vcf", "##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\ts1\ts2\n"
                          "1\t5\t.\tA\tG\t.\t.\t.\tGT\t0/1\t1/1\n") == {"variants": 1, "samples": 2}
    assert stats("s.fa", ">a\nACGT\n>b\nGG\n") == {"sequences": 2, "bases": 6}
    assert stats("m.mtx", "%%MatrixMarket matrix coordinate integer general\n3 2 2\n1 1 4\n2 2 1\n") == \
        {"rows": 3, "columns": 2, "entries": 2}
    assert stats("x.bed", "chr1\t1\t5\nchr1\t9\t12\n") == {"regions": 2, "columns": 3}
    assert stats("j.json", '{"a": 1, "b": 2}') == {"entries": 2}
    assert stats("i.png", b"\x89PNG\r\n\x1a\n" + b"\x00" * 16) == {}


# ---------------------------------------------------------------------------
# Backend copy — en wording, no raw exception text / paths, count-safe
# ---------------------------------------------------------------------------
def test_copy_no_paths_or_raw_errors_and_count_safe_text(tmp):
    missing = os.path.join(tmp, "perception_abc_missing.csv")
    prof = _prof(missing)
    assert prof["findings"][0]["code"] == "file_not_found" and tmp not in " ".join(prof["notes"]), prof["notes"]
    bad = _prof(_w(tmp, "bad.yaml", "key: [unclosed"))
    assert bad["findings"][0]["params"]["error"] == "the YAML is not valid" and "line" not in bad["notes"][0], bad
    big = _w(tmp, "many.fastq", "".join(f"@r{i}\nACGT\n+\nIIII\n" for i in range(4100)))
    fq = _prof(big)
    assert "at least 4,000" in " ".join(fq["signalSummary"]) and "≥" not in " ".join(fq["signalSummary"]), fq
    tbl = _prof(_table(tmp, "c.csv", ["k", "const", "label"], [[i, "X", "a" if i % 2 else "b"] for i in range(200)]))
    text = " ".join(tbl["notes"] + (tbl.get("signalSummary") or []))
    assert "(s)" not in text and "Constant columns" in text, text


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
    print(f"\n{len(tests) - failed}/{len(tests)} dataset-audit tests passed.")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
