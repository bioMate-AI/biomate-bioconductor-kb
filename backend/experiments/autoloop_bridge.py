"""
Auto-loop bridge: connects qc_trace_monitor.py metric parsers → auto-loop evaluators.

Called from NextflowQCGateHandler.handle_process_completion() after raw metrics
are parsed from workflow output files.  Produces rich autoloop_* SSE events with
gate results, remediation suggestions, and literature citations.

Architecture
------------
Reactive/advisory mode — no workflow restart happens here.  The evaluators run
against the single set of metrics produced by the completed Nextflow process and
emit structured feedback.  If the phase failed, the suggested parameters are stored
in memory (keyed by invocation_id) so the /autoloop-suggestions API can return them
for the user to start a new run with improved settings.
"""
from __future__ import annotations

import logging
import sys
import os
import threading
from typing import Any, Callable, Optional

log = logging.getLogger(__name__)

# ── Domain → process keywords ─────────────────────────────────────────────────

_DOMAIN_KEYWORDS: dict[str, set[str]] = {
    "admet": {
        "ADMET_TOXICITY", "HERG_SCREEN", "DILI_SCREEN", "TOXICITY_SCREEN",
        "ADMET_PRED", "PREDICT_ADMET", "ADMET_SAFETY",
    },
    "docking": {
        "MOLECULAR_DOCKING", "DOCKING", "AUTODOCK", "VINA", "GLIDE",
        "DIFFDOCK", "GNINA",
    },
    "cyp_ddi": {
        "CYP_INHIBITION", "DDI_RISK_ASSESSMENT", "CYP_PANEL", "DDI_RISK",
        "DDI_ASSESSMENT", "CYP_DDI", "DDI_REPORT",
    },
    "nca_pk": {
        "NCA_PKNCA", "NCA_ANALYSIS", "NONCOMPARTMENTAL", "PKNCA",
        "NCA_PK",
    },
    "pbpk": {
        "PBPK_SIMULATION", "PBPK_PEDIATRIC", "PK_SIM_PBPK", "SIMCYP_PBPK",
        "PBPK", "PHYSIOLOGICALLY_BASED_PK",
    },
}


def classify_domain(process_name: str) -> Optional[str]:
    upper = process_name.upper()
    for domain, kws in _DOMAIN_KEYWORDS.items():
        if any(k in upper for k in kws):
            return domain
    return None


# ── Schema adapters ────────────────────────────────────────────────────────────

def _adapt_admet(raw: dict) -> dict:
    """
    Map qc_trace_monitor ADMET parser output → ADMETQCEvaluator input.

    The evaluator's _dili_gates() reads 'dili_risk' directly (not 'dili_risk_level'),
    so no rename is needed for the risk-level gate.  We add 'dili_risk_level' as an
    alias anyway so that the key matches the GateResult.gate name used externally,
    but the evaluator itself reads the original 'dili_risk' key.

    Add safe defaults for Ro5 fields (logp, molecular_weight_da) the evaluator reads
    optionally — absent in the ADMET parser output.
    """
    out = dict(raw)
    # Alias: the gate is named "dili_risk_level" in GateResult, but the evaluator
    # reads metrics.get("dili_risk") — both keys are present after this adapter runs.
    if "dili_risk" in out and "dili_risk_level" not in out:
        out["dili_risk_level"] = out["dili_risk"]
    out.setdefault("logp", 3.0)
    out.setdefault("molecular_weight_da", 400.0)
    return out


def _adapt_docking(raw: dict) -> dict:
    """
    Map qc_trace_monitor docking parser output → DockingQCEvaluator input.

    Adds success=True if n_poses_generated > 0 (parser omits the key).
    Aliases n_poses_generated as n_ligands_docked for the evaluator fallback path.
    """
    out = dict(raw)
    if "success" not in out:
        out["success"] = int(out.get("n_poses_generated", 0)) > 0
    if "n_ligands_docked" not in out and "n_poses_generated" in out:
        out["n_ligands_docked"] = out["n_poses_generated"]
    return out


def _adapt_cyp_ddi(raw: dict) -> dict:
    """
    Map _parse_cyp_ddi_results() output → CYPDDIQCEvaluator input.

    The new parser already returns {"summary": {...}} so this is a pass-through
    with a safety check.
    """
    if "summary" in raw:
        return raw
    # Fallback: wrap flat dict into expected structure.
    # n_clinical_study_recommended takes priority; fall back to n_clinical if absent.
    return {
        "summary": {
            "n_clinical": raw.get("n_clinical_study_recommended",
                                  raw.get("n_clinical", 0)),
            "n_investigate": raw.get("n_investigate", 0),
            "n_tdi": raw.get("n_tdi_flagged", raw.get("n_tdi", 0)),
            "overall_recommendation": raw.get("overall_recommendation", "NOT_EXPECTED"),
        }
    }


def _adapt_nca_pk(raw: dict) -> dict:
    """
    Map qc_trace_monitor NCA parser output (flat) → NCAPKQCEvaluator input.

    Field renames:
      auc_extrap_pct_max          → population_summary.auc_extrap_pct
      thalf_mean_h / t_half_mean  → population_summary.t_half_mean
      auclast_mean                → population_summary.auc_last_mean
      (synthesise auc_inf_mean from auc_last + extrapolated fraction)
    """
    extrap_pct = float(raw.get("auc_extrap_pct_max", 0.0) or 0.0)
    auc_last   = float(raw.get("auclast_mean", 0.0) or 0.0)
    # AUC_inf = AUC_last / (1 - extrap_fraction); guard against extrap=100%
    if 0 < extrap_pct < 100:
        auc_inf = auc_last / (1.0 - extrap_pct / 100.0)
    else:
        auc_inf = auc_last

    # Use float-converted local variables (not raw values) to guard against
    # None values coming from JSON null fields (e.g., {"auc_extrap_pct_max": null}).
    t_half    = float(raw.get("thalf_mean_h", raw.get("t_half_mean", 0.0)) or 0.0)
    no_slope  = int(raw.get("subjects_with_no_terminal_slope", 0) or 0)
    cmax      = float(raw.get("cmax_mean", 0.0) or 0.0)

    return {
        "population_summary": {
            "auc_extrap_pct":                 extrap_pct,
            "subjects_with_no_terminal_slope": no_slope,
            "t_half_mean":                    t_half,
            "auc_last_mean":                  auc_last,
            "auc_inf_mean":                   auc_inf,
            "cmax_mean":                      cmax,
        }
    }


def _adapt_pbpk(raw: dict) -> dict:
    """
    Map qc_trace_monitor PBPK parser output (or pbpk_qc.json from the
    pbpk_simulation Nextflow process) → PBPKQCEvaluator input.

    Accepts both flat (qc_trace_monitor) and nested (pbpk_qc.json) keys
    because the PBPK gate JSON schema is still being defined (see
    docs/20260521_DEPLOYMENT_MISTAKES_LESSONS.md). Missing values default
    to None so the evaluator skips that gate gracefully.
    """
    return {
        "tmax_h":                float(raw.get("tmax_h", 0.0) or 0.0),
        "simulation_duration_h": float(raw.get("simulation_duration_h",
                                                raw.get("sim_duration_h", 0.0)) or 0.0),
        "cl_l_per_h":            float(raw.get("cl_l_per_h",
                                                raw.get("clearance_L_h", 0.0)) or 0.0),
        "thalf_estimable":       bool(raw.get("thalf_estimable", True)),
        "mass_balance_recovery": raw.get("mass_balance_recovery", None),
        "auc_pred_h_ug_per_mL":  raw.get("auc_pred_h_ug_per_mL", None),
        "auc_obs_h_ug_per_mL":   raw.get("auc_obs_h_ug_per_mL", None),
    }


_ADAPTERS: dict[str, Callable[[dict], dict]] = {
    "admet":   _adapt_admet,
    "docking": _adapt_docking,
    "cyp_ddi": _adapt_cyp_ddi,
    "nca_pk":  _adapt_nca_pk,
    "pbpk":    _adapt_pbpk,
}

# ── Phase routing ─────────────────────────────────────────────────────────────
# ADMET has three evaluator phases; other domains have one each.
# Map the specific Nextflow process name to the right evaluator phase so that
# HERG_SCREEN → phase_3_herg_screen (hERG-only gates) and
# DILI_SCREEN  → phase_4_dili_ames  (DILI+Ames gates),
# rather than routing everything through the full phase_2_admet_prediction.

_ADMET_PHASE3_KEYWORDS = {"HERG_SCREEN"}
_ADMET_PHASE4_KEYWORDS = {"DILI_SCREEN", "DILI_AMES", "AMES_SCREEN"}

_DOMAIN_DEFAULT_PHASE: dict[str, str] = {
    "admet":   "phase_2_admet_prediction",
    "docking": "phase_1_docking",
    "cyp_ddi": "phase_2_ddi_risk",
    "nca_pk":  "phase_1_nca_analysis",
    "pbpk":    "phase_1_pbpk_simulation",
}


def _resolve_phase(domain: str, process_name: str) -> str:
    """Return the evaluator phase string for a (domain, process_name) pair."""
    if domain == "admet":
        upper = process_name.upper()
        if any(k in upper for k in _ADMET_PHASE3_KEYWORDS):
            return "phase_3_herg_screen"
        if any(k in upper for k in _ADMET_PHASE4_KEYWORDS):
            return "phase_4_dili_ames"
        return "phase_2_admet_prediction"
    if domain not in _DOMAIN_DEFAULT_PHASE:
        raise ValueError(f"Unknown domain: {domain!r}")
    return _DOMAIN_DEFAULT_PHASE[domain]

_DOMAIN_DEFAULT_PROFILE: dict[str, str] = {
    "admet":   "admet_standard",
    "docking": "docking_hit_finding",
    "cyp_ddi": "cyp_ddi_standard",
    "nca_pk":  "nca_standard",
    "pbpk":    "pbpk_screening",   # advisory-only default; users opt-in to
                                    # pbpk_ind_submission for halt-grade gates
}

# ── In-memory suggestion store ─────────────────────────────────────────────────
# Stores the last remediation suggestions per invocation_id so the REST API
# can serve them without re-running evaluation.  Protected by a lock because
# qc_trace_monitor.py calls evaluate_and_emit from background polling threads.

_suggestions: dict[str, dict] = {}
_suggestions_lock = threading.Lock()


def get_suggestions(invocation_id: str) -> Optional[dict]:
    """Return the last stored auto-loop suggestions for an invocation, or None."""
    with _suggestions_lock:
        return _suggestions.get(invocation_id)


def pop_suggestions(invocation_id: str) -> Optional[dict]:
    """Return and remove suggestions for an invocation."""
    with _suggestions_lock:
        return _suggestions.pop(invocation_id, None)


# ── Public entry point ─────────────────────────────────────────────────────────

def evaluate_and_emit(
    process_name: str,
    raw_metrics: dict,
    invocation_id: str,
    sse_callback: Callable[[str, dict], None],
    qc_profile: Optional[str] = None,
) -> bool:
    """
    Evaluate *raw_metrics* using the appropriate auto-loop evaluator and emit
    structured SSE events.

    Parameters
    ----------
    process_name  : Nextflow process name (e.g., "ADMET_TOXICITY")
    raw_metrics   : Dict returned by the qc_trace_monitor parser
    invocation_id : Workflow invocation UUID (for suggestion store keying)
    sse_callback  : Callable(event_type, data) — posts to /internal/sse-inject
    qc_profile    : Optional named QC profile override

    Returns
    -------
    True if the phase passed, False if a gate HALTed.
    """
    domain = classify_domain(process_name)
    if domain is None:
        return True  # not an auto-loop domain — pass through

    try:
        return _do_evaluate(domain, process_name, raw_metrics, invocation_id, sse_callback, qc_profile)
    except Exception as exc:
        log.warning(f"[AutoLoop] Evaluation error for {process_name}: {exc}", exc_info=True)
        return True  # fail-open: never block existing QC pipeline on auto-loop error


# ── Core evaluation ────────────────────────────────────────────────────────────

def _do_evaluate(
    domain: str,
    process_name: str,
    raw_metrics: dict,
    invocation_id: str,
    sse_callback: Callable[[str, dict], None],
    qc_profile: Optional[str],
) -> bool:
    phase   = _resolve_phase(domain, process_name)
    profile = qc_profile or _DOMAIN_DEFAULT_PROFILE[domain]
    metrics = _ADAPTERS[domain](raw_metrics)

    evaluator_cls, tuner_cls, params_cls = _load_components(domain)
    qc_result = evaluator_cls(profile).evaluate_phase(phase, metrics)

    # ── Emit gate results (always) ──────────────────────────────────────────
    sse_callback("autoloop_gate_results", {
        "phase":         phase,
        "domain":        domain,
        "overall_level": qc_result.overall_level.value,
        "passed":        qc_result.passed,
        "gates": [
            {
                "gate":      g.gate,
                "action":    g.action.value,
                "level":     g.level.value,
                "value":     g.value,
                "threshold": g.threshold,
                "message":   g.message,
            }
            for g in qc_result.gate_results
        ],
    })

    if qc_result.passed:
        sse_callback("autoloop_phase_complete", {
            "phase":   phase,
            "domain":  domain,
            "outcome": "pass",
            "level":   qc_result.overall_level.value,
        })
        return True

    # ── Phase failed — compute enriched remediations ────────────────────────
    params = params_cls()
    _, enriched_remeds = tuner_cls().remediate(qc_result, params)
    remeds_json = [r.to_dict() for r in enriched_remeds]

    failed_gates = [g.gate for g in qc_result.halts]
    sse_callback("autoloop_update", {
        "phase":        phase,
        "domain":       domain,
        "attempt":      1,
        "next_attempt": 2,
        "failed_gates": failed_gates,
        "remediations": remeds_json,
    })

    # ── Persist suggestions for REST API ───────────────────────────────────
    with _suggestions_lock:
        _suggestions[invocation_id] = {
            "domain":        domain,
            "phase":         phase,
            "profile":       profile,
            "remediations":  remeds_json,
            "failed_gates":  failed_gates,
        }

    return False


# ── Lazy component loader (avoids heavy imports at module load time) ───────────

def _load_components(domain: str) -> tuple:
    """Return (EvaluatorClass, TunerClass, ParamsClass) for the given domain."""
    # Ensure experiments directory is on sys.path
    _ensure_experiments_path()

    if domain == "admet":
        from experiments.admet_autoloop.qc_evaluator import ADMETQCEvaluator
        from experiments.admet_autoloop.enriched_tuner import KnowledgeEnrichedADMETTuner
        from experiments.admet_autoloop.params import ADMETParams
        return ADMETQCEvaluator, KnowledgeEnrichedADMETTuner, ADMETParams

    if domain == "docking":
        from experiments.docking_autoloop.qc_evaluator import DockingQCEvaluator
        from experiments.docking_autoloop.enriched_tuner import KnowledgeEnrichedDockingTuner
        from experiments.docking_autoloop.params import DockingParams
        return DockingQCEvaluator, KnowledgeEnrichedDockingTuner, DockingParams

    if domain == "cyp_ddi":
        from experiments.cyp_ddi_autoloop.qc_evaluator import CYPDDIQCEvaluator
        from experiments.cyp_ddi_autoloop.enriched_tuner import KnowledgeEnrichedCYPTuner
        from experiments.cyp_ddi_autoloop.params import CYPDDIParams
        return CYPDDIQCEvaluator, KnowledgeEnrichedCYPTuner, CYPDDIParams

    if domain == "nca_pk":
        from experiments.nca_pk_autoloop.qc_evaluator import NCAPKQCEvaluator
        from experiments.nca_pk_autoloop.enriched_tuner import KnowledgeEnrichedNCAPKTuner
        from experiments.nca_pk_autoloop.params import NCAPKParams
        return NCAPKQCEvaluator, KnowledgeEnrichedNCAPKTuner, NCAPKParams

    if domain == "pbpk":
        from experiments.pbpk_autoloop.qc_evaluator import PBPKQCEvaluator
        from experiments.pbpk_autoloop.enriched_tuner import KnowledgeEnrichedPBPKTuner
        from experiments.pbpk_autoloop.params import PBPKParams
        return PBPKQCEvaluator, KnowledgeEnrichedPBPKTuner, PBPKParams

    raise ValueError(f"Unknown domain: {domain!r}")


def _ensure_experiments_path() -> None:
    """Add backend/experiments parent to sys.path if not already present."""
    backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if backend_dir not in sys.path:
        sys.path.insert(0, backend_dir)
