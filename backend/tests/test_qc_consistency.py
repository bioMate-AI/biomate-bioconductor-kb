"""
QC Consistency Tests

Verifies:
1. DEFAULT_THRESHOLDS contains all expected keys with scientifically-sound values
2. infer_qc_profile returns the correct named profile for every major workflow path
3. Segment-aware matching prevents false positives
4. All named profiles returned by infer_qc_profile actually exist in QC_NAMED_PROFILES
5. QC monitor correctly merges workflow_qc_params into gate thresholds
"""
import sys
from pathlib import Path

import pytest
from unittest.mock import MagicMock

sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

from galaxy.jobs.qc_trace_monitor import (
    NextflowQCGateHandler,
    DEFAULT_THRESHOLDS,
    QC_NAMED_PROFILES,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

BASE = "backend/biomni_workflows/nextflow_nfcore/subworkflows"
CANCER = "backend/biomni_workflows/nextflow_nfcore/subworkflows/cancer_biology"


def nf(path: str) -> str:
    """Append main.nf so paths mirror the real filesystem layout."""
    return f"{path}/main.nf"


# ===========================================================================
# 1. DEFAULT_THRESHOLDS — schema + value sanity
# ===========================================================================
class TestDefaultThresholds:
    REQUIRED_KEYS = [
        # Sequencing / alignment
        "alignment_rate", "reads_surviving_pct", "q30_pct", "assigned_reads_pct",
        # Coverage
        "mean_coverage",
        # PCR duplication
        "duplicate_pct",
        # Cryo-EM
        "fit_quality", "total_drift_angstrom", "astigmatism_angstrom", "correlation_score",
        "particles_picked",
        # Drug
        "docking_score_kcal_mol", "qsar_cv_r2",
        # NCA / PK
        "auc_extrap_pct_max",
        # Proteomics
        "psm_count", "protein_fdr_pct", "cv_pct",
    ]

    def test_all_required_keys_present(self):
        for key in self.REQUIRED_KEYS:
            assert key in DEFAULT_THRESHOLDS, f"Missing key: {key}"

    def test_all_values_are_floats(self):
        for k, v in DEFAULT_THRESHOLDS.items():
            assert isinstance(v, (int, float)), f"{k} value {v!r} is not numeric"

    def test_alignment_rate_default_is_70(self):
        assert DEFAULT_THRESHOLDS["alignment_rate"] == pytest.approx(70.0)

    def test_mean_coverage_default_is_20(self):
        assert DEFAULT_THRESHOLDS["mean_coverage"] == pytest.approx(20.0)

    def test_fit_quality_default_is_0_7(self):
        assert DEFAULT_THRESHOLDS["fit_quality"] == pytest.approx(0.7)

    def test_duplicate_pct_default_is_30(self):
        assert DEFAULT_THRESHOLDS["duplicate_pct"] == pytest.approx(30.0)

    def test_q30_pct_default_is_75(self):
        assert DEFAULT_THRESHOLDS["q30_pct"] == pytest.approx(75.0)

    def test_total_drift_angstrom_default_is_50(self):
        assert DEFAULT_THRESHOLDS["total_drift_angstrom"] == pytest.approx(50.0)

    def test_docking_score_is_negative(self):
        # Docking scores are negative; threshold should be a negative floor
        assert DEFAULT_THRESHOLDS["docking_score_kcal_mol"] < 0

    def test_protein_fdr_is_1_pct(self):
        assert DEFAULT_THRESHOLDS["protein_fdr_pct"] == pytest.approx(1.0)

    def test_no_zero_thresholds(self):
        """No threshold should be exactly zero — a zero threshold always triggers."""
        for k, v in DEFAULT_THRESHOLDS.items():
            assert v != 0, f"{k} has a zero threshold which would always fire"


# ===========================================================================
# 2. infer_qc_profile — correct profile per workflow path
# ===========================================================================
class TestInferQcProfile:
    # ── Somatic / Cancer ─────────────────────────────────────────────────────
    def test_somatic_cancer_biology_directory(self):
        path = nf(f"{CANCER}/detect_and_annotate_somatic_mutations")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "wgs_somatic_tumor_only"

    def test_somatic_mutect2_in_dirname(self):
        path = nf(f"{BASE}/genomics/mutect2_somatic_calling")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "wgs_somatic_tumor_only"

    def test_somatic_tumor_normal_dir(self):
        path = nf(f"{BASE}/genomics/tumor_normal_variant_calling")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "wgs_somatic_tumor_only"

    def test_somatic_ffpe_returns_wgs_ffpe(self):
        path = nf(f"{CANCER}/somatic_ffpe_variant_calling")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "wgs_ffpe"

    # ── Germline WGS ─────────────────────────────────────────────────────────
    def test_wgs_germline_standard(self):
        path = nf(f"{BASE}/genomics/wgs_germline_gatk")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "wgs_germline_standard"

    def test_wgs_lowpass(self):
        path = nf(f"{BASE}/genomics/wgs_lowpass_genotyping")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "wgs_germline_lowpass"

    # ── WES / Exome ───────────────────────────────────────────────────────────
    def test_wes_research(self):
        path = nf(f"{BASE}/genomics/whole_exome_sequencing")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "wes_research"

    def test_wes_clinical(self):
        path = nf(f"{BASE}/genomics/wes_clinical_diagnostics")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "wes_clinical_germline"

    def test_exome_dir(self):
        path = nf(f"{BASE}/genomics/exome_variant_calling")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "wes_research"

    # ── RNA-seq ───────────────────────────────────────────────────────────────
    def test_rnaseq_polya_standard(self):
        path = nf(f"{BASE}/transcriptomics/rnaseq_deseq2")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "rnaseq_polya_standard"

    def test_rnaseq_ribodepleted(self):
        path = nf(f"{BASE}/transcriptomics/rnaseq_ribodepleted_lncRNA")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "rnaseq_ribodepleted"

    def test_rnaseq_ffpe(self):
        path = nf(f"{BASE}/transcriptomics/rnaseq_ffpe_tumor")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "rnaseq_ffpe"

    def test_rnaseq_single_nucleus(self):
        path = nf(f"{BASE}/single_cell/snrna_seq_pipeline")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "rnaseq_single_nucleus"

    # ── ATAC-seq / ChIP-seq ───────────────────────────────────────────────────
    # No named profiles for these assays; infer_qc_profile returns None
    # and the monitor uses DEFAULT_THRESHOLDS.
    def test_atacseq_returns_none(self):
        path = nf(f"{BASE}/epigenomics/atacseq_peaks")
        assert NextflowQCGateHandler.infer_qc_profile(path) is None

    def test_chipseq_returns_none(self):
        path = nf(f"{BASE}/epigenomics/chipseq_histone_h3k27ac")
        assert NextflowQCGateHandler.infer_qc_profile(path) is None

    # ── Cryo-EM ───────────────────────────────────────────────────────────────
    def test_cryosparc_spa_purified(self):
        path = nf(f"{BASE}/cryo_em/cryosparc_standard_spa")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "cryoem_spa_purified"

    def test_cryosparc_membrane(self):
        path = nf(f"{BASE}/cryo_em/cryosparc_membrane_spa")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "cryoem_spa_membrane"

    def test_cryosparc_phase_plate(self):
        path = nf(f"{BASE}/cryo_em/cryosparc_phase_plate_spa")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "cryoem_spa_phase_plate"

    def test_cryosparc_lowdose(self):
        path = nf(f"{BASE}/cryo_em/cryosparc_lowdose_tilt")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "cryoem_spa_lowdose"

    def test_cryo_et_tomography(self):
        path = nf(f"{BASE}/cryo_et/et_full_pipeline")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "cryoem_tomo_in_situ"

    # ── Drug discovery ────────────────────────────────────────────────────────
    def test_admet_screening(self):
        path = nf(f"{BASE}/drug_discovery/admet_screening")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "compound_druglike"

    def test_docking(self):
        path = nf(f"{BASE}/drug_discovery/structure_prediction_docking")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "compound_druglike"

    # ── PK / NCA ─────────────────────────────────────────────────────────────
    # No named PK/NCA profile; sub-profiles are assay-specific; returns None
    def test_pharmacokinetics_returns_none(self):
        path = nf(f"{BASE}/drug_discovery/pharmacokinetics_nca_analysis")
        assert NextflowQCGateHandler.infer_qc_profile(path) is None

    def test_nca_standalone_returns_none(self):
        path = nf(f"{BASE}/clinical_pharmacology/nca_noncompartmental_analysis")
        assert NextflowQCGateHandler.infer_qc_profile(path) is None

    # ── Metagenomics ──────────────────────────────────────────────────────────
    # No generic metagenomics profile; user selects sub-profile explicitly
    def test_metagenomics_returns_none(self):
        path = nf(f"{BASE}/metagenomics/metagenomic_assembly")
        assert NextflowQCGateHandler.infer_qc_profile(path) is None

    # ── Unknown / no-match ────────────────────────────────────────────────────
    def test_unknown_path_returns_none(self):
        assert NextflowQCGateHandler.infer_qc_profile("unknown/pipeline/main.nf") is None

    def test_empty_path_returns_none(self):
        assert NextflowQCGateHandler.infer_qc_profile("") is None


# ===========================================================================
# 3. Segment-aware matching — no false positives
# ===========================================================================
class TestSegmentAwareMatching:
    """
    Paths that CONTAIN a keyword inside a longer compound name should not match
    the corresponding branch (e.g. 'cancer_biomarkers' ≠ 'cancer_biology').
    """

    def test_cancer_biomarkers_does_not_match_somatic(self):
        # 'cancer' appears in 'cancer_biomarkers_germline_annotation' but is NOT
        # in the cancer_biology domain directory
        path = nf(f"{BASE}/genomics/cancer_biomarkers_germline_annotation")
        result = NextflowQCGateHandler.infer_qc_profile(path)
        # Should be germline WGS (no 'cancer_biology' domain dir), not somatic
        assert result != "wgs_somatic_tumor_only"

    def test_somatic_only_in_longer_word_does_not_fire(self):
        # 'rheumatic_joint_disease' contains no 'somatic' segment
        path = nf("backend/workflows/rheumatic_joint_disease/main.nf")
        result = NextflowQCGateHandler.infer_qc_profile(path)
        assert result != "wgs_somatic_tumor_only"

    def test_scrna_within_rnaseq_dir_still_matches_scrna(self):
        path = nf(f"{BASE}/single_cell/scrna_seurat_pipeline")
        result = NextflowQCGateHandler.infer_qc_profile(path)
        # Should pick single-cell, not bulk rnaseq
        assert result == "scrna_perturbation"

    def test_metagenomics_word_returns_none_not_false_profile(self):
        # metagenomics branch returns None (sub-profiles are too specific to auto-infer)
        # Verify it returns None, not a non-existent generic profile name
        path = nf(f"{BASE}/metagenomics/metagenomic_assembly_pipeline")
        assert NextflowQCGateHandler.infer_qc_profile(path) is None

    def test_drug_path_does_not_match_rnaseq(self):
        path = nf(f"{BASE}/drug_discovery/admet_screening")
        result = NextflowQCGateHandler.infer_qc_profile(path)
        assert result not in ("rnaseq_polya_standard", "rnaseq_ffpe", "rnaseq_ribodepleted")

    def test_wgs_dir_containing_somatic_returns_somatic_profile(self):
        # Explicit: wgs directory that contains 'somatic' in dirname
        path = nf(f"{BASE}/genomics/wgs_somatic_mutect2")
        assert NextflowQCGateHandler.infer_qc_profile(path) == "wgs_somatic_tumor_only"


# ===========================================================================
# 4. All inferred profiles exist in QC_NAMED_PROFILES
# ===========================================================================
class TestProfilesExist:
    """Every profile returned by infer_qc_profile must be a valid named profile."""

    # Only paths where infer_qc_profile returns a non-None profile
    # (paths returning None are valid and skip this check)
    TEST_PATHS = [
        nf(f"{CANCER}/detect_and_annotate_somatic_mutations"),
        nf(f"{BASE}/genomics/wgs_germline_gatk"),
        nf(f"{BASE}/genomics/wgs_lowpass_genotyping"),
        nf(f"{BASE}/genomics/whole_exome_sequencing"),
        nf(f"{BASE}/genomics/wes_clinical_diagnostics"),
        nf(f"{BASE}/transcriptomics/rnaseq_deseq2"),
        nf(f"{BASE}/transcriptomics/rnaseq_ribodepleted_lncRNA"),
        nf(f"{BASE}/transcriptomics/rnaseq_ffpe_tumor"),
        nf(f"{BASE}/single_cell/snrna_seq_pipeline"),
        nf(f"{BASE}/single_cell/scrna_seurat_pipeline"),
        nf(f"{BASE}/cryo_em/cryosparc_standard_spa"),
        nf(f"{BASE}/cryo_em/cryosparc_membrane_spa"),
        nf(f"{BASE}/cryo_em/cryosparc_phase_plate_spa"),
        nf(f"{BASE}/cryo_em/cryosparc_lowdose_tilt"),
        nf(f"{BASE}/cryo_et/et_full_pipeline"),
        nf(f"{BASE}/drug_discovery/admet_screening"),
        nf(f"{BASE}/drug_discovery/structure_prediction_docking"),
    ]

    @pytest.mark.parametrize("path", TEST_PATHS)
    def test_inferred_profile_is_registered(self, path):
        profile = NextflowQCGateHandler.infer_qc_profile(path)
        if profile is not None:
            assert profile in QC_NAMED_PROFILES, (
                f"infer_qc_profile('{path}') returned '{profile}' "
                f"which is NOT in QC_NAMED_PROFILES"
            )


# ===========================================================================
# 5. DEFAULT_THRESHOLDS ↔ QC_NAMED_PROFILES override keys consistency
# ===========================================================================
class TestProfileOverrideKeysExistInDefaults:
    """
    Every key in a named profile's `overrides` dict should also be in
    DEFAULT_THRESHOLDS (or be a known metric key accepted by _get_threshold).
    This ensures profiles don't silently reference non-existent metrics.
    """

    # Metrics that are valid profile override keys but live outside DEFAULT_THRESHOLDS
    # (they are domain-specific parser outputs or computed values, not simple thresholds)
    KNOWN_PARSER_ONLY_METRICS = {
        # Cryo-EM orientation anisotropy
        "orientation_anisotropy_ratio",
        "anisotropy_ratio",
        "best_worst_ratio",
        "orientation_bias_ratio",
        # scRNA / CRISPR screen
        "median_genes_per_cell",
        "guide_library_coverage_pct",
        "transfection_efficiency_pct",
        "max_doublet_fraction_pct",
        # Metagenomics (classification threshold variant)
        "classified_pct_critical",
        # Proteomics
        "missed_cleavage_pct",
        # Drug / compound filter rules (integer counts, not float thresholds)
        "logp_limit",
        "hbd_limit",
        "hba_limit",
        # Alternative alignment metric name
        "min_assigned_reads_pct",
    }

    def test_all_override_keys_are_known(self):
        unknown = []
        for profile_name, profile in QC_NAMED_PROFILES.items():
            for key in profile.get("overrides", {}):
                if key not in DEFAULT_THRESHOLDS and key not in self.KNOWN_PARSER_ONLY_METRICS:
                    unknown.append(f"{profile_name}.{key}")
        assert unknown == [], (
            f"Named profiles reference unknown metric keys: {unknown}\n"
            "Add them to DEFAULT_THRESHOLDS or KNOWN_PARSER_ONLY_METRICS."
        )


# ===========================================================================
# 6. QC monitor threshold merge order
# ===========================================================================

def _make_handler(qc_profile=None, qc_overrides=None):
    """Create a minimal NextflowQCGateHandler for threshold merge testing."""
    return NextflowQCGateHandler(
        invocation_id="test_invocation",
        work_dir=Path("/tmp/qc_test"),
        sse_callback=MagicMock(),
        app=MagicMock(),
        qc_profile=qc_profile,
        qc_overrides=qc_overrides or {},
    )


class TestThresholdMergeOrder:
    """
    Verify that explicit qc_overrides take priority over named profile overrides.
    Uses a handler with a named profile + explicit override on the same metric.
    """

    def test_explicit_override_beats_profile(self):
        # rnaseq_ribodepleted sets alignment_rate=50.0
        # Explicit override: alignment_rate=55.0  → should win
        handler = _make_handler(
            qc_profile="rnaseq_ribodepleted",
            qc_overrides={"alignment_rate": 55.0},
        )
        effective = handler._get_threshold("alignment_rate", default=70.0)
        # Profile would have 50.0, explicit is 55.0 — explicit wins
        assert effective == pytest.approx(55.0)

    def test_named_profile_beats_default(self):
        # rnaseq_ribodepleted sets alignment_rate=50.0 (not 70.0 default)
        handler = _make_handler(qc_profile="rnaseq_ribodepleted")
        effective = handler._get_threshold("alignment_rate", default=70.0)
        # Profile override of 50.0 should be applied
        assert effective == pytest.approx(50.0)

    def test_default_used_when_no_profile_and_no_override(self):
        handler = _make_handler()
        effective = handler._get_threshold("alignment_rate", default=70.0)
        assert effective == pytest.approx(70.0)
