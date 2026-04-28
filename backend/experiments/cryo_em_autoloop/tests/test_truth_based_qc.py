"""
Truth-based QC tests for the CryoEM auto-loop.

Every assertion is tied to a specific published source.  Where the evaluator's
internal threshold DIFFERS from the paper-cited value, a dedicated test
documents the discrepancy rather than hiding it.

Sources used:
  [VMAT2]   doi:10.1038/s41586-023-06328-6    (Lee lab, Nature 2023)
  [μOR]     doi:10.1016/j.cell.2022.06.017    (Cell 2022)
  [CaV1.2]  doi:10.1016/j.cell.2023.08.002    (Yan lab, Cell 2023)
  [GF-G6]   docs/cryo_em_skills/00_GENERAL_FRAMEWORK.md  G6 row
  [GF-G9]   docs/cryo_em_skills/00_GENERAL_FRAMEWORK.md  G9 row
  [GF-G10]  docs/cryo_em_skills/00_GENERAL_FRAMEWORK.md  G10 row
  [GF-P8]   docs/cryo_em_skills/00_GENERAL_FRAMEWORK.md  Principle 8
  [IDX]     docs/cryo_em_skills/00_INDEX.md   cross-cutting parameters
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest

# ── Path setup ────────────────────────────────────────────────────────────────
# Allow running tests from the repo root or from the experiments directory.
_EXPERIMENTS = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(_EXPERIMENTS))

from cryo_em_autoloop.qc_evaluator import (
    CryoEMQCEvaluator,
    QCAction,
    QC_PROFILES,
)
from cryo_em_autoloop.params import CryoEMParams
from cryo_em_autoloop.param_tuner import ParamTuner

# Import knowledge base from the sibling UX package
_UX_PKG = _EXPERIMENTS / "cryo_em_autoloop_ux"
sys.path.insert(0, str(_UX_PKG.parent))
from cryo_em_autoloop_ux.knowledge_base import GATE_KNOWLEDGE, KnowledgeEntry


# ── Helpers ───────────────────────────────────────────────────────────────────

def purified_evaluator() -> CryoEMQCEvaluator:
    return CryoEMQCEvaluator(profile="cryoem_spa_purified")


def default_params(**overrides) -> CryoEMParams:
    p = CryoEMParams()
    for k, v in overrides.items():
        setattr(p, k, v)
    return p


# ─────────────────────────────────────────────────────────────────────────────
# TestMotionDriftThreshold
# ─────────────────────────────────────────────────────────────────────────────

class TestMotionDriftThreshold:
    """
    The 50 Å total-drift limit is independently cited by three sources:
      - VMAT2 Nature 2023 (02_VMAT2_nature2023.md): "Motion (total): < 50 Å"
      - μOR Cell 2022 (05_muOR_cell2022.md): same threshold independently applied
      - General Framework G6 (00_GENERAL_FRAMEWORK.md):
        "| G6 | Motion correction | < 50 Å total drift | …|"

    The evaluator stores this as QC_PROFILES['cryoem_spa_purified']['max_total_drift_A'] = 50.0.
    """

    def test_profile_stores_50_angstrom_limit(self):
        """
        Source: 00_GENERAL_FRAMEWORK.md G6: '< 50 Å total drift'.
        Source: 02_VMAT2_nature2023.md Phase 3 Pre-processing: 'Motion (total): < 50 Å'.
        The evaluator threshold must be exactly 50.0 Å — the value cited by two independent
        published cryo-EM datasets.
        """
        threshold = QC_PROFILES["cryoem_spa_purified"]["max_total_drift_A"]
        assert threshold == 50.0, (
            f"Expected 50.0 Å (VMAT2/μOR/GF-G6 threshold); got {threshold}"
        )

    def test_pass_typical_vmat2_drift(self):
        """
        Source: 02_VMAT2_nature2023.md — VMAT2 dataset 1 achieved 2.7 Å final resolution,
        implying drift was well under 50 Å.  22 Å is representative of a well-corrected
        VMAT2-style dataset after MotionCor2 5×5 patch correction.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_A({"mean_total_drift_A": 22.0, "mean_per_frame_drift_A": 0.5})
        drift_gate = next(g for g in result.gate_results if g.gate == "motion_drift")
        assert drift_gate.action == QCAction.PASS, (
            f"22 Å drift should PASS (VMAT2 style); got {drift_gate.action}"
        )

    def test_pass_near_limit_45_angstrom(self):
        """
        Source: 00_GENERAL_FRAMEWORK.md G6: threshold is < 50 Å, so 45 Å must PASS.
        Testing the near-boundary case confirms the gate is strictly < 50 (not ≤ 45).
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_A({"mean_total_drift_A": 45.0, "mean_per_frame_drift_A": 0.5})
        drift_gate = next(g for g in result.gate_results if g.gate == "motion_drift")
        assert drift_gate.action != QCAction.HALT, (
            f"45 Å drift should not HALT (limit is 50 Å per GF-G6); got {drift_gate.action}"
        )

    def test_fail_just_over_limit_55_angstrom(self):
        """
        Source: 00_GENERAL_FRAMEWORK.md G6: '< 50 Å total drift'.
        55 Å is just over the 50 Å boundary — must trigger HALT.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_A({"mean_total_drift_A": 55.0, "mean_per_frame_drift_A": 0.5})
        drift_gate = next(g for g in result.gate_results if g.gate == "motion_drift")
        assert drift_gate.action == QCAction.HALT, (
            f"55 Å drift should HALT (over 50 Å limit); got {drift_gate.action}"
        )

    def test_fail_clearly_bad_100_angstrom(self):
        """
        Source: 00_GENERAL_FRAMEWORK.md G6 + 02_VMAT2_nature2023.md.
        100 Å total drift is double the limit; must HALT with no ambiguity.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_A({"mean_total_drift_A": 100.0, "mean_per_frame_drift_A": 0.5})
        drift_gate = next(g for g in result.gate_results if g.gate == "motion_drift")
        assert drift_gate.action == QCAction.HALT, (
            f"100 Å drift must HALT; got {drift_gate.action}"
        )

    def test_gate_reports_correct_threshold_value(self):
        """
        Source: 00_GENERAL_FRAMEWORK.md G6.
        The GateResult.threshold field must echo back 50.0 Å so audit logs
        are traceable to the published value.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_A({"mean_total_drift_A": 55.0, "mean_per_frame_drift_A": 0.5})
        drift_gate = next(g for g in result.gate_results if g.gate == "motion_drift")
        assert drift_gate.threshold == 50.0, (
            f"GateResult.threshold must be 50.0 Å; got {drift_gate.threshold}"
        )


# ─────────────────────────────────────────────────────────────────────────────
# TestCTFQualityThreshold
# ─────────────────────────────────────────────────────────────────────────────

class TestCTFQualityThreshold:
    """
    The papers cite CTFFIND4 raw FOM > 0.1 (CTFFIND4's own scale).
    The evaluator uses CryoSPARC's internal ctf/cross_corr_ctffind metric
    which runs on a different 0–1 scale with a practical quality floor of 0.70.

    Sources:
      - 02_VMAT2_nature2023.md: "CTF figure of merit threshold: > 0.1"
      - 03_CaV1_2_cell2023.md: "CTFFIND4: 30–5 Å, threshold CTF-FOM > 0.1"
      - knowledge_base.py finding for ctf_fit_quality gate:
        "Note: the FOM > 0.1 threshold applies to CTFFIND4's raw output;
         CryoSPARC's internal ctf/cross_corr_ctffind metric uses a different
         scale (0–1, with 0.70 being a practical quality floor)."
    """

    def test_ctf_metric_scale_documentation(self):
        """
        Source: 02_VMAT2_nature2023.md + 03_CaV1_2_cell2023.md + knowledge_base.py
        finding for ctf_fit_quality.

        This test explicitly documents the metric-scale discrepancy:
          - Papers cite CTFFIND4 FOM > 0.1  (raw CTFFIND4 output)
          - Evaluator uses min_ctf_fit_quality = 0.70  (CryoSPARC internal scale)

        The two numbers are NOT the same metric.  The evaluator threshold is
        0.70 (not 0.1) on the CryoSPARC scale.  This test asserts the ACTUAL
        evaluator threshold and prints a clear discrepancy notice.
        """
        actual_threshold = QC_PROFILES["cryoem_spa_purified"]["min_ctf_fit_quality"]
        paper_fom_threshold = 0.1  # CTFFIND4 raw FOM cited by VMAT2 + CaV1.2

        # The evaluator does NOT use 0.1 — document this explicitly.
        assert actual_threshold != paper_fom_threshold, (
            "UNEXPECTED: evaluator threshold equals paper's raw CTFFIND4 FOM (0.1). "
            "These are different metrics on different scales. If the evaluator changed "
            "to use 0.1, this test must be updated with a full scale justification."
        )
        assert actual_threshold == 0.70, (
            f"Evaluator min_ctf_fit_quality (CryoSPARC internal scale) expected 0.70; "
            f"got {actual_threshold}. "
            f"NOTE: paper threshold is 0.1 on the CTFFIND4 raw-FOM scale — different metric."
        )

    def test_pass_above_evaluator_threshold(self):
        """
        Source: qc_evaluator.py — min_ctf_fit_quality = 0.70 (CryoSPARC scale).
        A value of 0.85 must PASS the ctf_fit_quality gate.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_A({
            "mean_total_drift_A": 20.0,
            "mean_per_frame_drift_A": 0.5,
            "mean_ctf_fit_quality": 0.85,
            "mean_astigmatism_A": 500.0,
        })
        ctf_gate = next(g for g in result.gate_results if g.gate == "ctf_fit_quality")
        assert ctf_gate.action == QCAction.PASS, (
            f"CTF quality 0.85 (above 0.70 evaluator threshold) should PASS; got {ctf_gate.action}"
        )

    def test_pass_exactly_at_evaluator_threshold(self):
        """
        Source: qc_evaluator.py — action is HALT if ctf_quality < thresh_ctf (strict <).
        At exactly 0.70 the gate must PASS (not HALT).
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_A({
            "mean_total_drift_A": 20.0,
            "mean_per_frame_drift_A": 0.5,
            "mean_ctf_fit_quality": 0.70,
            "mean_astigmatism_A": 500.0,
        })
        ctf_gate = next(g for g in result.gate_results if g.gate == "ctf_fit_quality")
        assert ctf_gate.action == QCAction.PASS, (
            f"CTF quality exactly at threshold (0.70) should PASS (strict <); got {ctf_gate.action}"
        )

    def test_fail_below_evaluator_threshold(self):
        """
        Source: qc_evaluator.py — min_ctf_fit_quality = 0.70.
        A value of 0.65 is below the evaluator threshold and must HALT.
        NOTE: 0.65 is above the paper's raw CTFFIND4 FOM threshold (0.1) but on a
        completely different scale — reinforcing that the metrics are not comparable.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_A({
            "mean_total_drift_A": 20.0,
            "mean_per_frame_drift_A": 0.5,
            "mean_ctf_fit_quality": 0.65,
            "mean_astigmatism_A": 500.0,
        })
        ctf_gate = next(g for g in result.gate_results if g.gate == "ctf_fit_quality")
        assert ctf_gate.action == QCAction.HALT, (
            f"CTF quality 0.65 (below 0.70 evaluator threshold) should HALT; got {ctf_gate.action}"
        )

    def test_fail_clearly_bad_ctf(self):
        """
        Source: qc_evaluator.py — min_ctf_fit_quality = 0.70.
        A value of 0.30 is far below threshold and must HALT.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_A({
            "mean_total_drift_A": 20.0,
            "mean_per_frame_drift_A": 0.5,
            "mean_ctf_fit_quality": 0.30,
            "mean_astigmatism_A": 500.0,
        })
        ctf_gate = next(g for g in result.gate_results if g.gate == "ctf_fit_quality")
        assert ctf_gate.action == QCAction.HALT, (
            f"CTF quality 0.30 must HALT; got {ctf_gate.action}"
        )

    def test_gate_reports_evaluator_threshold_not_paper_threshold(self):
        """
        Source: qc_evaluator.py (actual behavior) vs. VMAT2/CaV1.2 papers (raw FOM).
        GateResult.threshold must be the evaluator's 0.70, not the paper's 0.1.
        This documents the scale difference in the audit trail.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_A({
            "mean_total_drift_A": 20.0,
            "mean_per_frame_drift_A": 0.5,
            "mean_ctf_fit_quality": 0.65,
            "mean_astigmatism_A": 500.0,
        })
        ctf_gate = next(g for g in result.gate_results if g.gate == "ctf_fit_quality")
        assert ctf_gate.threshold == 0.70, (
            f"GateResult.threshold must be the evaluator's 0.70 (CryoSPARC scale); "
            f"got {ctf_gate.threshold}. "
            f"Paper's CTFFIND4 FOM threshold (0.1) is a different metric."
        )


# ─────────────────────────────────────────────────────────────────────────────
# TestFSCResolutionCriterion
# ─────────────────────────────────────────────────────────────────────────────

class TestFSCResolutionCriterion:
    """
    The FSC 0.143 gold-standard criterion is the most consistently cited value
    across all studies.  The evaluator gate 'fsc_resolution' uses it.

    Sources:
      - 00_INDEX.md: "| FSC criterion | 0.143 (gold-standard) | …|"
      - 00_GENERAL_FRAMEWORK.md G10:
        "| G10 | Gold-standard FSC | 0.143 crossing visible (not just asymptote) | …|"
      - 02_VMAT2_nature2023.md: FSC 0.143 resolution 2.7 Å (Dataset 1), 2.9 Å (Dataset 2)
    """

    def test_pass_vmat2_dataset1_resolution(self):
        """
        Source: 02_VMAT2_nature2023.md — "FSC (0.143): 2.7 Å (Dataset 1)".
        2.7 Å is far better than the 20 Å gate limit → must PASS with GOLD level.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_E({"fsc_resolution_A": 2.7})
        fsc_gate = result.gate_results[0]
        assert fsc_gate.action == QCAction.PASS, (
            f"2.7 Å FSC (VMAT2 Dataset 1) should PASS; got {fsc_gate.action}"
        )
        from cryo_em_autoloop.qc_evaluator import QCLevel
        assert fsc_gate.level == QCLevel.GOLD, (
            f"2.7 Å FSC should be GOLD (≤ 4.0 Å); got {fsc_gate.level}"
        )

    def test_pass_vmat2_dataset2_resolution(self):
        """
        Source: 02_VMAT2_nature2023.md — "FSC (0.143): 2.9 Å (Dataset 2)".
        2.9 Å must also PASS with GOLD level.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_E({"fsc_resolution_A": 2.9})
        fsc_gate = result.gate_results[0]
        assert fsc_gate.action == QCAction.PASS, (
            f"2.9 Å FSC (VMAT2 Dataset 2) should PASS; got {fsc_gate.action}"
        )

    def test_pass_4_angstrom_resolution(self):
        """
        Source: 00_GENERAL_FRAMEWORK.md G10 — gate limit is 20 Å.
        4.0 Å is well within the acceptable zone → must PASS.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_E({"fsc_resolution_A": 4.0})
        fsc_gate = result.gate_results[0]
        assert fsc_gate.action == QCAction.PASS, (
            f"4.0 Å FSC should PASS; got {fsc_gate.action}"
        )

    def test_fail_25_angstrom_not_converged(self):
        """
        Source: 00_GENERAL_FRAMEWORK.md G10:
          '0.143 crossing visible (not just asymptote)'
        A 25 Å result indicates the map has not converged beyond background noise.
        The gate limit is 20 Å (QC_PROFILES['cryoem_spa_purified']['min_fsc_resolution_A']).
        25 Å > 20 Å limit → must HALT.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_E({"fsc_resolution_A": 25.0})
        fsc_gate = result.gate_results[0]
        assert fsc_gate.action == QCAction.HALT, (
            f"25 Å FSC (not converged per GF-G10) should HALT; got {fsc_gate.action}"
        )

    def test_gate_limit_is_20_angstrom(self):
        """
        Source: qc_evaluator.py QC_PROFILES — min_fsc_resolution_A = 20.0.
        The evaluator uses 20 Å as the gate (recognizable structure, per GF-G10 guidance
        of 'recognizable 3D structure at 15 Å').  The gate is permissive enough to pass
        initial convergence while still blocking noise maps.
        """
        threshold = QC_PROFILES["cryoem_spa_purified"]["min_fsc_resolution_A"]
        assert threshold == 20.0, (
            f"FSC gate limit expected 20.0 Å; got {threshold}"
        )

    def test_boundary_exactly_20_angstrom_passes(self):
        """
        Source: qc_evaluator.py — action is PASS if fsc_res <= thresh (≤ 20 Å passes).
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_E({"fsc_resolution_A": 20.0})
        fsc_gate = result.gate_results[0]
        assert fsc_gate.action == QCAction.PASS, (
            f"Exactly 20 Å FSC should PASS (≤ threshold); got {fsc_gate.action}"
        )

    def test_boundary_just_over_20_angstrom_halts(self):
        """
        Source: qc_evaluator.py — action is HALT if fsc_res > 20 Å.
        20.1 Å is just over; must HALT.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_E({"fsc_resolution_A": 20.1})
        fsc_gate = result.gate_results[0]
        assert fsc_gate.action == QCAction.HALT, (
            f"20.1 Å FSC should HALT (over 20 Å limit); got {fsc_gate.action}"
        )


# ─────────────────────────────────────────────────────────────────────────────
# TestParticleCountTargets
# ─────────────────────────────────────────────────────────────────────────────

class TestParticleCountTargets:
    """
    Cross-study targets from 00_INDEX.md:
      "| Final particle count | > 50K for routine; > 200K for < 3 Å |"
    The evaluator's particle_yield gate uses a dynamic min_particles_required
    passed in the metrics dict (default 5,000 from the code).

    Tests here check the evaluator's actual behavior and its relationship
    to the published targets (which are final-pipeline targets, not gate limits).
    """

    def test_50k_particles_does_not_halt(self):
        """
        Source: 00_INDEX.md — '> 50K for routine structures'.
        50,000 particles is the published minimum for routine structures.
        With the default min_particles_required (5,000), 50K must not HALT.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_B({
            "junk_fraction": 0.2,
            "num_particles_selected": 50_000,
            "min_particles_required": 5_000,
        })
        yield_gate = next(g for g in result.gate_results if g.gate == "particle_yield")
        assert yield_gate.action == QCAction.PASS, (
            f"50,000 particles (routine threshold per 00_INDEX.md) should PASS; "
            f"got {yield_gate.action}"
        )

    def test_200k_particles_does_not_halt(self):
        """
        Source: 00_INDEX.md — '> 200K for < 3 Å'.
        200,000 particles is the published target for sub-3 Å resolution.
        Must not HALT under any reasonable min_particles_required.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_B({
            "junk_fraction": 0.2,
            "num_particles_selected": 200_000,
            "min_particles_required": 5_000,
        })
        yield_gate = next(g for g in result.gate_results if g.gate == "particle_yield")
        assert yield_gate.action == QCAction.PASS, (
            f"200,000 particles (sub-3 Å target per 00_INDEX.md) should PASS; "
            f"got {yield_gate.action}"
        )

    def test_very_low_particle_count_halts(self):
        """
        Source: 00_INDEX.md — '> 50K for routine'.  500 particles is far below
        any published minimum; must HALT when below min_particles_required.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_B({
            "junk_fraction": 0.2,
            "num_particles_selected": 500,
            "min_particles_required": 5_000,
        })
        yield_gate = next(g for g in result.gate_results if g.gate == "particle_yield")
        assert yield_gate.action == QCAction.HALT, (
            f"500 particles (far below 5,000 minimum) should HALT; got {yield_gate.action}"
        )

    def test_below_minimum_required_halts(self):
        """
        Source: qc_evaluator.py evaluate_phase_B — gate passes if
        particle_count >= min_particles_required.
        Testing explicit boundary: count = min - 1 must HALT.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_B({
            "junk_fraction": 0.2,
            "num_particles_selected": 4_999,
            "min_particles_required": 5_000,
        })
        yield_gate = next(g for g in result.gate_results if g.gate == "particle_yield")
        assert yield_gate.action == QCAction.HALT, (
            f"4,999 particles (one below 5,000 minimum) should HALT; got {yield_gate.action}"
        )

    def test_at_minimum_required_passes(self):
        """
        Source: qc_evaluator.py evaluate_phase_B — count_ok = particle_count >= min_particles_required.
        At exactly the minimum, gate must PASS.
        """
        ev = purified_evaluator()
        result = ev.evaluate_phase_B({
            "junk_fraction": 0.2,
            "num_particles_selected": 5_000,
            "min_particles_required": 5_000,
        })
        yield_gate = next(g for g in result.gate_results if g.gate == "particle_yield")
        assert yield_gate.action == QCAction.PASS, (
            f"5,000 particles (at minimum) should PASS; got {yield_gate.action}"
        )


# ─────────────────────────────────────────────────────────────────────────────
# TestAbInitioRemediationDirection
# ─────────────────────────────────────────────────────────────────────────────

class TestAbInitioRemediationDirection:
    """
    Sources:
      - 00_GENERAL_FRAMEWORK.md: "Good 2D, bad 3D → Try 6–8 ab initio classes"
        (G9 row + failure-mode table)
      - 02_VMAT2_nature2023.md: "CryoSPARC Ab initio: Number of classes: 4"
        (VMAT2 used 4; framework says go to 6–8 when failing)

    The tuner must INCREASE num_ab_initio_classes, never decrease it.
    The cap is MAX_AB_INITIO_CLASSES = 8 (consistent with "6–8" from GF).
    """

    def test_remediation_increases_ab_initio_classes(self):
        """
        Source: 00_GENERAL_FRAMEWORK.md failure-mode table:
          'Good 2D, bad 3D → Try 6–8 ab initio classes'
        Starting from default (3 classes), remediation must produce more classes.
        """
        ev = purified_evaluator()
        qc_result = ev.evaluate_phase_D({
            "best_abinitio_class_score": 0.0,   # far below 0.10 threshold → HALT
            "best_abinitio_resolution_A": 12.0,  # within limit
        })
        assert qc_result.halts, "abinitio_class_score should have HALT'd"

        params = default_params(num_ab_initio_classes=3)
        tuner = ParamTuner()
        new_params, remediations = tuner.remediate(qc_result, params)

        assert new_params.num_ab_initio_classes > params.num_ab_initio_classes, (
            f"num_ab_initio_classes must INCREASE when ab initio fails "
            f"(GF: 'Try 6–8 classes'); "
            f"was {params.num_ab_initio_classes}, got {new_params.num_ab_initio_classes}"
        )

    def test_remediation_adds_two_classes(self):
        """
        Source: 00_GENERAL_FRAMEWORK.md — 'Try 6–8 ab initio classes'.
        Starting from 3 (VMAT2 used 4; GF target is 6–8).
        The tuner adds +2 per retry, which reaches 5, 7 over two iterations —
        within the 6–8 range after one or two retries.
        """
        ev = purified_evaluator()
        qc_result = ev.evaluate_phase_D({
            "best_abinitio_class_score": 0.0,
            "best_abinitio_resolution_A": 12.0,
        })
        params = default_params(num_ab_initio_classes=3)
        tuner = ParamTuner()
        new_params, _ = tuner.remediate(qc_result, params)

        assert new_params.num_ab_initio_classes == 5, (
            f"Expected +2 classes (3→5) per tuner rule; "
            f"got {new_params.num_ab_initio_classes}"
        )

    def test_remediation_does_not_exceed_cap_8(self):
        """
        Source: 00_GENERAL_FRAMEWORK.md — 'Try 6–8 ab initio classes'.
        The framework's upper end is 8. The tuner caps at MAX_AB_INITIO_CLASSES = 8.
        """
        ev = purified_evaluator()
        qc_result = ev.evaluate_phase_D({
            "best_abinitio_class_score": 0.0,
            "best_abinitio_resolution_A": 12.0,
        })
        params = default_params(num_ab_initio_classes=8)  # already at cap
        tuner = ParamTuner()
        new_params, _ = tuner.remediate(qc_result, params)

        assert new_params.num_ab_initio_classes == 8, (
            f"num_ab_initio_classes must not exceed 8 (GF cap); "
            f"got {new_params.num_ab_initio_classes}"
        )

    def test_remediation_never_decreases_classes(self):
        """
        Source: 00_GENERAL_FRAMEWORK.md — rationale is compositional diversity.
        Decreasing class count when ab initio fails would contradict the framework.
        """
        ev = purified_evaluator()
        qc_result = ev.evaluate_phase_D({
            "best_abinitio_class_score": 0.0,
            "best_abinitio_resolution_A": 12.0,
        })
        for starting_n in [3, 4, 5, 6]:
            params = default_params(num_ab_initio_classes=starting_n)
            tuner = ParamTuner()
            new_params, _ = tuner.remediate(qc_result, params)
            assert new_params.num_ab_initio_classes >= starting_n, (
                f"Remediation must never decrease num_ab_initio_classes "
                f"(GF: 'Try 6–8'); started {starting_n}, got {new_params.num_ab_initio_classes}"
            )


# ─────────────────────────────────────────────────────────────────────────────
# TestC1SymmetryPrinciple
# ─────────────────────────────────────────────────────────────────────────────

class TestC1SymmetryPrinciple:
    """
    Source: 00_GENERAL_FRAMEWORK.md Principle 8:
      "Never symmetrize without experimental evidence: Applying C2/D2/I symmetry
       speeds refinement but can mask asymmetric features.
       Start C1, verify symmetry from 2D classes."

    When orientation_anisotropy HALT fires, the remediation must NOT set
    symmetry to anything higher than C1.  The correct fix forces symmetry=C1
    (in case it was wrongly set) and increases 2D class count.
    """

    def test_anisotropy_remediation_sets_c1_symmetry(self):
        """
        Source: 00_GENERAL_FRAMEWORK.md Principle 8 + orientation_anisotropy failure mode.
        When preferred-orientation HALT triggers, symmetry must be C1.
        """
        ev = purified_evaluator()
        qc_result = ev.evaluate_phase_C({
            "orientation_anisotropy": 15.0,   # above 10.0 halt threshold → HALT
            "mean_class_quality": 0.8,
        })
        assert qc_result.halts, "orientation_anisotropy should have HALT'd"

        params = default_params(symmetry="C2")   # was wrongly set to C2
        tuner = ParamTuner()
        new_params, remediations = tuner.remediate(qc_result, params)

        assert new_params.symmetry == "C1", (
            f"Anisotropy remediation must set symmetry=C1 (GF Principle 8); "
            f"got '{new_params.symmetry}'"
        )

    def test_anisotropy_remediation_does_not_raise_symmetry(self):
        """
        Source: 00_GENERAL_FRAMEWORK.md Principle 8:
          'Start C1, verify symmetry from 2D classes.'
        When orientation_anisotropy fails, no remediation may result in
        a symmetry order HIGHER than C1 (i.e., C2, C3, D2, I, O, T, etc.).
        """
        ev = purified_evaluator()
        qc_result = ev.evaluate_phase_C({
            "orientation_anisotropy": 15.0,
            "mean_class_quality": 0.8,
        })

        for start_sym in ["C1", "C2", "C4", "D2"]:
            params = default_params(symmetry=start_sym)
            tuner = ParamTuner()
            new_params, _ = tuner.remediate(qc_result, params)
            # Only C1 is safe when anisotropy is detected
            assert new_params.symmetry == "C1", (
                f"Starting from symmetry={start_sym}: after anisotropy remediation "
                f"symmetry must be C1 (GF Principle 8); got '{new_params.symmetry}'"
            )

    def test_anisotropy_remediation_increases_2d_classes(self):
        """
        Source: 00_GENERAL_FRAMEWORK.md — orientation_anisotropy fix also increases
        num_2d_classes to better sample under-represented orientations.
        Combined with C1 symmetry, this is the documented two-part response.
        """
        ev = purified_evaluator()
        qc_result = ev.evaluate_phase_C({
            "orientation_anisotropy": 15.0,
            "mean_class_quality": 0.8,
        })
        params = default_params(num_2d_classes=100, symmetry="C1")
        tuner = ParamTuner()
        new_params, _ = tuner.remediate(qc_result, params)

        assert new_params.num_2d_classes > params.num_2d_classes, (
            f"Anisotropy remediation must increase num_2d_classes "
            f"(was {params.num_2d_classes}, got {new_params.num_2d_classes})"
        )

    def test_good_orientation_no_symmetry_change(self):
        """
        Source: 00_GENERAL_FRAMEWORK.md Principle 8 — symmetry must not be touched
        if anisotropy gate passes.
        When orientation is good, no remediation fires and symmetry is unchanged.
        """
        ev = purified_evaluator()
        qc_result = ev.evaluate_phase_C({
            "orientation_anisotropy": 2.0,   # well below 5.0 advisory threshold
            "mean_class_quality": 0.8,
        })
        assert not qc_result.halts, "Good orientation should not HALT"

        params = default_params(symmetry="C2")   # hypothetically set
        tuner = ParamTuner()
        new_params, remediations = tuner.remediate(qc_result, params)

        # No anisotropy remediation → symmetry untouched
        assert new_params.symmetry == "C2", (
            f"When orientation is good, tuner must not change symmetry; "
            f"got '{new_params.symmetry}'"
        )
        assert remediations == [], "No remediations expected when no gate halted"


# ─────────────────────────────────────────────────────────────────────────────
# TestKnowledgeBaseSourceIntegrity
# ─────────────────────────────────────────────────────────────────────────────

class TestKnowledgeBaseSourceIntegrity:
    """
    Structural integrity tests for knowledge_base.py.
    These verify that every citation is non-empty, properly formatted, and
    that specific known DOIs are (or are documented to be) present/absent.
    """

    _DOI_RE = re.compile(r"^10\.\d{4,}/\S+$")

    def test_every_entry_has_non_empty_source_text(self):
        """
        Source: knowledge_base.py integrity policy (docstring):
          'There are NO fabricated quotes. The source_text fields are
           copied verbatim from the files listed.'
        Empty source_text would violate the integrity contract.
        """
        for gate, entries in GATE_KNOWLEDGE.items():
            for i, entry in enumerate(entries):
                assert entry.source_text.strip() != "", (
                    f"gate='{gate}' entry[{i}] has empty source_text — "
                    f"violates knowledge base integrity policy"
                )

    def test_every_entry_has_valid_doi_format(self):
        """
        Source: knowledge_base.py — paper_doi must be a real DOI.
        DOIs start with '10.' followed by at least 4 digits, then '/'.
        An empty or malformed DOI makes citations untraceable.
        """
        for gate, entries in GATE_KNOWLEDGE.items():
            for i, entry in enumerate(entries):
                assert self._DOI_RE.match(entry.paper_doi), (
                    f"gate='{gate}' entry[{i}] paper_doi='{entry.paper_doi}' "
                    f"does not match DOI format '10.NNNN/...'"
                )

    def test_every_entry_has_non_empty_source_file(self):
        """
        Source: knowledge_base.py KnowledgeEntry docstring:
          'source_file: Path relative to /home/yzhang/biomate/ of the BioMate
           skill document that contains this claim.'
        Empty source_file makes the entry unverifiable.
        """
        for gate, entries in GATE_KNOWLEDGE.items():
            for i, entry in enumerate(entries):
                assert entry.source_file.strip() != "", (
                    f"gate='{gate}' entry[{i}] has empty source_file"
                )

    def test_vmat2_doi_appears_in_motion_drift_entries(self):
        """
        Source: 02_VMAT2_nature2023.md + 00_GENERAL_FRAMEWORK.md G6.
        VMAT2 doi 10.1038/s41586-023-06328-6 must appear in motion_drift entries
        because the paper directly provides the 50 Å threshold.
        """
        vmat2_doi = "10.1038/s41586-023-06328-6"
        motion_entries = GATE_KNOWLEDGE.get("motion_drift", [])
        assert motion_entries, "motion_drift gate has no knowledge entries"
        doi_set = {e.paper_doi for e in motion_entries}
        assert vmat2_doi in doi_set, (
            f"VMAT2 doi '{vmat2_doi}' not found in motion_drift entries. "
            f"Found: {doi_set}"
        )

    def test_cav12_doi_appears_in_ctf_fit_quality_entries(self):
        """
        Source: 03_CaV1_2_cell2023.md: 'CTFFIND4: 30–5 Å, threshold CTF-FOM > 0.1'
        CaV1.2 doi 10.1016/j.cell.2023.08.002 must appear in ctf_fit_quality entries
        as an independent confirmation of the CTFFIND4 threshold.
        """
        cav12_doi = "10.1016/j.cell.2023.08.002"
        ctf_entries = GATE_KNOWLEDGE.get("ctf_fit_quality", [])
        assert ctf_entries, "ctf_fit_quality gate has no knowledge entries"
        doi_set = {e.paper_doi for e in ctf_entries}
        assert cav12_doi in doi_set, (
            f"CaV1.2 doi '{cav12_doi}' not found in ctf_fit_quality entries. "
            f"Found: {doi_set}"
        )

    def test_muor_doi_not_yet_in_knowledge_base(self):
        """
        Source: honest gap documentation.
        The μOR Cell 2022 paper (doi:10.1016/j.cell.2022.06.017) independently
        confirms the 50 Å drift and FOM > 0.1 thresholds (05_muOR_cell2022.md),
        but has not yet been added as a KnowledgeEntry in knowledge_base.py.

        This test documents that gap explicitly so it is not overlooked.
        If the μOR DOI is added in the future, update this test to confirm
        it appears in the appropriate gates (motion_drift, ctf_fit_quality).
        """
        muor_doi = "10.1016/j.cell.2022.06.017"
        all_dois = {
            e.paper_doi
            for entries in GATE_KNOWLEDGE.values()
            for e in entries
        }
        assert muor_doi not in all_dois, (
            f"μOR doi '{muor_doi}' IS now present in knowledge_base.py. "
            f"Update this test: confirm it appears in motion_drift and "
            f"ctf_fit_quality entries, then change this assertion to a presence check."
        )

    def test_all_entries_have_non_empty_finding(self):
        """
        Source: knowledge_base.py KnowledgeEntry docstring:
          'finding: Plain-language summary of what this means for the tuning rule.'
        Empty finding means the knowledge entry provides no actionable guidance.
        """
        for gate, entries in GATE_KNOWLEDGE.items():
            for i, entry in enumerate(entries):
                assert entry.finding.strip() != "", (
                    f"gate='{gate}' entry[{i}] has empty finding"
                )

    def test_all_cited_gates_have_at_least_one_entry(self):
        """
        Source: knowledge_base.py all_cited_gates() helper.
        Every gate in GATE_KNOWLEDGE must have at least one KnowledgeEntry.
        """
        for gate, entries in GATE_KNOWLEDGE.items():
            assert len(entries) >= 1, (
                f"gate='{gate}' is listed in GATE_KNOWLEDGE but has no entries"
            )

    def test_knowledge_entries_cover_all_evaluated_gates(self):
        """
        Source: qc_evaluator.py — gates evaluated: motion_drift, per_frame_drift,
        ctf_fit_quality, astigmatism (phase A); junk_fraction, particle_yield (phase B);
        orientation_anisotropy, class_quality (phase C); abinitio_class_score,
        abinitio_resolution (phase D); fsc_resolution (phase E).

        Every gate that can HALT must have literature support in GATE_KNOWLEDGE.
        This test checks that the core HALT-capable gates are covered.
        """
        halt_capable_gates = {
            "motion_drift",
            "ctf_fit_quality",
            "astigmatism",
            "junk_fraction",
            "particle_yield",
            "orientation_anisotropy",
            "abinitio_class_score",
            "abinitio_resolution",
            "fsc_resolution",
        }
        covered = set(GATE_KNOWLEDGE.keys())
        missing = halt_capable_gates - covered
        assert not missing, (
            f"HALT-capable gates with no knowledge entries: {missing}. "
            f"Add citations to knowledge_base.py for these gates."
        )
