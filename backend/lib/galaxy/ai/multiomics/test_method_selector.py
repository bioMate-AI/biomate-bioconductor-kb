"""Tests for the flexible multi-omics integration method selector.

Runnable two ways:
  - pytest:  PYTHONPATH=lib python3.9 -m pytest lib/galaxy/ai/multiomics/test_method_selector.py -q
  - direct:  python3.9 lib/galaxy/ai/multiomics/test_method_selector.py
"""
import os
import sys

try:
    from galaxy.ai.multiomics.method_selector import (
        recommend, select_method, sample_alignment, normalization_plan,
        normalization_for, Modality,
    )
except ImportError:  # standalone run
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from method_selector import (  # type: ignore
        recommend, select_method, sample_alignment, normalization_plan,
        normalization_for, Modality,
    )


def _mods(*specs):
    """specs: (name, data_type, sample_ids, n_features)"""
    return [dict(name=n, data_type=d, sample_ids=s, n_features=f) for (n, d, s, f) in specs]


def test_two_paired_continuous_picks_mofa2():
    ids = ["s1", "s2", "s3", "s4"]
    mods = _mods(("rna", "rna", ids, 20000), ("prot", "proteomics", ids, 5000))
    r = recommend(mods)  # no goal
    assert r["recommended_method"] == "MOFA2", r
    assert r["overlap_type"] == "fully_paired"
    assert r["n_modalities"] == 2


def test_clustering_goal_picks_snf():
    ids = ["s1", "s2", "s3"]
    mods = _mods(("rna", "rna", ids, 20000), ("meth", "methylation", ids, 15000))
    r = recommend(mods, goal="clustering")
    assert r["recommended_method"] == "SNF", r
    r2 = recommend(mods, goal="subtypes")
    assert r2["recommended_method"] == "SNF"


def test_high_dim_three_block_mixed_picks_mcia():
    ids = ["s%d" % i for i in range(30)]
    mods = _mods(
        ("expr", "rna", ids, 20000),
        ("meth", "methylation", ids, 15000),
        ("mir", "mirna", ids, 1000),
    )
    r = recommend(mods)  # 3 blocks, mixed types, high-dim, paired
    assert r["recommended_method"] == "MCIA", r
    assert r["overlap_type"] == "fully_paired"


def test_partial_overlap_is_mosaic_and_picks_stabmap():
    rna_ids = ["a", "b", "c", "d"]
    atac_ids = ["c", "d", "e", "f"]
    mods = _mods(("rna", "rna", rna_ids, 20000), ("atac", "scatac", atac_ids, 50000))
    r = recommend(mods)
    assert r["overlap_type"] == "partial_overlap", r
    assert r["recommended_method"] == "StabMap", r
    assert any("mosaic-capable" in w for w in r["warnings"]), r["warnings"]
    # dropped counts: intersection {c,d} → each block keeps 2, drops 2
    per = {m["name"]: m for m in r["aligned_samples"]["per_modality"]}
    assert per["rna"]["retained"] == 2 and per["rna"]["dropped"] == 2, per
    assert per["atac"]["retained"] == 2 and per["atac"]["dropped"] == 2, per


def test_single_cell_partial_flags_mosaic():
    # single-cell + non-identical sample sets → mosaic even if some overlap
    m1 = ["c1", "c2", "c3"]
    m2 = ["c2", "c3", "c4"]
    mods = _mods(("sc_rna", "scrna", m1, 25000), ("sc_atac", "scatac", m2, 60000))
    r = recommend(mods)
    assert r["single_cell"] is True
    assert r["recommended_method"] == "StabMap", r


def test_all_non_negative_paired_picks_intnmf():
    ids = ["s1", "s2", "s3"]
    mods = _mods(("rna", "rna", ids, 8000), ("mir", "mirna", ids, 1200))
    r = recommend(mods)  # both non-negative, 2 blocks (not high-dim-3), no goal
    assert r["recommended_method"] == "intNMF", r


def test_no_heavy_deps_constraint_picks_mfa():
    ids = ["s1", "s2", "s3"]
    mods = _mods(("rna", "rna", ids, 20000), ("prot", "proteomics", ids, 5000))
    r = recommend(mods, constraints={"no_heavy_deps": True})
    assert r["recommended_method"] == "MFA", r


def test_feature_selection_goal_picks_iclusterplus():
    ids = ["s1", "s2", "s3"]
    mods = _mods(("rna", "rna", ids, 20000), ("meth", "methylation", ids, 15000))
    r = recommend(mods, goal="feature_selection")
    assert r["recommended_method"] == "iClusterPlus", r


def test_normalization_plan_per_datatype():
    assert normalization_for("rna") == "log2-CPM"
    assert normalization_for("mirna") == "log2-CPM"
    assert normalization_for("scrna") == "log1p(CP10k)"
    assert normalization_for("methylation") == "M-value"
    assert normalization_for("scatac") == "TF-IDF"
    assert normalization_for("proteomics") == "log2 + median-centre"
    assert normalization_for("drug_response") == "quantile"
    assert normalization_for("metabolomics") == "quantile"
    assert normalization_for("mutation") == "pass-through"
    assert normalization_for("cnv") == "pass-through"
    assert normalization_for("totally_unknown") == "pass-through"
    plan = normalization_plan(_mods(("a", "rna", ["s1"], 100), ("b", "methylation", ["s1"], 100)))
    assert plan == {"a": "log2-CPM", "b": "M-value"}


def test_single_modality_is_degenerate():
    mods = _mods(("rna", "rna", ["s1", "s2"], 20000))
    r = recommend(mods)
    assert r["recommended_method"] is None, r
    assert any("single modality" in w for w in r["warnings"]), r["warnings"]


def test_empty_raises():
    raised = False
    try:
        recommend([])
    except ValueError:
        raised = True
    assert raised, "empty modality list should raise ValueError"


def test_modality_dataclass_and_dict_interchangeable():
    ids = ["s1", "s2", "s3"]
    as_dc = [Modality("rna", "rna", ids, None, 20000),
             Modality("prot", "proteomics", ids, None, 5000)]
    as_dict = _mods(("rna", "rna", ids, 20000), ("prot", "proteomics", ids, 5000))
    assert recommend(as_dc)["recommended_method"] == recommend(as_dict)["recommended_method"]


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    passed = 0
    for fn in fns:
        fn()
        print("  PASS", fn.__name__)
        passed += 1
    print("\n%d/%d tests passed" % (passed, len(fns)))
