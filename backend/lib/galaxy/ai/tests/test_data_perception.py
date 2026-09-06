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
    # header only, 0 data rows
    path = _write(tmp, "headeronly.csv", "a,b,label\n")
    prof = profile_dataset(path)
    assert prof["quality"] == "blocked", prof
    assert "leakage" not in prof and "classBalance" not in prof, prof

    # missing file
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


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    with tempfile.TemporaryDirectory() as tmp:
        for t in tests:
            t(tmp)
    print(f"\nAll {len(tests)} data-perception tests passed.")


if __name__ == "__main__":
    main()
