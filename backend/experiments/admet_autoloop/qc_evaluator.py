"""
ADMET QC evaluator.

Gate thresholds mirror BioMate's existing drug discovery QC logic:
  - assay_ingestion.py: _HERG_SAFETY_THRESHOLD_uM=10.0, _SAFETY_FLAG_TYPES
  - qc_trace_monitor.py: ADMET toxicity safety gate (lines 1033-1036)
  - ADMET_pred/main.nf: toxicity_report.json schema

In production, metrics come from toxicity_report.json produced by the
pharmacology/ADMET_pred Nextflow process.  In tests, pass synthetic dicts.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


# ── Shared result types (identical API to cryo_em_autoloop) ──────────────────

class QCAction(str, Enum):
    PASS = "pass"
    ADVISORY = "advisory"
    HALT = "halt"


class QCLevel(str, Enum):
    GOLD = "GOLD"
    SILVER = "SILVER"
    BRONZE = "BRONZE"
    FAIL = "FAIL"


class RegulatoryBasis(str, Enum):
    """
    Why this gate exists and what authority it carries.

    REGULATORY
        The gate directly implements a named regulatory criterion (FDA/ICH/EMA
        guidance).  Failing it means a specific regulatory action is required
        (conduct a clinical DDI study, file a genotoxicity package, etc.).
        Auto-loop MUST NOT substitute parameter tuning for that action — it
        should emit the guidance text and tell the user what they must do.

    RISK_STRATIFICATION
        The gate is anchored to peer-reviewed literature but no regulatory body
        mandates it.  Failing it is a risk signal — you may proceed, but should
        understand and document the risk.  Auto-loop parameter tuning is
        appropriate here because moving the filter changes the risk profile.

    OPERATIONAL
        BioMate convention with no external anchor, or a mathematical sanity
        check (mass balance, solver convergence).  Used for computational
        workflow quality, not drug-safety decisions.  Advisory only — never
        blocks an IND.
    """
    REGULATORY        = "REGULATORY"
    RISK_STRATIFICATION = "RISK_STRATIFICATION"
    OPERATIONAL       = "OPERATIONAL"


@dataclass
class GateResult:
    gate: str
    action: QCAction
    level: QCLevel
    value: float
    threshold: float
    message: str
    suggestion: str = ""
    regulatory_basis: RegulatoryBasis = RegulatoryBasis.OPERATIONAL

    @property
    def passed(self) -> bool:
        return self.action != QCAction.HALT


@dataclass
class PhaseQCResult:
    phase: str
    gate_results: list[GateResult] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return all(g.passed for g in self.gate_results)

    @property
    def halts(self) -> list[GateResult]:
        return [g for g in self.gate_results if g.action == QCAction.HALT]

    @property
    def overall_level(self) -> QCLevel:
        if any(g.level == QCLevel.FAIL for g in self.gate_results):
            return QCLevel.FAIL
        if any(g.level == QCLevel.BRONZE for g in self.gate_results):
            return QCLevel.BRONZE
        if any(g.level == QCLevel.SILVER for g in self.gate_results):
            return QCLevel.SILVER
        return QCLevel.GOLD


# ── QC profiles (mirrors assay_ingestion.py constants) ───────────────────────

QC_PROFILES: dict[str, dict[str, Any]] = {
    "admet_standard": {
        # hERG — ICH S7B empirical threshold (assay_ingestion.py line 25)
        "herg_ic50_threshold_uM": 10.0,
        # CiPA Tier 2 — qNET thresholds (Dutta et al. 2017 Front Physiol Table 2)
        # qNET < -40 pC/pF → LOW TdP risk  (repolarization reserve maintained)
        # -40 ≤ qNET < -30 → INTERMEDIATE
        # qNET ≥ -30       → HIGH (EAD-prone; proarrhythmic concern)
        "cipa_qnet_intermediate_threshold": -40.0,   # pC/pF
        "cipa_qnet_high_threshold":          -30.0,  # pC/pF
        "cipa_apd90_prolongation_pct_warn":   20.0,  # % vs baseline — advisory
        "cipa_apd90_prolongation_pct_halt":   30.0,  # % — HALT
        # DILI — Lammert 2010 model threshold
        "dili_probability_max": 0.5,
        "dili_risk_level_max": "medium",
        # DILI multi-endpoint (Dawson 2012 BSEP; Xu 2008 mito; Thompson 2006 RM alerts)
        # All RISK_STRATIFICATION — gates are advisory/halt based on probability
        "bsep_inhibition_probability_warn": 0.5,   # BSEP IC50 < ~10 µM (Dawson 2012)
        "bsep_inhibition_probability_halt": 0.75,  # Strong BSEP inhibitor
        "mito_tox_probability_warn":        0.5,   # MTP assay positive (Xu 2008)
        "mito_tox_probability_halt":        0.75,
        # Ames — ICH M7 (2014/2023) dual-model: structural alerts (Kazius 2005) +
        # statistical QSAR (e.g. Lhasa Nexus, Hansen 2009 RF, Enalos QSAR).
        # Both must be below threshold AND concordant for a PASS.
        # Discordant result → ADVISORY ("equivocal" per ICH M7 §5.1).
        "ames_probability_max":             0.5,   # alert-based model threshold
        "ames_statistical_probability_max": 0.5,   # statistical QSAR model threshold
        # Lipinski Rule of Five
        "logp_max": 5.0,
        "mw_max_da": 500.0,
        # CNS penetration profile (stricter)
        "tpsa_max_A2": 140.0,
    },
    "admet_cns": {
        "herg_ic50_threshold_uM": 10.0,
        "dili_probability_max": 0.4,
        "dili_risk_level_max": "low",
        "bsep_inhibition_probability_warn": 0.4,
        "bsep_inhibition_probability_halt": 0.6,
        "mito_tox_probability_warn":        0.4,
        "mito_tox_probability_halt":        0.6,
        "ames_probability_max":             0.3,
        "ames_statistical_probability_max": 0.3,
        "logp_max": 4.0,
        "mw_max_da": 450.0,
        "tpsa_max_A2": 90.0,
    },
    "admet_oncology": {
        "herg_ic50_threshold_uM": 5.0,
        "dili_probability_max": 0.6,
        "dili_risk_level_max": "high",
        "bsep_inhibition_probability_warn": 0.6,
        "bsep_inhibition_probability_halt": 0.85,  # higher tolerance in oncology
        "mito_tox_probability_warn":        0.6,
        "mito_tox_probability_halt":        0.85,
        "ames_probability_max":             0.6,
        "ames_statistical_probability_max": 0.6,
        "logp_max": 6.0,
        "mw_max_da": 700.0,
        "tpsa_max_A2": 180.0,
    },
    # Population PK (nlmixr2 / NONMEM-style) — Savic & Karlsson 2009 CPT:PSP thresholds
    "poppk_standard": {
        # ETA shrinkage: < 20% pass, 20-30% advisory, > 30% halt
        "eta_shrinkage_pct_warn": 20.0,  # % — ADVISORY
        "eta_shrinkage_pct_halt": 30.0,  # % — HALT (Savic & Karlsson 2009)
        # Condition number: < 100 pass, 100-1000 advisory, > 1000 halt
        "condition_number_warn": 100.0,
        "condition_number_halt": 1000.0,
    },
    # Stricter thresholds for IND-enabling PopPK (FDA 2019 Pop PK Guidance §V.C)
    "poppk_ind": {
        "eta_shrinkage_pct_warn": 15.0,
        "eta_shrinkage_pct_halt": 20.0,
        "condition_number_warn": 50.0,
        "condition_number_halt": 300.0,
    },
}

# Advisory band: metric/threshold between 1.0 and 1.15 → ADVISORY (not HALT)
ADVISORY_BAND = 1.15

_DILI_RISK_ORDER = {"low": 0, "medium": 1, "high": 2}


def _level_for_ratio(ratio: float, higher_is_worse: bool = True) -> QCLevel:
    """Map a metric / threshold ratio to a QC level (same as cryo_em_autoloop)."""
    if not higher_is_worse:
        ratio = 1 / ratio if ratio != 0 else math.inf
    if ratio <= 0.7:
        return QCLevel.GOLD
    if ratio <= 1.0:
        return QCLevel.SILVER
    if ratio <= ADVISORY_BAND:
        return QCLevel.BRONZE
    return QCLevel.FAIL


class ADMETQCEvaluator:
    """
    Evaluates ADMET safety metrics against profile thresholds.

    Metrics come from toxicity_report.json (pharmacology/ADMET_pred/main.nf):
      {
        "herg_ic50_uM":       float,   # hERG IC50 in µM (worst compound)
        "dili_risk":          str,     # "high" | "medium" | "low"
        "dili_probability":   float,   # 0-1
        "ames_positive":                bool,    # True = alert-based model predicts positive
        "ames_probability":             float,   # alert-based probability (Kazius 2005 alerts)
        "ames_statistical_probability": float,   # statistical QSAR probability (Hansen 2009 RF / Lhasa)
        "ames_statistical_positive":    bool,    # True = statistical model predicts positive
        "logP":               float,   # worst-case logP across compounds
        "mw":                 float,   # worst-case MW (Da)
      }
    """

    def __init__(self, profile: str = "admet_standard"):
        if profile not in QC_PROFILES:
            raise ValueError(
                f"Unknown QC profile: {profile!r}. Options: {list(QC_PROFILES)}"
            )
        self.profile = profile
        self.thresholds = QC_PROFILES[profile]

    # ── Phase evaluators ──────────────────────────────────────────────────────

    def evaluate_phase_2(self, metrics: dict) -> PhaseQCResult:
        """Full ADMET evaluation (hERG + DILI + multi-endpoint DILI + Ames + physicochemical)."""
        results: list[GateResult] = []
        results.extend(self._herg_gates(metrics))
        results.extend(self._dili_gates(metrics))
        results.extend(self._dili_multi_endpoint_gates(metrics))
        results.extend(self._ames_gates(metrics))
        results.extend(self._physicochemical_gates(metrics))
        return PhaseQCResult(phase="phase_2_admet_prediction", gate_results=results)

    def evaluate_phase_3(self, metrics: dict) -> PhaseQCResult:
        """hERG-only safety screen."""
        return PhaseQCResult(
            phase="phase_3_herg_screen",
            gate_results=self._herg_gates(metrics),
        )

    def evaluate_phase_4(self, metrics: dict) -> PhaseQCResult:
        """DILI + multi-endpoint DILI + Ames flags only."""
        results = (self._dili_gates(metrics)
                   + self._dili_multi_endpoint_gates(metrics)
                   + self._ames_gates(metrics))
        return PhaseQCResult(phase="phase_4_dili_ames", gate_results=results)

    def evaluate_phase_5(self, metrics: dict) -> PhaseQCResult:
        """
        CiPA Tier 2 cardiac safety evaluation.

        Reads from cipa_results.json (virtual_cell/cipa_cardiac_safety_ode).
        Metrics expected:
          qNET_drug_pCpF       float  — net charge per AP cycle (primary CiPA metric)
          APD90_change_pct     float  — APD90 prolongation vs baseline (%)
          EAD_probability      float  — 0–1 EAD score
          TdP_risk_category    str    — 'HIGH' | 'INTERMEDIATE' | 'LOW'
        """
        return PhaseQCResult(
            phase="phase_5_cipa_cardiac",
            gate_results=self._cipa_gates(metrics),
        )

    def evaluate_phase_6_poppk(self, metrics: dict) -> PhaseQCResult:
        """
        Population PK model diagnostics (nlmixr2 / NONMEM).

        Reads from nlmixr2_results.json produced by pharmacology/nlmixr2_population_pk.
        Metrics expected:
          convergence_status      str   — "converged" | "not_converged" | "failed"
          max_eta_shrinkage_pct   float — max ETA shrinkage % across random effects
          condition_number        float — covariance matrix condition number
        """
        return PhaseQCResult(
            phase="phase_6_poppk",
            gate_results=self._poppk_gates(metrics),
        )

    def evaluate_phase(self, phase: str, metrics: dict) -> PhaseQCResult:
        """Dispatch to the correct per-phase evaluator."""
        dispatch = {
            "phase_2_admet_prediction": self.evaluate_phase_2,
            "phase_3_herg_screen":      self.evaluate_phase_3,
            "phase_4_dili_ames":        self.evaluate_phase_4,
            "phase_5_cipa_cardiac":     self.evaluate_phase_5,
            "phase_6_poppk":            self.evaluate_phase_6_poppk,
        }
        fn = dispatch.get(phase)
        if fn is None:
            raise ValueError(f"Unknown phase: {phase!r}")
        return fn(metrics)

    # ── CiPA gates ────────────────────────────────────────────────────────────

    def _cipa_gates(self, metrics: dict) -> list[GateResult]:
        """
        CiPA Tier 2 gates: qNET (primary) + APD90 prolongation (secondary).

        Regulatory basis: ICH S7B (2021) integrated risk assessment framework.
        qNET thresholds from Dutta et al. 2017 Front Physiol 8:616, validated
        against the FDA CiPA 28-compound reference set.

        Advantage over single-channel hERG:
          Sensitivity:  ~89% (CiPA qNET) vs ~73% (hERG IC50 alone)
          Specificity:  ~85% (CiPA qNET) vs ~67% (hERG IC50 alone)
          Source: Li et al. 2019 J Pharmacol Toxicol Methods
        """
        results = []

        # ── Gate 1: qNET (primary CiPA proarrhythmia metric) ─────────────────
        qnet = float(metrics.get("qNET_drug_pCpF", metrics.get("ap_endpoints", {}).get("qNET_drug_pCpF", -50.0)))
        q_halt = self.thresholds.get("cipa_qnet_high_threshold", -30.0)
        q_warn = self.thresholds.get("cipa_qnet_intermediate_threshold", -40.0)

        # qNET: more negative = safer; less negative (toward 0) = more proarrhythmic
        if qnet >= q_halt:
            qnet_action = QCAction.HALT
        elif qnet >= q_warn:
            qnet_action = QCAction.ADVISORY
        else:
            qnet_action = QCAction.PASS

        # Ratio for level: distance from the halt threshold (higher ratio = worse)
        qnet_severity = (qnet - q_halt) / abs(q_halt) if q_halt != 0 else 0
        results.append(GateResult(
            gate="cipa_qnet",
            action=qnet_action,
            level=QCLevel.FAIL if qnet >= q_halt else (
                QCLevel.BRONZE if qnet >= q_warn else QCLevel.GOLD
            ),
            value=round(qnet, 2),
            threshold=q_halt,
            message=(
                f"qNET = {qnet:.1f} pC/pF "
                f"(CiPA HIGH risk threshold: ≥ {q_halt:.0f} pC/pF; "
                f"INTERMEDIATE: ≥ {q_warn:.0f} pC/pF)"
            ),
            suggestion=(
                "CiPA Tier 2 flags HIGH TdP risk. "
                "ICH S7B (2021): in vitro cardiomyocyte assay (CiPA Tier 3) "
                "required before first-in-human study. "
                "Single-channel hERG IC50 alone would miss balanced multi-channel "
                "blockers — qNET accounts for ICaL, INa, IKs protective effects."
            ) if qnet_action == QCAction.HALT else (
                "CiPA Tier 2 flags INTERMEDIATE TdP risk. "
                "Extended non-clinical cardiac profiling recommended per ICH S7B."
            ) if qnet_action == QCAction.ADVISORY else "",
            regulatory_basis=RegulatoryBasis.REGULATORY,
        ))

        # ── Gate 2: APD90 prolongation (secondary — corroborating evidence) ──
        apd_pct = float(metrics.get("APD90_change_pct",
                        metrics.get("ap_endpoints", {}).get("APD90_change_pct", 0.0)))
        apd_halt = self.thresholds.get("cipa_apd90_prolongation_pct_halt", 30.0)
        apd_warn = self.thresholds.get("cipa_apd90_prolongation_pct_warn", 20.0)

        if apd_pct >= apd_halt:
            apd_action = QCAction.HALT
        elif apd_pct >= apd_warn:
            apd_action = QCAction.ADVISORY
        else:
            apd_action = QCAction.PASS

        results.append(GateResult(
            gate="cipa_apd90_prolongation",
            action=apd_action,
            level=QCLevel.FAIL if apd_pct >= apd_halt else (
                QCLevel.BRONZE if apd_pct >= apd_warn else QCLevel.GOLD
            ),
            value=round(apd_pct, 1),
            threshold=apd_halt,
            message=f"APD90 prolongation {apd_pct:+.1f}% vs baseline (halt threshold: +{apd_halt:.0f}%)",
            suggestion=(
                "APD90 prolonged >{apd_halt:.0f}%. "
                "Corroborates qNET risk — consider ICaL/INa co-block profile "
                "to distinguish balanced from unbalanced hERG blockers."
            ).format(apd_halt=apd_halt) if apd_action == QCAction.HALT else "",
            regulatory_basis=RegulatoryBasis.RISK_STRATIFICATION,
        ))

        return results

    # ── PopPK gates ───────────────────────────────────────────────────────────

    def _poppk_gates(self, metrics: dict) -> list[GateResult]:
        """
        Population PK model diagnostic gates.

        Gate 1: poppk_convergence — REGULATORY
          FDA Pop PK Guidance 2019 §V.C: "a model that did not converge should
          not be used for labelling or dose recommendations." HALT on non-convergence.

        Gate 2: poppk_eta_shrinkage — RISK_STRATIFICATION
          Savic & Karlsson 2009 CPT:PSP 86(1):27-34: ETA shrinkage > 30% renders
          individual EBEs unreliable for post-hoc diagnostics. ADVISORY at > 20%.

        Gate 3: poppk_condition_number — RISK_STRATIFICATION
          Beal & Sheiner 1992; community convention: condition number > 1000 →
          near-collinear parameters; model likely over-parameterised.
        """
        results = []

        # ── Gate 1: convergence (REGULATORY) ─────────────────────────────────
        convergence = str(metrics.get("convergence_status", "converged")).lower()
        conv_failed = convergence not in ("converged", "true", "1", "yes", "ok")
        results.append(GateResult(
            gate="poppk_convergence",
            action=QCAction.HALT if conv_failed else QCAction.PASS,
            level=QCLevel.FAIL if conv_failed else QCLevel.GOLD,
            value=0.0 if conv_failed else 1.0,
            threshold=1.0,
            message=(
                f"PopPK model did not converge (status: {convergence}). "
                f"FDA Pop PK Guidance 2019: non-converged models cannot be used "
                f"for dosing recommendations or regulatory submissions."
                if conv_failed else
                f"Population PK model converged (status: {convergence})."
            ),
            suggestion=(
                "Simplify the structural model (try 1-compartment before 2-compartment). "
                "Increase max iterations (--max_iter 500). "
                "Check for data outliers or influential subjects. "
                "Review GOF plots for systematic misfit in any subpopulation."
            ) if conv_failed else "",
            regulatory_basis=RegulatoryBasis.REGULATORY,
        ))

        # ── Gate 2: ETA shrinkage (RISK_STRATIFICATION) ───────────────────────
        shrinkage = metrics.get("max_eta_shrinkage_pct")
        if shrinkage is not None:
            sh_halt = self.thresholds.get("eta_shrinkage_pct_halt", 30.0)
            sh_warn = self.thresholds.get("eta_shrinkage_pct_warn", 20.0)
            if shrinkage > sh_halt:
                sh_action, sh_level = QCAction.HALT, QCLevel.FAIL
            elif shrinkage > sh_warn:
                sh_action, sh_level = QCAction.ADVISORY, QCLevel.BRONZE
            else:
                sh_action, sh_level = QCAction.PASS, QCLevel.GOLD
            results.append(GateResult(
                gate="poppk_eta_shrinkage",
                action=sh_action,
                level=sh_level,
                value=round(float(shrinkage), 1),
                threshold=sh_halt,
                message=(
                    f"Max ETA shrinkage {shrinkage:.1f}% "
                    f"(halt threshold: > {sh_halt:.0f}%; advisory: > {sh_warn:.0f}%)"
                ),
                suggestion=(
                    "High ETA shrinkage makes individual Bayesian estimates (EBEs) "
                    "unreliable for per-subject diagnostics (DV vs IPRED, CWRES vs IPRED). "
                    "Use only population predictions for diagnostics. "
                    "Collect richer PK sampling, merge sparse occasions, "
                    "or simplify the between-subject variability (BSV) model "
                    "(remove IIV on poorly-estimated parameters). "
                    "Ref: Savic & Karlsson 2009 CPT:PSP 86(1):27-34."
                ) if sh_action != QCAction.PASS else "",
                regulatory_basis=RegulatoryBasis.RISK_STRATIFICATION,
            ))

        # ── Gate 3: condition number (RISK_STRATIFICATION) ────────────────────
        cond_num = metrics.get("condition_number")
        if cond_num is not None:
            cn_halt = self.thresholds.get("condition_number_halt", 1000.0)
            cn_warn = self.thresholds.get("condition_number_warn", 100.0)
            if cond_num > cn_halt:
                cn_action, cn_level = QCAction.HALT, QCLevel.FAIL
            elif cond_num > cn_warn:
                cn_action, cn_level = QCAction.ADVISORY, QCLevel.BRONZE
            else:
                cn_action, cn_level = QCAction.PASS, QCLevel.GOLD
            results.append(GateResult(
                gate="poppk_condition_number",
                action=cn_action,
                level=cn_level,
                value=round(float(cond_num), 1),
                threshold=cn_halt,
                message=(
                    f"Covariance matrix condition number {cond_num:.0f} "
                    f"(halt threshold: > {cn_halt:.0f}; advisory: > {cn_warn:.0f})"
                ),
                suggestion=(
                    "High condition number indicates near-collinear parameters — "
                    "the model is likely over-parameterised for the available data. "
                    "Fix one clearance or volume parameter to a literature value, "
                    "reduce to a simpler structural model, or reparameterise "
                    "(e.g. CL/F and V/F as a ratio). "
                    "Ref: Beal & Sheiner 1992 NONMEM Users Guide, Part V."
                ) if cn_action != QCAction.PASS else "",
                regulatory_basis=RegulatoryBasis.RISK_STRATIFICATION,
            ))

        return results

    # ── Private gate builders ─────────────────────────────────────────────────

    def _herg_gates(self, metrics: dict) -> list[GateResult]:
        results = []
        herg_ic50 = metrics.get("herg_ic50_uM", 999.0)
        thresh = self.thresholds["herg_ic50_threshold_uM"]
        # Lower IC50 = more cardiotoxic → higher is better
        ratio = thresh / herg_ic50 if herg_ic50 > 0 else math.inf
        action = QCAction.HALT if herg_ic50 < thresh else (
            QCAction.ADVISORY if herg_ic50 < thresh * ADVISORY_BAND else QCAction.PASS
        )
        results.append(GateResult(
            gate="herg_ic50",
            action=action,
            level=_level_for_ratio(ratio, higher_is_worse=True),
            value=herg_ic50,
            threshold=thresh,
            message=(
                f"hERG IC50 {herg_ic50:.2f} µM "
                f"({'below' if herg_ic50 < thresh else 'above'} safety threshold {thresh:.0f} µM)"
            ),
            suggestion=(
                "Tighten logP/MW filters to shift screened population toward "
                "compounds with lower hERG affinity (higher IC50). "
                "ICH S7B requires hERG assessment; 10 µM threshold is cross-pharma "
                "industry convention (Bowes 2012), not a stated ICH value."
            ) if action == QCAction.HALT else "",
            regulatory_basis=RegulatoryBasis.RISK_STRATIFICATION,
        ))
        return results

    def _dili_gates(self, metrics: dict) -> list[GateResult]:
        results = []

        # Probability gate (quantitative)
        dili_prob = metrics.get("dili_probability", 0.0)
        thresh_prob = self.thresholds["dili_probability_max"]
        ratio = dili_prob / thresh_prob if thresh_prob else 0.0
        action = QCAction.HALT if dili_prob > thresh_prob else (
            QCAction.ADVISORY if ratio > 0.85 else QCAction.PASS
        )
        results.append(GateResult(
            gate="dili_probability",
            action=action,
            level=_level_for_ratio(ratio),
            value=dili_prob,
            threshold=thresh_prob,
            message=f"DILI probability {dili_prob:.3f} (max {thresh_prob:.2f})",
            suggestion=(
                "Set logP ≤ 4.0 and MW ≤ 400 Da (Lammert 2010 risk-zone boundary). "
                "No FDA/ICH guideline mandates this screen — it is a literature-based "
                "risk-stratification filter, not a regulatory requirement."
            ) if action == QCAction.HALT else "",
            regulatory_basis=RegulatoryBasis.RISK_STRATIFICATION,
        ))

        # Risk-level gate (categorical: high > medium > low)
        dili_risk = str(metrics.get("dili_risk", "low")).lower()
        max_risk = str(self.thresholds.get("dili_risk_level_max", "medium")).lower()
        risk_num = _DILI_RISK_ORDER.get(dili_risk, 0)
        max_risk_num = _DILI_RISK_ORDER.get(max_risk, 1)
        risk_action = QCAction.HALT if risk_num > max_risk_num else (
            QCAction.ADVISORY if risk_num == max_risk_num else QCAction.PASS
        )
        results.append(GateResult(
            gate="dili_risk_level",
            action=risk_action,
            level=QCLevel.GOLD if risk_num == 0 else (
                QCLevel.SILVER if risk_num == 1 else QCLevel.FAIL
            ),
            value=float(risk_num),
            threshold=float(max_risk_num),
            message=f"DILI risk level '{dili_risk}' (max allowed '{max_risk}')",
            suggestion=(
                "Apply logP ≤ 4.0 and MW ≤ 400 Da filters (Lammert 2010 boundary). "
                "Risk-stratification only — no regulatory mandate requires this gate."
            ) if risk_action == QCAction.HALT else "",
            regulatory_basis=RegulatoryBasis.RISK_STRATIFICATION,
        ))

        return results

    def _dili_multi_endpoint_gates(self, metrics: dict) -> list[GateResult]:
        """
        DILI multi-endpoint gates — emitted ONLY when the corresponding fields are present.

        Gate 1: bsep_inhibition — RISK_STRATIFICATION
          BSEP (Bile Salt Export Pump, ABCB11) inhibition → bile acid accumulation →
          hepatocyte toxicity. A leading DILI mechanism (Morgan et al. 2010 Toxicol Sci;
          Dawson et al. 2012 Drug Metab Dispos). Probability from ML model trained on
          BSEP fluorescence assay data (IC50 < 10 µM threshold).
          Field: bsep_inhibition_probability (float 0–1)

        Gate 2: mito_toxicity — RISK_STRATIFICATION
          Mitochondrial toxicity (uncoupling, Complex I/III inhibition, mtDNA depletion).
          Associated with 49% of drug-induced hepatotoxicity (Xu 2008 Toxicol Sci).
          Probability from MTP (membrane potential) assay ML model.
          Field: mito_tox_probability (float 0–1)

        Gate 3: reactive_metabolites — RISK_STRATIFICATION (ADVISORY only, no halt)
          Structural alerts for reactive metabolite formation (Thompson 2006 Drug Metab Rev;
          Kalgutkar & Soglia 2005 Expert Opin Drug Metab Toxicol). Alerts: furan, aniline,
          nitro, Michael acceptor, quinone precursors, halogenated alkenes.
          Reactive metabolite covalent binding → idiosyncratic DILI / immune sensitisation.
          ADVISORY only: structural alert alone is not sufficient for termination — requires
          trapping assay (GSH, KCN, semicarbazide) to confirm.
          Field: reactive_metabolite_flag (bool) or reactive_metabolite_alerts (list[str])
        """
        results = []

        # ── Gate 1: BSEP inhibition ────────────────────────────────────────────
        bsep_prob = metrics.get("bsep_inhibition_probability")
        if bsep_prob is not None:
            bsep_prob = float(bsep_prob)
            bsep_halt = self.thresholds.get("bsep_inhibition_probability_halt", 0.75)
            bsep_warn = self.thresholds.get("bsep_inhibition_probability_warn", 0.5)
            if bsep_prob > bsep_halt:
                bsep_action, bsep_level = QCAction.HALT, QCLevel.FAIL
            elif bsep_prob > bsep_warn:
                bsep_action, bsep_level = QCAction.ADVISORY, QCLevel.BRONZE
            else:
                bsep_action, bsep_level = QCAction.PASS, QCLevel.GOLD
            results.append(GateResult(
                gate="bsep_inhibition",
                action=bsep_action,
                level=bsep_level,
                value=round(bsep_prob, 3),
                threshold=bsep_halt,
                message=(
                    f"BSEP inhibition probability {bsep_prob:.3f} "
                    f"(halt: > {bsep_halt:.2f}; advisory: > {bsep_warn:.2f})"
                ),
                suggestion=(
                    "BSEP (ABCB11) inhibitor detected. BSEP inhibition → impaired bile "
                    "acid export → hepatocellular bile acid accumulation → cholestatic DILI. "
                    "Confirm with BSEP vesicular transport assay (IC50 target > 10 µM). "
                    "Consider reducing cation amphiphilicity (logD, polar surface area). "
                    "Ref: Dawson 2012 Drug Metab Dispos 40:130–138; FDA 2012 DDI Guidance §5.5."
                ) if bsep_action != QCAction.PASS else "",
                regulatory_basis=RegulatoryBasis.RISK_STRATIFICATION,
            ))

        # ── Gate 2: mitochondrial toxicity ────────────────────────────────────
        mito_prob = metrics.get("mito_tox_probability")
        if mito_prob is not None:
            mito_prob = float(mito_prob)
            mito_halt = self.thresholds.get("mito_tox_probability_halt", 0.75)
            mito_warn = self.thresholds.get("mito_tox_probability_warn", 0.5)
            if mito_prob > mito_halt:
                mito_action, mito_level = QCAction.HALT, QCLevel.FAIL
            elif mito_prob > mito_warn:
                mito_action, mito_level = QCAction.ADVISORY, QCLevel.BRONZE
            else:
                mito_action, mito_level = QCAction.PASS, QCLevel.GOLD
            results.append(GateResult(
                gate="mito_toxicity",
                action=mito_action,
                level=mito_level,
                value=round(mito_prob, 3),
                threshold=mito_halt,
                message=(
                    f"Mitochondrial toxicity probability {mito_prob:.3f} "
                    f"(halt: > {mito_halt:.2f}; advisory: > {mito_warn:.2f})"
                ),
                suggestion=(
                    "Mitochondrial toxicity signal. Mechanism may include: ETC Complex I/III "
                    "inhibition, membrane potential uncoupling, or mtDNA depletion (nucleoside "
                    "analogues). 49% of hepatotoxic drugs are mitotoxic (Xu 2008 Toxicol Sci). "
                    "Confirm with mitochondrial membrane potential assay (TMRE, JC-1) or "
                    "Seahorse XF assay (OCR/ECAR). Consider structural modifications to reduce "
                    "lipophilicity or remove electrophilic warheads. "
                    "Ref: Xu 2008 Toxicol Sci 105:97–108."
                ) if mito_action != QCAction.PASS else "",
                regulatory_basis=RegulatoryBasis.RISK_STRATIFICATION,
            ))

        # ── Gate 3: reactive metabolites (ADVISORY only) ──────────────────────
        rm_flag = metrics.get("reactive_metabolite_flag")
        rm_alerts = metrics.get("reactive_metabolite_alerts", [])
        if rm_flag is not None or rm_alerts:
            is_flagged = bool(rm_flag) or bool(rm_alerts)
            alert_names = rm_alerts if isinstance(rm_alerts, list) else []
            alert_str = (", ".join(alert_names[:5]) + (" …" if len(alert_names) > 5 else "")
                         if alert_names else "see structural alert panel")
            results.append(GateResult(
                gate="reactive_metabolites",
                action=QCAction.ADVISORY if is_flagged else QCAction.PASS,
                level=QCLevel.BRONZE if is_flagged else QCLevel.GOLD,
                value=1.0 if is_flagged else 0.0,
                threshold=0.0,
                message=(
                    f"Reactive metabolite structural alert(s) detected: {alert_str}. "
                    f"May form covalent protein adducts → idiosyncratic DILI / immune sensitisation."
                    if is_flagged else
                    "No reactive metabolite structural alerts detected."
                ),
                suggestion=(
                    "Structural alert for reactive metabolite formation. "
                    "This is an ADVISORY — structural alerts alone do not mandate "
                    "compound termination (many marketed drugs carry alerts). "
                    "Confirm with covalent trapping assay: GSH, KCN, or semicarbazide adducts. "
                    "Consider bioisosteric replacement of the flagged motif. "
                    "Refs: Thompson 2006 Drug Metab Rev 38:567–598; "
                    "Kalgutkar & Soglia 2005 Expert Opin Drug Metab Toxicol 1:91–142."
                ) if is_flagged else "",
                regulatory_basis=RegulatoryBasis.RISK_STRATIFICATION,
            ))

        return results

    def _ames_gates(self, metrics: dict) -> list[GateResult]:
        """
        ICH M7 (2014, rev 2023) dual-model Ames mutagenicity assessment.

        ICH M7 §5.1 requires two complementary computational approaches:
          Model A (alert-based): Kazius 2005 structural alerts — expert rules.
            Key field: ames_positive (bool), ames_probability (float 0–1)
          Model B (statistical): Hansen 2009 Random Forest / Lhasa Nexus QSAR.
            Key field: ames_statistical_positive (bool), ames_statistical_probability (float 0–1)

        Concordance rules (ICH M7 Table 1):
          Both negative → PASS (low confidence required)
          Both positive → HALT (positive call; ICH S2R1 wet-lab test mandated)
          Discordant    → ADVISORY / "equivocal" (expert review; wet-lab recommended)

        When model B metrics are absent (workflow did not run a statistical model),
        fall back to model A alone (pre-ICH-M7 behaviour) and flag as ADVISORY
        so the user knows a second model should be added to the ADMET workflow.
        """
        results = []
        # Model A — alert-based (Kazius 2005 structural alerts)
        prob_a    = float(metrics.get("ames_probability", 0.0) or 0.0)
        pos_a     = bool(metrics.get("ames_positive", False))
        thresh_a  = self.thresholds["ames_probability_max"]
        ratio_a   = prob_a / thresh_a if thresh_a else 0.0

        # Model B — statistical QSAR (Hansen 2009 RF / Lhasa Nexus / equivalent)
        prob_b_raw = metrics.get("ames_statistical_probability")
        has_model_b = prob_b_raw is not None
        prob_b    = float(prob_b_raw or 0.0)
        pos_b     = bool(metrics.get("ames_statistical_positive", prob_b > 0.5))
        thresh_b  = self.thresholds.get("ames_statistical_probability_max", thresh_a)

        # Gate 1: alert-based model result
        action_a = QCAction.HALT if pos_a or prob_a > thresh_a else (
            QCAction.ADVISORY if ratio_a > 0.85 else QCAction.PASS
        )
        results.append(GateResult(
            gate="ames_mutagenicity",
            action=action_a,
            level=_level_for_ratio(ratio_a) if not pos_a else QCLevel.FAIL,
            value=prob_a,
            threshold=thresh_a,
            message=(
                f"Alert-based (Kazius 2005): {'positive' if pos_a else 'negative'}, "
                f"probability {prob_a:.3f} (max {thresh_a:.2f})"
            ),
            suggestion=(
                "ICH S2(R1) requires a wet-lab Ames test before IND filing. "
                "Alert-based model predicts positive. Enable ames_strict=True to remove "
                "alerted scaffolds (pre-screening optimization — does not substitute for "
                "the required ICH S2(R1) genotoxicity package). "
                "ICH M7: also run a statistical QSAR model for dual-model concordance."
            ) if action_a == QCAction.HALT else "",
            regulatory_basis=RegulatoryBasis.REGULATORY,
        ))

        # Gate 2: statistical QSAR model result (only if output is available)
        if has_model_b:
            ratio_b = prob_b / thresh_b if thresh_b else 0.0
            action_b = QCAction.HALT if pos_b or prob_b > thresh_b else (
                QCAction.ADVISORY if ratio_b > 0.85 else QCAction.PASS
            )
            results.append(GateResult(
                gate="ames_statistical_qsar",
                action=action_b,
                level=_level_for_ratio(ratio_b) if not pos_b else QCLevel.FAIL,
                value=prob_b,
                threshold=thresh_b,
                message=(
                    f"Statistical QSAR (ICH M7 Model B): "
                    f"{'positive' if pos_b else 'negative'}, "
                    f"probability {prob_b:.3f} (max {thresh_b:.2f})"
                ),
                suggestion=(
                    "Statistical QSAR (ICH M7 §5.1 Model B) predicts Ames positive. "
                    "Concordant with alert-based model — high-confidence call. "
                    "Wet-lab Ames test required (ICH S2R1) before IND filing."
                ) if action_b == QCAction.HALT else "",
                regulatory_basis=RegulatoryBasis.REGULATORY,
            ))

            # Gate 3: concordance assessment (ICH M7 §5.1)
            concordant = (pos_a == pos_b)
            if not concordant:
                results.append(GateResult(
                    gate="ames_model_concordance",
                    action=QCAction.ADVISORY,
                    level=QCLevel.SILVER,
                    value=0.0,
                    threshold=1.0,
                    message=(
                        f"ICH M7 discordant: alert-based={'positive' if pos_a else 'negative'}, "
                        f"statistical={'positive' if pos_b else 'negative'}. "
                        f"Equivocal result — expert review recommended."
                    ),
                    suggestion=(
                        "ICH M7 §5.1: discordant models produce an 'equivocal' result. "
                        "Expert review is required. Recommended actions: (1) run a third "
                        "computational model or Ames expert system (Derek Nexus / DEREK); "
                        "(2) perform wet-lab Ames test. "
                        "Discordance often indicates borderline structural features — "
                        "consider structural modification to resolve the alert."
                    ),
                    regulatory_basis=RegulatoryBasis.REGULATORY,
                ))
        else:
            # Model B absent — flag as advisory so user knows to add it
            results.append(GateResult(
                gate="ames_statistical_qsar",
                action=QCAction.ADVISORY,
                level=QCLevel.BRONZE,
                value=0.0,
                threshold=thresh_b,
                message="Statistical QSAR model B not run — ICH M7 requires dual-model assessment.",
                suggestion=(
                    "ICH M7 §5.1 requires two complementary models. Only the alert-based "
                    "model (Kazius 2005) ran. Add a statistical QSAR model "
                    "(e.g. Hansen 2009 Random Forest, Lhasa Nexus, or equivalent) "
                    "to the ADMET workflow to complete the ICH M7 dual-model assessment. "
                    "The ames_statistical_probability field should be emitted in "
                    "toxicity_report.json by the ADMET_pred Nextflow process."
                ),
                regulatory_basis=RegulatoryBasis.REGULATORY,
            ))

        return results

    def _physicochemical_gates(self, metrics: dict) -> list[GateResult]:
        """Lipinski Rule of Five gates (advisory only — no auto-tune defined)."""
        results = []

        logp = metrics.get("logP", 0.0)
        logp_max = self.thresholds["logp_max"]
        logp_ratio = logp / logp_max if logp_max else 0.0
        results.append(GateResult(
            gate="logp",
            action=QCAction.ADVISORY if logp > logp_max else QCAction.PASS,
            level=_level_for_ratio(logp_ratio),
            value=logp,
            threshold=logp_max,
            message=f"logP {logp:.2f} (Lipinski limit {logp_max:.1f})",
            suggestion="Reduce logP filter to improve aqueous solubility and reduce DILI risk." if logp > logp_max else "",
            regulatory_basis=RegulatoryBasis.RISK_STRATIFICATION,
        ))

        mw = metrics.get("mw", 0.0)
        mw_max = self.thresholds["mw_max_da"]
        mw_ratio = mw / mw_max if mw_max else 0.0
        results.append(GateResult(
            gate="molecular_weight",
            action=QCAction.ADVISORY if mw > mw_max else QCAction.PASS,
            level=_level_for_ratio(mw_ratio),
            value=mw,
            threshold=mw_max,
            message=f"MW {mw:.1f} Da (Lipinski limit {mw_max:.0f} Da)",
            regulatory_basis=RegulatoryBasis.RISK_STRATIFICATION,
        ))

        return results
