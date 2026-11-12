"""
Unit tests for the folder profiler (galaxy/ai/folder_profile.py).

* Galaxy's own pairing spec (lib/galaxy/model/dataset_collections/auto_pairing_spec.yml) is
  copied below as SPEC_CASES and run against BOTH engines: the pure port, and Galaxy's
  auto_pairing source loaded by file path (its package __init__ needs SQLAlchemy/boltons,
  which a laptop lacks — the module itself only needs pydantic). When the yml is present in
  the checkout the copy is also checked against it, so the copy cannot drift.
* 10x recognition, roll-up, samplesheet, and the per-file context helpers.

Run standalone (no pytest needed):
    cd backend && python3.9 lib/galaxy/ai/tests/test_folder_profile.py
"""
from __future__ import annotations

import importlib.util
import os
import sys
import types

_HERE = os.path.dirname(os.path.abspath(__file__))
_MOD_PATH = os.path.abspath(os.path.join(_HERE, "..", "folder_profile.py"))
_spec = importlib.util.spec_from_file_location("_folder_profile_under_test", _MOD_PATH)
fp = importlib.util.module_from_spec(_spec)
sys.modules["_folder_profile_under_test"] = fp
_spec.loader.exec_module(fp)  # type: ignore[union-attr]

_DC_DIR = os.path.abspath(os.path.join(_HERE, "..", "..", "model", "dataset_collections"))

# Copied verbatim from auto_pairing_spec.yml (inputs → expected pairs).
SPEC_CASES = [
    ("Simple _R1 _R2 fastqs split.", ["input_R1.fastq", "input_R2.fastq"],
     {"input": ("input_R1.fastq", "input_R2.fastq")}),
    ("Compressed _R1 _R2 fastqs split.", ["input_R1.fastq.gz", "input_R2.fastq.gz"],
     {"input": ("input_R1.fastq.gz", "input_R2.fastq.gz")}),
    ("Joining common prefixes on _R1 _R2.",
     ["input541_R1.fastq", "input541_R2.fastq", "input521_R1.fastq", "input521_R2.fastq"],
     {"input541": ("input541_R1.fastq", "input541_R2.fastq"), "input521": ("input521_R1.fastq", "input521_R2.fastq")}),
    ("Simple .1.fastq/.2.fastq split.", ["input.1.fastq", "input.2.fastq"],
     {"input": ("input.1.fastq", "input.2.fastq")}),
    ("Simple .1.fastq.gz/.2.fastq.gz split.", ["input.1.fastq.gz", "input.2.fastq.gz"],
     {"input": ("input.1.fastq.gz", "input.2.fastq.gz")}),
    ("Simple _1/_2 split.", ["input_1.fastq", "input_2.fastq"],
     {"input": ("input_1.fastq", "input_2.fastq")}),
    ("Simple _1/_2 split on compressed files (.gz)", ["input_1.fastq.gz", "input_2.fastq.gz"],
     {"input": ("input_1.fastq.gz", "input_2.fastq.gz")}),
    ("Simple _1/_2 split on compressed files (.bz2)", ["input_1.fastq.bz2", "input_2.fastq.bz2"],
     {"input": ("input_1.fastq.bz2", "input_2.fastq.bz2")}),
]


class _El:
    def __init__(self, name):
        self.name = name


def _galaxy_auto_pairing():
    """Galaxy's auto_pairing.py loaded by path under a stub package (None if absent)."""
    src = os.path.join(_DC_DIR, "auto_pairing.py")
    if not os.path.exists(src):
        return None
    pkg = types.ModuleType("_galaxy_dc")
    pkg.__path__ = [_DC_DIR]  # type: ignore[attr-defined]
    sys.modules["_galaxy_dc"] = pkg
    try:
        for name in ("auto_identifiers", "auto_pairing"):
            spec = importlib.util.spec_from_file_location(f"_galaxy_dc.{name}", os.path.join(_DC_DIR, f"{name}.py"))
            mod = importlib.util.module_from_spec(spec)
            sys.modules[f"_galaxy_dc.{name}"] = mod
            spec.loader.exec_module(mod)  # type: ignore[union-attr]
        return sys.modules["_galaxy_dc.auto_pairing"]
    except Exception as exc:  # noqa: BLE001 — pydantic missing: parity check skipped, not failed silently
        print(f"NOTE Galaxy auto_pairing not loadable here ({exc}); parity check skipped")
        return None


def test_spec_copy_matches_galaxy_yml():
    yml = os.path.join(_DC_DIR, "auto_pairing_spec.yml")
    if not os.path.exists(yml):
        print("NOTE auto_pairing_spec.yml not in checkout; copy check skipped")
        return
    import yaml

    with open(yml) as f:
        cases = yaml.safe_load(f)
    as_tuples = [(c["doc"], c["inputs"], {k: (v["forward"], v["reverse"]) for k, v in c["paired"].items()}) for c in cases]
    assert as_tuples == SPEC_CASES, "SPEC_CASES drifted from auto_pairing_spec.yml"
    print("PASS test_spec_copy_matches_galaxy_yml")


def _pairs_of(pairs):
    return {name: (f.name, r.name) for name, f, r in pairs}


def test_fallback_passes_galaxy_spec():
    for doc, inputs, expected in SPEC_CASES:
        pairs, unpaired, _ft, engine, _why = fp.auto_pair([_El(n) for n in inputs], engine="fallback")
        assert engine == "fallback"
        assert _pairs_of(pairs) == expected, (doc, _pairs_of(pairs))
        assert unpaired == [], (doc, [u.name for u in unpaired])
    print("PASS test_fallback_passes_galaxy_spec")


def test_fallback_matches_galaxy_source():
    gal = _galaxy_auto_pairing()
    if gal is None:
        return
    extra = [
        ["S1_R1.fastq.gz", "S1_R2.fastq.gz", "S2_R1.fastq.gz"],
        ["a_1.fq", "a_2.fq", "b_1.fq", "c.fastq"],
        ["x.fastq", "y.fastq"],
        ["S1_L001_R1_001.fastq.gz", "S1_L001_R2_001.fastq.gz", "S1_L002_R1_001.fastq.gz", "S1_L002_R2_001.fastq.gz"],
        ["r.1.fastq", "r.2.fastq", "q_R1.fastq"],
    ]
    for doc, inputs, expected in SPEC_CASES:
        res = gal.auto_pair([_El(n) for n in inputs])
        assert {p.name: (p.forward.name, p.reverse.name) for p in res.paired} == expected, doc
    for inputs in [c[1] for c in SPEC_CASES] + extra:
        els = [_El(n) for n in inputs]
        g = gal.auto_pair(els)
        pairs, unpaired, ft, _e, _why = fp.auto_pair(els, engine="fallback")
        # Same FILE pairs as Galaxy wherever Galaxy's marker substitution is unambiguous (sample
        # names may differ: lanes are runs of one sample here).
        assert {(p.forward.name, p.reverse.name) for p in g.paired} == {(f.name, r.name) for _n, f, r in pairs}, inputs
        assert sorted(u.name for u in g.unpaired) == sorted(u.name for u in unpaired), inputs
        assert gal.guess_initial_filter_type(els) == ft, inputs
    print("PASS test_fallback_matches_galaxy_source")


def test_pairs_folder_paired_and_orphan():
    names = ["pairs/S1_R1.fastq.gz", "pairs/S1_R2.fastq.gz", "pairs/S2_R1.fastq.gz"]
    out = fp.profile_folder("pairs", names, engine="fallback")
    assert out["kind"] == "fastq_set" and out["fileCount"] == 3, out
    fq = out["fastq"]
    assert fq["verdict"] == "mixed" and fq["pairs"] == 1 and fq["pattern"] == "Rs", fq
    by = {s["sample"]: s for s in fq["samples"]}
    assert by["S1"]["status"] == "paired" and by["S1"]["forward"] == "pairs/S1_R1.fastq.gz" \
        and by["S1"]["reverse"] == "pairs/S1_R2.fastq.gz", by
    assert by["S2"]["status"] == "orphan" and by["S2"]["role"] == "forward", by
    assert fq["orphans"] == ["pairs/S2_R1.fastq.gz"], fq
    sheet = out["samplesheet"]
    assert sheet["rows"] == [["S1", "pairs/S1_R1.fastq.gz", "pairs/S1_R2.fastq.gz"], ["S2", "pairs/S2_R1.fastq.gz", ""]], sheet
    assert sheet["csv"].splitlines()[0] == "sample,fastq_1,fastq_2" and len(sheet["csv"].splitlines()) == 3, sheet["csv"]
    codes = {f["code"]: f for f in out["findings"]}
    assert codes["folder_fastq_orphan"]["params"] == {"name": "S2_R1.fastq.gz", "sample": "S2", "missing": "R2"}, codes
    assert codes["folder_fastq_orphan"]["level"] == "watch"
    assert "folder_fastq_mixed_layout" in codes and codes["folder_fastq_pairs"]["params"]["pairs"] == 1, codes
    assert out["rollup"] == [{"format": "fastq", "label": "FASTQ", "count": 3, "pairs": 1}], out["rollup"]
    print("PASS test_pairs_folder_paired_and_orphan")


def test_all_paired_and_single_end_verdicts():
    out = fp.profile_folder("", ["a_1.fq.gz", "a_2.fq.gz", "b_1.fq.gz", "b_2.fq.gz"], engine="fallback")
    assert out["fastq"]["verdict"] == "paired" and out["fastq"]["pairs"] == 2 and out["fastq"]["pattern"] == "illumina"
    assert not [f for f in out["findings"] if f["level"] != "info"], out["findings"]
    out = fp.profile_folder("se", ["se/x.fastq", "se/y.fastq.gz"], engine="fallback")
    assert out["fastq"]["verdict"] == "single_end" and {s["status"] for s in out["fastq"]["samples"]} == {"single"}
    assert "folder_fastq_single_end" in [f["code"] for f in out["findings"]]
    assert out["samplesheet"]["rows"] == [["x", "se/x.fastq", ""], ["y", "se/y.fastq.gz", ""]]
    # Same basenames in two subdirectories pair within their directory, never across.
    out = fp.profile_folder("runs", ["runs/a/S1_R1.fq", "runs/a/S1_R2.fq", "runs/b/S1_R1.fq", "runs/b/S1_R2.fq"], engine="fallback")
    assert out["fastq"]["pairs"] == 2 and out["fastq"]["verdict"] == "paired", out["fastq"]
    assert {(s["forward"], s["reverse"]) for s in out["fastq"]["samples"]} == {
        ("runs/a/S1_R1.fq", "runs/a/S1_R2.fq"), ("runs/b/S1_R1.fq", "runs/b/S1_R2.fq")}
    assert "folder_fastq_sample_runs" in [f["code"] for f in out["findings"]]
    print("PASS test_all_paired_and_single_end_verdicts")


MTX_HEAD = "%%MatrixMarket matrix coordinate integer general\n% tenx\n%\n5 5 8\n1 1 3\n"


def test_tenx_recognised_with_dims():
    names = ["tenx/matrix.mtx", "tenx/barcodes.tsv", "tenx/features.tsv"]
    seen = []

    def head(p):
        seen.append(p)
        return MTX_HEAD

    out = fp.profile_folder("tenx", names, read_head=head)
    assert out["kind"] == "tenx_matrix", out
    assert seen == ["tenx/matrix.mtx"], seen  # only the matrix head is read
    s = out["tenx"]["sets"][0]
    assert s["complete"] and s["version"] == "v3" and s["genes"] == 5 and s["cells"] == 5 and s["nnz"] == 8, s
    codes = {f["code"]: f for f in out["findings"]}
    assert codes["folder_tenx_recognised"]["params"]["cells"] == 5 and "folder_tenx_headerless" in codes, codes
    assert "fastq" not in out and "samplesheet" not in out
    print("PASS test_tenx_recognised_with_dims")


def test_tenx_variants():
    # Cell Ranger v2 (genes.tsv), gzip, nested filtered/raw dirs, GEO prefix.
    names = [
        "outs/filtered_feature_bc_matrix/matrix.mtx.gz", "outs/filtered_feature_bc_matrix/barcodes.tsv.gz",
        "outs/filtered_feature_bc_matrix/features.tsv.gz",
        "outs/raw_gene_bc_matrices/GRCh38/matrix.mtx", "outs/raw_gene_bc_matrices/GRCh38/barcodes.tsv",
        "outs/raw_gene_bc_matrices/GRCh38/genes.tsv",
        "outs/GSM1_matrix.mtx.gz", "outs/GSM1_barcodes.tsv.gz", "outs/GSM1_features.tsv.gz",
        "outs/metrics_summary.csv",
    ]
    out = fp.profile_folder("outs", names, read_head=lambda p: MTX_HEAD)
    sets = out["tenx"]["sets"]
    assert len(sets) == 3 and all(s["complete"] for s in sets), sets
    assert {s["dir"] for s in sets} == {"", "filtered_feature_bc_matrix", "raw_gene_bc_matrices/GRCh38"}, sets
    assert {s["version"] for s in sets} == {"v2", "v3"} and out["kind"] == "tenx_matrix"
    # Incomplete set and a lone matrix.
    out = fp.profile_folder("x", ["x/matrix.mtx", "x/barcodes.tsv"], read_head=lambda p: MTX_HEAD)
    assert out["tenx"]["sets"][0]["missing"] == ["features"] and "folder_tenx_incomplete" in [f["code"] for f in out["findings"]]
    out = fp.profile_folder("y", ["y/matrix.mtx"], read_head=lambda p: MTX_HEAD)
    assert "tenx" not in out, out
    # "mygenes.tsv" is not a 10x part (prefix must end at a separator).
    assert fp.tenx_sets(["z/matrix.mtx", "z/mygenes.tsv"]) == []
    # Unreadable matrix head: recognised without dims + a watch finding.
    out = fp.profile_folder("tenx", ["tenx/matrix.mtx", "tenx/barcodes.tsv", "tenx/features.tsv"], read_head=lambda p: None)
    codes = [f["code"] for f in out["findings"]]
    assert "folder_tenx_recognised_nodims" in codes and "folder_tenx_mtx_unreadable" in codes, codes
    print("PASS test_tenx_variants")


def test_rollup_mixed_folder():
    names = [f"m/S{i}_R{r}.fastq.gz" for i in range(1, 5) for r in (1, 2)] + ["m/a.csv", "m/b.csv", "m/notes", "m/x.weird"]
    out = fp.profile_folder("m", names)
    assert out["kind"] == "mixed" and out["fileCount"] == 12, out
    assert out["rollup"] == [
        {"format": "fastq", "label": "FASTQ", "count": 8, "pairs": 4},
        {"format": "csv", "label": "CSV", "count": 2},
        {"format": "unrecognised", "label": "", "count": 2},
    ], out["rollup"]
    assert fp.profile_folder("e", [])["kind"] == "empty"
    print("PASS test_rollup_mixed_folder")


def test_per_file_context_helpers():
    sib = ["pairs/S1_R1.fastq.gz", "pairs/S1_R2.fastq.gz", "pairs/S2_R1.fastq.gz", "other/S2_R2.fastq.gz"]
    lay = fp.fastq_layout("pairs/S1_R1.fastq.gz", sib)
    assert lay == {"status": "paired", "sample": "S1", "role": "forward", "mate": "S1_R2.fastq.gz", "pattern": "_R1/_R2"}, lay
    lay = fp.fastq_layout("pairs/S1_R2.fastq.gz", sib)
    assert lay["role"] == "reverse" and lay["mate"] == "S1_R1.fastq.gz", lay
    # The R2 in ANOTHER directory is not a mate.
    lay = fp.fastq_layout("pairs/S2_R1.fastq.gz", sib)
    assert lay["status"] == "orphan" and lay["role"] == "forward" and lay["mate"] is None, lay
    assert fp.fastq_layout("solo.fastq", [])["status"] == "single"
    assert fp.fastq_layout("a.csv", sib) is None
    tx = ["tenx/matrix.mtx", "tenx/barcodes.tsv", "tenx/features.tsv"]
    assert fp.tenx_member("tenx/features.tsv", tx) == {"role": "features", "version": "v3", "matrix": "matrix.mtx", "barcodes": "barcodes.tsv", "features": "features.tsv"}
    assert fp.tenx_member("tenx/barcodes.tsv", tx)["role"] == "barcodes"
    assert fp.tenx_member("tenx/features.tsv", ["tenx/features.tsv"]) is None
    print("PASS test_per_file_context_helpers")


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        t()
    print(f"\nAll {len(tests)} folder-profile tests passed.")


if __name__ == "__main__":
    main()
