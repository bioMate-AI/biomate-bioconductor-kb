"""
Behavioural tests for the ROUND-6 leftovers of the dataset-profiler audit (2026-11-12):

* 1 — FASTQ: the layout decision (single-end / paired-end) was stated twice — in a note AND in
  the plan ("treated as single-end unless a mate …" + "single-end pipeline suggested …"; "its
  mate … is in the same folder" + "Mate file in the same folder → paired-end"). The note now
  states what was observed, the plan what follows from it: each fact once.
* 2 — ``leaked_id`` could never fire: under the leave-one-out rule a value seen once carries no
  evidence, so an (almost) unique-per-row column never reached the accuracy threshold. A unique
  ID gives the group away through its NAME part ("ctrl_017", "KO-3"): the name stems are scored
  instead. A plain running ID (S0001 …), a UUID or a measurement still says nothing.
* 3 — the undecodable-byte counter was a process-global codec error handler under one fixed
  name, so a second copy of the module (another test suite, a re-import) took over the counting
  and the first copy reported 0 replaced bytes ("Good" for a damaged file) — the r2 test that
  failed only when the profiler suites ran in one pytest session.
* 4 — plate well names (A01 … H12, sample_A1, sample_B1) were read as sample groups A, B ….

Every test fails on the profiler at 64433d947b. Deterministic, no network.

Run standalone (no pytest needed):
    cd backend && python3.9 lib/galaxy/ai/tests/test_dataset_audit_r6_20261112.py
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


dp = _load("_dp_audit_r6_under_test", "data_perception.py")

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


def _texts(prof):
    """Every sentence the planning view shows: notes, plan observations and plan effects."""
    out = list(prof.get("notes") or [])
    for pi in prof.get("planImpact") or []:
        out += [pi["observed"], pi["effect"]]
    return out


def _fastq(tmp, name, n=20):
    rec = "".join(f"@r{i}\nACGTACGTAC\n+\nIIIIIIIIII\n" for i in range(n))
    return _w(tmp, name, rec)


# ---------------------------------------------------------------------------
# 1 — FASTQ: each layout fact once (note = observation, plan = decision)
# ---------------------------------------------------------------------------
def _count(texts, pattern):
    return sum(1 for t in texts if re.search(pattern, t, re.I))


def test_1_fastq_layout_decision_stated_once(tmp):
    path = _fastq(tmp, "S1_R1.fastq")
    sib = ["pairs/S1_R1.fastq", "pairs/S1_R2.fastq", "pairs/S2_R1.fastq", "pairs/plain.fastq"]
    cases = {
        "bare": dp.profile_dataset(path),
        "paired": dp.profile_dataset(path, name="pairs/S1_R1.fastq",
                                     context={"name": "pairs/S1_R1.fastq", "siblings": sib}),
        "orphan": dp.profile_dataset(path, name="pairs/S2_R1.fastq",
                                     context={"name": "pairs/S2_R1.fastq", "siblings": sib}),
        "named": dp.profile_dataset(path, name="pairs/plain.fastq",
                                    context={"name": "pairs/plain.fastq", "siblings": sib}),
    }
    for kind, prof in cases.items():
        texts = _texts(prof)
        assert prof["planImpact"], (kind, prof)
        # The decision (single-end / paired-end) is the plan's, said once.
        assert _count(texts, r"single-end|paired-end") == 1, (kind, texts)
        assert not re.search(r"single-end|paired-end", " ".join(prof["notes"]), re.I), (kind, prof["notes"])
        # The observation is the note's; the plan line does not restate it.
        assert _count(texts, r"same folder|in this folder|from the folder") <= 1, (kind, texts)
        _once(prof)
    assert "S1_R2.fastq" in " ".join(cases["paired"]["notes"])
    assert cases["orphan"]["quality"] == "watch" and "read-2" in " ".join(cases["orphan"]["notes"])


_FASTQ_NOTES = ("fastq_single_file", "fastq_paired_mate", "fastq_mate_missing", "fastq_single_end_named")


def test_1_fastq_copy_backend_equals_both_locales():
    root = os.path.abspath(os.path.join(_AI, "..", "..", "..", "..", "frontend", "client", "src", "locales"))
    for lng in ("en", "zh"):
        with open(os.path.join(root, lng, "common.json"), encoding="utf-8") as fh:
            msg = json.load(fh)["perception"]["msg"]
        for code in _FASTQ_NOTES + ("fastq_single_end", "fastq_paired_end", "fastq_orphan_single_end"):
            assert code in msg, (lng, code)
            if lng == "en":
                assert msg[code] == dp._EN_TEXT[code], (code, msg[code], dp._EN_TEXT[code])
            if code in _FASTQ_NOTES:  # the notes observe; the decision is the plan's
                assert not re.search(r"单端|双端" if lng == "zh" else r"single-end|paired-end", msg[code]), \
                    (lng, code, msg[code])


# ---------------------------------------------------------------------------
# 2 — leaked_id fires on an ID whose name part gives the group away
# ---------------------------------------------------------------------------
def _modelling(ids, labels, seed=6):
    rng = random.Random(seed)
    return [[i, lbl, rng.randint(1800, 2250), round(rng.uniform(1.5, 12), 2)] for i, lbl in zip(ids, labels)]


_MHEAD = ["sample_id", "condition", "expression", "mito_pct"]


def test_2_id_containing_the_group_is_a_leaked_id(tmp):
    labels = ["ctrl" if i % 2 == 0 else "treat" for i in range(80)]
    ids = [f"{lbl}_{i + 1:03d}" for i, lbl in enumerate(labels)]
    prof = dp.profile_dataset(_tsv(tmp, "ids.tsv", _MHEAD, _modelling(ids, labels)))
    by = _codes(prof)
    assert "leaked_id" in by and by["leaked_id"]["params"] == {"column": "sample_id"}, prof["findings"]
    assert by["leaked_id"]["level"] == "watch" and prof["quality"] == "watch", prof
    assert "drop_leaky_column" in by, prof["findings"]
    # Another naming style: genotype abbreviations with a dash.
    labels = ["WT" if i < 40 else "KO" for i in range(80)]
    ids = [f"{'wt' if lbl == 'WT' else 'ko'}-{i}" for i, lbl in enumerate(labels)]
    prof = dp.profile_dataset(_tsv(tmp, "geno.tsv", ["mouse", "group", "weight", "score"], _modelling(ids, labels)))
    assert _codes(prof).get("leaked_id", {}).get("params") == {"column": "mouse"}, prof["findings"]
    _once(prof)


def test_2_plain_unique_ids_and_measurements_are_not_leaks(tmp):
    labels = ["ctrl" if i % 2 == 0 else "treat" for i in range(80)]
    rng = random.Random(1)
    for ids in ([f"S{i + 1:04d}" for i in range(80)],                                   # running ID
                ["".join(rng.choice("0123456789abcdef") for _ in range(12)) for _ in range(80)],  # hex / UUID-like
                [rng.choice("ABCDEFGHJK") + rng.choice("LMNPQRST") + str(i) for i in range(80)],  # random codes
                [f"{rng.uniform(0, 1):.9f}" for _ in range(80)]):                         # a float measurement
        prof = dp.profile_dataset(_tsv(tmp, "plain.tsv", _MHEAD, _modelling(ids, labels)))
        by = _codes(prof)
        assert not {"leaked_id", "leaked_feature"} & set(by), (ids[:3], prof["findings"])


# ---------------------------------------------------------------------------
# 3 — replaced-byte counting belongs to each module copy
# ---------------------------------------------------------------------------
def test_3_replaced_bytes_counted_by_the_copy_that_reads(tmp):
    body = "gene,note\n" + "".join(f"G{i},naïve café\n" for i in range(50))
    path = _w(tmp, "damaged.csv", body.encode() + b"G99,bad\xff\xfebyte\n")
    other = _load("_dp_audit_r6_second_copy", "data_perception.py")  # registered AFTER dp
    for mod in (dp, other, dp):
        prof = mod.profile_dataset(path)
        assert _codes(prof).get("text_encoding_replaced", {}).get("params") == {"count": 2}, (mod.__name__, prof["findings"])
        assert prof["quality"] == "watch", (mod.__name__, prof["quality"])


# ---------------------------------------------------------------------------
# 4 — plate well names are positions, not groups
# ---------------------------------------------------------------------------
def test_4_well_names_are_not_sample_groups(tmp):
    for names in (["A01", "A02", "B01", "B02", "C01", "C02"],
                  ["sample_A1", "sample_B1", "sample_A2", "sample_B2"],
                  ["plate1_H12", "plate1_G11", "plate1_H11", "plate1_G12"],
                  ["D3.bam", "D4.bam", "E3.bam", "E4.bam"]):
        assert dp._sample_name_groups(names) is None, names
    # Real groups whose names merely end in a letter stay groups.
    assert dp._sample_name_groups(["KO1", "KO2", "WT1", "WT2"]) == [{"name": "KO", "n": 2}, {"name": "WT", "n": 2}]
    assert dp._sample_name_groups(["C1", "C2", "T1", "T2"]) == [{"name": "C", "n": 2}, {"name": "T", "n": 2}]
    assert dp._sample_name_groups(["ctrl_1", "ctrl_2", "treat_1"]) == [{"name": "ctrl", "n": 2}, {"name": "treat", "n": 1}]
    # End to end: a counts matrix with well-named columns states no groups.
    rows = [[f"ENSG{i:011d}", 1800 + i, 1900 + i, 2000 + i, 2100 + 2 * i] for i in range(40)]
    prof = dp.profile_dataset(_tsv(tmp, "wells.tsv", ["gene_id", "A01", "A02", "B01", "B02"], rows))
    assert "sample_groups_from_names" not in _codes(prof), prof["findings"]


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
    print(f"\n{len(tests) - failed}/{len(tests)} round-6 dataset-audit tests passed.")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
