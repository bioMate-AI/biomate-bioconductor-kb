"""Tests for feature-flagged multi-omics integration chat routing.
Run: `cd backend && PYTHONPATH=lib python3.9 lib/galaxy/ai/multiomics/test_routing.py`
"""
from galaxy.ai.multiomics.routing import (
    detect_multiomics_intent, route_multiomics_result, _extract_modalities, _infer_goal,
)


def test_detect_two_modalities_with_integrate_verb():
    assert detect_multiomics_intent("integrate my RNA-seq and methylation data") is True
    assert detect_multiomics_intent("combine transcriptomics, proteomics and mutations") is True


def test_detect_rejects_single_modality_or_no_integrate():
    assert detect_multiomics_intent("run RNA-seq differential expression") is False   # 1 modality, no integrate
    assert detect_multiomics_intent("integrate this genome") is False                  # integrate verb but <2 omics
    assert detect_multiomics_intent("analyze my proteomics data") is False             # 1 modality


def test_extract_modalities_distinct_types():
    mods = _extract_modalities("fuse RNA, methylation, miRNA and drug-response matrices")
    dtypes = sorted(m.data_type for m in mods)
    assert dtypes == ["drug_response", "methylation", "mirna", "rna"], dtypes


def test_infer_goal():
    assert _infer_goal("integrate rna and methylation to find patient subtypes") == "clustering"
    assert _infer_goal("integrate rna and protein into shared latent factors") == "factors"
    assert _infer_goal("integrate rna and cnv") is None


def test_route_inert_when_flag_off():
    assert route_multiomics_result("integrate RNA and methylation", enabled=False) is None
    assert route_multiomics_result("integrate RNA and methylation", enabled=None) is None  # env unset → off


def test_route_returns_card_when_enabled():
    r = route_multiomics_result("integrate my RNA and proteomics data", enabled=True)
    assert r is not None
    assert r["source"] == "multiomics"
    ga = r["workflow_ga"]
    assert ga["method"] == "MOFA2"                       # default: paired continuous
    assert ga["nextflow_path"].endswith("mofa2/main.nf")
    assert ga["runnable"] is True
    assert ga["required_params"][0]["name"] == "omics"
    assert ga["normalization_plan"]["RNA"]               # normalization carried into the card
    assert ga["pipeline"] == ["normalize", "MOFA2"]      # 2-step: normalize THEN integrate
    assert "Normalize each modality" in ga["description"]


def test_route_clustering_goal_picks_snf():
    r = route_multiomics_result("combine RNA and methylation to cluster patients into subtypes", enabled=True)
    ga = r["workflow_ga"]
    assert ga["method"] == "SNF", ga["method"]
    assert ga["nextflow_path"].endswith("snf_multiomics/main.nf")
    assert ga["optional_params"][0]["name"] == "n_clusters"


def test_route_returns_none_for_non_integration():
    assert route_multiomics_result("call variants in this WGS sample", enabled=True) is None
    assert route_multiomics_result("screen these SMILES for hERG", enabled=True) is None


if __name__ == "__main__":
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    passed = 0
    for t in tests:
        try:
            t(); print(f"  PASS {t.__name__}"); passed += 1
        except Exception as e:
            print(f"  FAIL {t.__name__}: {e}")
    print(f"\n{passed}/{len(tests)} tests passed")
    raise SystemExit(0 if passed == len(tests) else 1)


# --- spatial modality + Chinese routing (SYSUCC: NPC spatial atlas, 中文 users) ---

def test_spatial_modality_is_detected():
    mods = _extract_modalities("integrate spatial transcriptomics with proteomics")
    assert sorted(m.data_type for m in mods) == ["proteomics", "spatial"]
    # Visium / MERFISH platform names also resolve to spatial
    assert any(m.data_type == "spatial" for m in _extract_modalities("fuse Visium and scRNA"))


def test_chinese_multiomics_request_full_pipeline():
    # 整合 RNA + 蛋白质组 + 代谢组 做分型  → intent, 3 modalities, clustering goal
    txt = "整合 RNA、蛋白质组和代谢组数据做患者分型"
    assert detect_multiomics_intent(txt) is True
    dtypes = sorted(m.data_type for m in _extract_modalities(txt))
    assert dtypes == ["metabolomics", "proteomics", "rna"], dtypes
    assert _infer_goal(txt) == "clustering"


def test_chinese_spatial_singlecell():
    txt = "融合空间转录组与单细胞数据"
    assert detect_multiomics_intent(txt) is True
    assert sorted(m.data_type for m in _extract_modalities(txt)) == ["scrna", "spatial"]


def test_proteomics_metabolomics_are_first_class_layers():
    # the core of the correction: proteomics+metabolomics alone must route
    txt = "jointly analyze proteomics and metabolomics for biomarker selection"
    assert detect_multiomics_intent(txt) is True
    assert sorted(m.data_type for m in _extract_modalities(txt)) == ["metabolomics", "proteomics"]
    assert _infer_goal(txt) == "feature_selection"


# ── A method the user NAMED is an instruction (dev 2026-11-11) ──────────────────────────────────
# "Integrate a multi-omics cohort (RNA, protein, methylation) with SNF" came back as a MOFA2 card:
# the selector reads the DATA SHAPE and nothing read the request's own method, so with no goal
# detected the cascade fell through to its MOFA2 default.
SNF_PROMPT = ("Integrate the attached multi-omics cohort with SNF: rna.csv, protein.csv and "
              "methyl.csv have features in rows and samples in columns. Intersect sample IDs, "
              "use n_clusters=3, and report integration QC and cross-layer driver evidence.")


def test_named_method_is_extracted_only_when_unambiguous_and_runnable():
    from galaxy.ai.multiomics.routing import named_method
    assert named_method(SNF_PROMPT) == "SNF"
    assert named_method("用 MOFA2 整合 RNA 和蛋白质组") == "MOFA2"
    assert named_method("integrate RNA and protein with similarity network fusion") == "SNF"
    assert named_method("Should I integrate RNA and protein with MOFA2 or SNF?") is None  # a question
    assert named_method("integrate RNA and protein with StabMap") is None                 # not packaged
    assert named_method("integrate RNA and protein") is None
    assert named_method("MFAP5 expression across RNA and protein") is None                # not a method


def test_named_method_decides_the_card_and_keeps_the_shape_recommendation_as_an_alternative():
    ga = route_multiomics_result(SNF_PROMPT, enabled=True)["workflow_ga"]
    assert ga["method"] == "SNF"
    assert ga["runnable"] is True
    assert ga["nextflow_path"].endswith("snf_multiomics/main.nf")
    assert ga["name"] == "Multi-omics integration — SNF"
    assert "MOFA2" in (ga["alternatives"] or []), "the shape-based pick is still reported"
    assert "You asked for SNF" in ga["scientific_rationale"]


def test_unnamed_request_still_uses_the_data_shape_selector():
    ga = route_multiomics_result("整合 RNA、蛋白质组和代谢组数据做患者分型", enabled=True)["workflow_ga"]
    assert ga["method"] == "SNF"          # clustering goal → SNF, unchanged
    ga2 = route_multiomics_result("integrate my RNA and protein tables", enabled=True)["workflow_ga"]
    assert ga2["method"] == "MOFA2"       # no goal, no named method → unchanged default
