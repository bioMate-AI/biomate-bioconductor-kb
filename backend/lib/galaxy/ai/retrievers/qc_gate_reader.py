"""
QC gate JSON reader — surfaces gate results from workflow output files
as SSE-shaped event dicts that any caller can emit.

Standalone helper (does NOT modify autoloop_bridge.py or nextflow_executor.py
— both are subject to parallel-session edit collisions). Caller wiring
example (one-liner from a workflow completion hook):

    from galaxy.ai.retrievers.qc_gate_reader import (
        read_gate_json,
        build_gate_event,
    )
    metrics = read_gate_json(output_dir / "ich_s5_qc.json")
    if metrics is not None:
        evt = build_gate_event(
            workflow_name="ich_s5_reproductive_tox",
            domain="ich_s5",
            metrics=metrics,
        )
        sse_callback("autoloop_gate_results", evt)

This gives ~10 QC-but-no-autoloop workflows (BOIN, ICH-S5/S7A, HTS,
allometric, openfe, ivive, p0_pkpd, pocket_detection, aizynthfinder, plus
forward-looking structure_prediction) the same UI treatment as the 5
wired auto-loop domains.

Critical: the emitted event uses the IDENTICAL shape as
autoloop_gate_results so the existing frontend panel renders it without
any frontend code change. Each gate carries an `evidence` field populated
from qc_evidence.yaml — the existing tooltip wrapper picks it up
automatically.
"""

from __future__ import annotations

import json
import logging
import math
from pathlib import Path
from typing import Any, Optional

from galaxy.ai.retrievers.qc_evidence import get_evidence_for_gate, resolve_thresholds

log = logging.getLogger(__name__)


# Per-domain gate definitions. Each gate function maps raw metrics →
# (value, threshold, passed_bool, level_str) or returns None to skip.
# Thresholds + comparisons here MUST agree with the rule_text in
# backend/config/qc_evidence.yaml — that's the user-facing claim.


def _gate_hts_z_prime(m: dict) -> Optional[tuple]:
    """Z' ≥ 0.5 (Zhang 1999). Lower = fail."""
    v = m.get("z_prime")
    if v is None:
        return None
    v = float(v)
    threshold = 0.5
    passed = v >= threshold
    level = "GOLD" if v >= 0.5 else ("SILVER" if v >= 0.4 else "FAIL")
    msg = f"Z'={v:.3f}" + ("" if passed else f" < {threshold} (Zhang 1999)")
    return ("hts_z_prime", v, threshold, passed, level, msg)


def _gate_hts_signal_window(m: dict) -> Optional[tuple]:
    """SW ≥ 2 (Iversen 2006)."""
    v = m.get("signal_window")
    if v is None:
        return None
    v = float(v)
    threshold = 2.0
    passed = v >= threshold
    level = "GOLD" if passed else "BRONZE"
    msg = f"SW={v:.2f}" + ("" if passed else f" < {threshold} (Iversen 2006)")
    return ("hts_signal_window", v, threshold, passed, level, msg)


def _gate_ich_s5_safety_margin(m: dict) -> Optional[tuple]:
    """≥10× Cmax safety margin (ICH S5R3 WOCBP)."""
    v = m.get("safety_margin_x")
    if v is None:
        return None
    v = float(v)
    threshold = 10.0
    passed = v >= threshold
    level = "GOLD" if v >= 30 else ("SILVER" if v >= 10 else "FAIL")
    msg = f"margin={v:.1f}× Cmax" + ("" if passed else f" < {threshold}×")
    return ("ich_s5_safety_margin", v, threshold, passed, level, msg)


def _gate_ich_s7b_herg_margin(m: dict, context: Optional[dict] = None) -> Optional[tuple]:
    """hERG safety margin ≥10× (ICH S7B).

    Optional context for indication-class modifier (added 2026-06-15 Track 1).
    Example: context={"indication_class": "chronic_cns"} → 50/30 cutoffs.
    Falls back to the historical 30/10 defaults when context is absent.
    """
    v = m.get("herg_safety_margin_x")
    if v is None:
        return None
    v = float(v)
    advisory_min, fail_min = resolve_thresholds(
        "ich_s7", "ich_s7b_herg_margin", context,
        default_advisory=30.0, default_fail=10.0,
    )
    passed = v >= fail_min
    level = "GOLD" if v >= advisory_min else ("SILVER" if v >= fail_min else "FAIL")
    msg = f"hERG margin={v:.1f}×" + ("" if passed else f" < {fail_min}× (ICH S7B)")
    return ("ich_s7b_herg_margin", v, fail_min, passed, level, msg)


def _gate_boin_dlt_boundary(m: dict) -> Optional[tuple]:
    """MTD DLT rate ≤ φ (Liu & Yuan 2015). Reports observed/target ratio."""
    obs = m.get("mtd_observed_dlt_rate")
    target = m.get("target_dlt_rate", 0.25)
    if obs is None:
        return None
    obs, target = float(obs), float(target)
    if target <= 0:
        return None
    ratio = obs / target
    passed = ratio <= 1.0
    level = "GOLD" if ratio <= 0.9 else ("SILVER" if ratio <= 1.0 else "FAIL")
    msg = f"DLT={obs:.3f} vs target φ={target}" + ("" if passed else " — MTD exceeds target")
    return ("boin_dlt_boundary", ratio, 1.0, passed, level, msg)


def _gate_allometric_r_squared(m: dict) -> Optional[tuple]:
    """R² ≥ 0.85 for allometric fit (FDA 2005 FIH)."""
    v = m.get("r_squared")
    if v is None:
        return None
    v = float(v)
    threshold = 0.85
    passed = v >= threshold
    level = "GOLD" if v >= 0.95 else ("SILVER" if v >= 0.85 else "FAIL")
    msg = f"R²={v:.3f}" + ("" if passed else f" < {threshold} (FDA FIH 2005)")
    return ("allometric_r_squared", v, threshold, passed, level, msg)


def _gate_ivive_fold_error(m: dict) -> Optional[tuple]:
    """|pred/obs| ≤ 2 (Obach 1999)."""
    pred, obs = m.get("cl_predicted_l_per_h"), m.get("cl_observed_l_per_h")
    if pred is None or obs is None or float(obs) == 0:
        return None
    pred, obs = float(pred), float(obs)
    fold = 2 ** abs(math.log2(pred / obs)) if pred > 0 else math.inf
    threshold = 2.0
    passed = fold <= threshold
    level = "GOLD" if fold <= 1.5 else ("SILVER" if fold <= 2.0 else "FAIL")
    msg = f"fold-error={fold:.2f}×" + ("" if passed else f" > {threshold}× (Obach 1999)")
    return ("ivive_fold_error", fold, threshold, passed, level, msg)


def _gate_openfe_cycle_closure(m: dict) -> Optional[tuple]:
    """|ΔG_sum| ≤ 1 kcal/mol around closed cycles (Mey 2020)."""
    v = m.get("cycle_closure_kcal_per_mol")
    if v is None:
        return None
    v = float(abs(v))
    threshold = 1.0
    passed = v <= threshold
    level = "GOLD" if v <= 0.5 else ("SILVER" if v <= 1.0 else "FAIL")
    msg = f"cycle_closure={v:.2f} kcal/mol" + ("" if passed else f" > {threshold} (Mey 2020)")
    return ("openfe_cycle_closure", v, threshold, passed, level, msg)


def _gate_p0_pkpd_weight_loss(m: dict) -> Optional[tuple]:
    """Week-30 weight change in [-6, +3] kg band (Overgaard 2019)."""
    v = m.get("week30_weight_change_kg")
    if v is None:
        return None
    v = float(v)
    in_band = -6.0 <= v <= 3.0
    level = "GOLD" if in_band else "FAIL"
    msg = f"Δweight={v:+.2f} kg at wk30" + ("" if in_band else " — outside [-6, +3] kg band")
    return ("p0_pkpd_weight_loss_band", v, 0.0, in_band, level, msg)


def _gate_pocket_druggability(m: dict) -> Optional[tuple]:
    """Druggability score ≥ 0.5 (Le Guilloux 2009 fpocket)."""
    v = m.get("druggability_score")
    if v is None:
        return None
    v = float(v)
    threshold = 0.5
    passed = v >= threshold
    level = "GOLD" if v >= 0.7 else ("SILVER" if v >= 0.5 else "FAIL")
    msg = f"druggability={v:.2f}" + ("" if passed else f" < {threshold} (fpocket)")
    return ("pocket_druggability_score", v, threshold, passed, level, msg)


def _gate_aizynth_solved_routes(m: dict) -> Optional[tuple]:
    """≥1 solved route (Genheden 2020)."""
    v = m.get("num_solved_routes")
    if v is None:
        return None
    v = int(v)
    threshold = 1
    passed = v >= threshold
    level = "GOLD" if v >= 3 else ("SILVER" if v >= 1 else "FAIL")
    msg = f"{v} solved routes" + ("" if passed else " — no synthetic route found")
    return ("aizynth_solved_routes", float(v), float(threshold), passed, level, msg)


def _gate_struct_pred_mean_plddt(m: dict) -> Optional[tuple]:
    """Mean pLDDT ≥ 70 for downstream docking use (Jumper 2021 GOLD)."""
    v = m.get("mean_plddt")
    if v is None:
        v = m.get("plddt_mean")
    if v is None:
        return None
    v = float(v)
    threshold = 70.0
    passed = v >= threshold
    if v >= 70.0:
        level = "GOLD"
    elif v >= 50.0:
        level = "BRONZE"
    else:
        level = "FAIL"
    msg = f"mean pLDDT={v:.1f}" + ("" if passed else f" < {threshold} (Jumper 2021)")
    return ("struct_pred_mean_plddt", v, threshold, passed, level, msg)


def _gate_struct_pred_confident_fraction(m: dict) -> Optional[tuple]:
    """Fraction of residues with pLDDT > 70 should be ≥ 0.70
    (Tunyasuvunakool 2021 SILVER)."""
    v = m.get("confident_fraction")
    if v is None:
        v = m.get("frac_plddt_gt_70")
    if v is None:
        return None
    v = float(v)
    threshold = 0.70
    passed = v >= threshold
    if v >= 0.70:
        level = "SILVER"
    elif v >= 0.50:
        level = "BRONZE"
    else:
        level = "FAIL"
    msg = f"confident fraction={v:.2f}" + (
        "" if passed else f" < {threshold} (Tunyasuvunakool 2021)"
    )
    return ("struct_pred_confident_fraction", v, threshold, passed, level, msg)


def _gate_struct_pred_max_pae(m: dict) -> Optional[tuple]:
    """Max inter-domain PAE ≤ 8 Å (Tunyasuvunakool 2021 SILVER).

    Skipped if max_pae not present — single-domain proteins don't
    have meaningful inter-domain PAE.
    """
    v = m.get("max_pae")
    if v is None:
        v = m.get("pae_max")
    if v is None:
        return None
    v = float(v)
    threshold = 8.0
    passed = v <= threshold
    if v <= 8.0:
        level = "SILVER"
    elif v <= 15.0:
        level = "BRONZE"
    else:
        level = "FAIL"
    msg = f"max PAE={v:.1f} Å" + (
        "" if passed else f" > {threshold} Å (Tunyasuvunakool 2021)"
    )
    return ("struct_pred_max_pae", v, threshold, passed, level, msg)


# ─── Cancer biology / somatic variant calling ─────────────────────────

def _gate_cancer_somatic_vaf_min(m: dict) -> Optional[tuple]:
    """VAF ≥ 0.05 (GATK / Mutect2 default)."""
    v = m.get("vaf")
    if v is None:
        v = m.get("variant_allele_frequency")
    if v is None:
        return None
    v = float(v)
    threshold = 0.05
    passed = v >= threshold
    level = "GOLD" if passed else "FAIL"
    msg = f"VAF={v:.3f}" + ("" if passed else f" < {threshold} (GATK Mutect2)")
    return ("cancer_somatic_vaf_min", v, threshold, passed, level, msg)


def _gate_cancer_somatic_depth_min(m: dict) -> Optional[tuple]:
    """Depth ≥ 30× (Strelka2 / GATK Best Practices)."""
    v = m.get("depth")
    if v is None:
        v = m.get("mean_depth")
    if v is None:
        return None
    v = float(v)
    threshold = 30.0
    passed = v >= threshold
    level = "GOLD" if passed else "FAIL"
    msg = f"depth={v:.1f}×" + ("" if passed else f" < {threshold}× (Strelka2)")
    return ("cancer_somatic_depth_min", v, threshold, passed, level, msg)


def _gate_cancer_somatic_mapping_quality(m: dict) -> Optional[tuple]:
    """Mean MAPQ ≥ 20 (Phred-20 = 99% mapping accuracy; BWA-MEM convention)."""
    v = m.get("mapq_mean")
    if v is None:
        v = m.get("mean_mapq")
    if v is None:
        return None
    v = float(v)
    threshold = 20.0
    passed = v >= threshold
    if v >= 20.0:
        level = "SILVER"
    elif v >= 10.0:
        level = "BRONZE"
    else:
        level = "FAIL"
    msg = f"mean MAPQ={v:.1f}" + ("" if passed else f" < {threshold} (BWA-MEM)")
    return ("cancer_somatic_mapping_quality", v, threshold, passed, level, msg)


# ─── Cryo-EM single-particle reconstruction ───────────────────────────

def _gate_cryo_em_fsc_resolution(m: dict) -> Optional[tuple]:
    """FSC=0.143 resolution; ≤4 Å pass, 4-8 Å advisory, >8 Å fail
    (Rosenthal & Henderson 2003 GOLD criterion; 4 Å operational cutoff)."""
    v = m.get("fsc_resolution_angstroms")
    if v is None:
        v = m.get("resolution_A")
    if v is None:
        return None
    v = float(v)
    threshold = 4.0
    passed = v <= threshold
    if v <= 4.0:
        level = "GOLD"
    elif v <= 8.0:
        level = "SILVER"
    else:
        level = "FAIL"
    msg = f"FSC0.143 res={v:.2f} Å" + ("" if passed else f" > {threshold} Å (Rosenthal & Henderson 2003)")
    return ("cryo_em_fsc_resolution", v, threshold, passed, level, msg)


def _gate_cryo_em_motion_drift(m: dict) -> Optional[tuple]:
    """Total drift ≤ 50 Å per movie (cryoSPARC operational)."""
    v = m.get("total_drift_angstroms")
    if v is None:
        v = m.get("drift_A")
    if v is None:
        return None
    v = float(v)
    threshold = 50.0
    passed = v <= threshold
    if v <= 50.0:
        level = "SILVER"
    elif v <= 100.0:
        level = "BRONZE"
    else:
        level = "FAIL"
    msg = f"drift={v:.1f} Å" + ("" if passed else f" > {threshold} Å (cryoSPARC)")
    return ("cryo_em_motion_drift", v, threshold, passed, level, msg)


def _gate_cryo_em_particle_count(m: dict) -> Optional[tuple]:
    """≥ 50,000 particles for sub-3 Å (Henderson 1995 theory)."""
    v = m.get("n_particles")
    if v is None:
        v = m.get("particle_count")
    if v is None:
        return None
    v = float(v)
    threshold = 50000.0
    passed = v >= threshold
    if v >= 50000.0:
        level = "SILVER"
    elif v >= 10000.0:
        level = "BRONZE"
    else:
        level = "FAIL"
    msg = f"n_particles={int(v)}" + ("" if passed else f" < {int(threshold)} (Henderson 1995)")
    return ("cryo_em_particle_count", v, threshold, passed, level, msg)


# ─── Cryo-ET gates ────────────────────────────────────────────────────

def _gate_cryo_et_sta_fsc_resolution(m: dict) -> Optional[tuple]:
    """STA FSC 0.143 resolution from subtomogram averaging.
    Lower = better. Threshold derived from cryo-ET community target."""
    v = m.get("fsc_0143_resolution_angstroms", m.get("fsc_resolution_angstroms"))
    if v is None:
        return None
    v = float(v)
    threshold = 15.0  # advisory above; FAIL above 30
    passed = v <= threshold
    if v <= 8:
        level = "GOLD"
    elif v <= 15:
        level = "SILVER"
    elif v <= 30:
        level = "BRONZE"
    else:
        level = "FAIL"
    msg = f"STA FSC@0.143={v:.1f} Å" + ("" if passed else f" > {threshold} Å (Rosenthal & Henderson 2003)")
    return ("cryo_et_sta_fsc_resolution", v, threshold, passed, level, msg)


def _gate_cryo_et_tilt_residual(m: dict) -> Optional[tuple]:
    """Mean tilt-alignment residual in pixels (lower = better).
    Mastronarde & Held 2017; cutoffs operational."""
    v = m.get("tilt_residual_pixels", m.get("mean_residual_px"))
    if v is None:
        return None
    v = float(v)
    threshold = 1.0
    passed = v <= threshold
    if v <= 0.5:
        level = "GOLD"
    elif v <= 1.0:
        level = "SILVER"
    elif v <= 3.0:
        level = "BRONZE"
    else:
        level = "FAIL"
    msg = f"tilt residual={v:.2f} px" + ("" if passed else f" > {threshold} px (IMOD/AreTomo community)")
    return ("cryo_et_tilt_residual", v, threshold, passed, level, msg)


def _gate_cryo_et_defocus_range(m: dict) -> Optional[tuple]:
    """Mean defocus in µm should be in [-8.0, -0.5] for cryo-ET.
    Hagen 2017 dose-symmetric tilt schemes."""
    v = m.get("defocus_um", m.get("mean_defocus_um"))
    if v is None:
        return None
    v = float(v)
    # Negative values; outside [-8, -0.5] is implausible
    in_range = -8.0 <= v <= -0.5
    level = "GOLD" if in_range else "FAIL"
    msg = f"defocus={v:.2f} µm" + ("" if in_range else " outside [-8.0, -0.5] µm range (Hagen 2017)")
    return ("cryo_et_defocus_range", v, 0.0, in_range, level, msg)


# Domain → list of gate functions to apply
_GATE_REGISTRY: dict[str, list] = {
    "hts":             [_gate_hts_z_prime, _gate_hts_signal_window],
    "ich_s5":          [_gate_ich_s5_safety_margin],
    "ich_s7":          [_gate_ich_s7b_herg_margin],
    "clinical_trial":  [_gate_boin_dlt_boundary],
    "allometric":      [_gate_allometric_r_squared],
    "ivive":           [_gate_ivive_fold_error],
    "openfe":          [_gate_openfe_cycle_closure],
    "p0_pkpd":         [_gate_p0_pkpd_weight_loss],
    "pocket_detection":[_gate_pocket_druggability],
    "aizynthfinder":   [_gate_aizynth_solved_routes],
    "structure_prediction": [
        _gate_struct_pred_mean_plddt,
        _gate_struct_pred_confident_fraction,
        _gate_struct_pred_max_pae,
    ],
    "cancer_biology": [
        _gate_cancer_somatic_vaf_min,
        _gate_cancer_somatic_depth_min,
        _gate_cancer_somatic_mapping_quality,
    ],
    "cryo_em": [
        _gate_cryo_em_fsc_resolution,
        _gate_cryo_em_motion_drift,
        _gate_cryo_em_particle_count,
    ],
    "cryo_et": [
        _gate_cryo_et_sta_fsc_resolution,
        _gate_cryo_et_tilt_residual,
        _gate_cryo_et_defocus_range,
    ],
}


def read_gate_json(path: str | Path) -> Optional[dict]:
    """Read a *_qc.json artifact emitted by a workflow's main.nf.

    Returns the parsed dict, or None if the file is missing / unparseable.
    Never raises — safe to call on every workflow output dir.
    """
    p = Path(path)
    if not p.exists():
        return None
    try:
        with open(p) as f:
            data = json.load(f)
    except Exception as exc:
        log.warning("failed to parse gate JSON %s: %s", p, exc)
        return None
    if not isinstance(data, dict):
        log.warning("gate JSON %s root is not a dict", p)
        return None
    return data


def build_gate_event(
    workflow_name: str,
    domain: str,
    metrics: dict,
    phase: str = "phase_1",
) -> dict:
    """Build an SSE-shaped event dict from raw metrics for the given domain.

    The output dict has IDENTICAL shape to what
    autoloop_bridge.evaluate_and_emit sends as "autoloop_gate_results",
    so the existing frontend panel renders it without any change. Each
    gate carries an `evidence` field populated from qc_evidence.yaml.
    """
    gate_funcs = _GATE_REGISTRY.get(domain, [])
    gate_results: list[dict] = []
    for fn in gate_funcs:
        try:
            result = fn(metrics)
        except Exception as exc:
            log.warning("gate %s in domain %s failed: %s", fn.__name__, domain, exc)
            continue
        if result is None:
            continue
        gate_name, value, threshold, passed, level, msg = result
        gate_results.append({
            "gate":      gate_name,
            "action":    "pass" if passed else (
                "advisory" if level in ("SILVER", "BRONZE") else "halt"
            ),
            "level":     level,
            "value":     value,
            "threshold": threshold,
            "message":   msg,
            "evidence":  get_evidence_for_gate(domain, gate_name),
        })

    all_passed = all(g["action"] == "pass" for g in gate_results)
    if any(g["level"] == "FAIL" for g in gate_results):
        overall = "FAIL"
    elif any(g["level"] == "BRONZE" for g in gate_results):
        overall = "BRONZE"
    elif any(g["level"] == "SILVER" for g in gate_results):
        overall = "SILVER"
    else:
        overall = "GOLD"

    return {
        "phase":         phase,
        "domain":        domain,
        "workflow":      workflow_name,
        "overall_level": overall,
        "passed":        all_passed,
        "gates":         gate_results,
    }


def list_supported_domains() -> list[str]:
    """Return the domains for which gates are wired in this reader."""
    return list(_GATE_REGISTRY.keys())


# ═══════════════════════════════════════════════════════════════════════
# 6 additional domains added 2026-05-26 (LNP, nlmixr2 popPK, antibody
# developability, siRNA off-target, polymorph stability, biomarker enrichment)
# ═══════════════════════════════════════════════════════════════════════

def _gate_lnp_z_avg_particle_size(m: dict) -> Optional[tuple]:
    v = m.get("z_avg_nm")
    if v is None: return None
    v = float(v)
    if 60.0 <= v <= 120.0: return ("lnp_z_avg_particle_size", v, 120.0, True, "SILVER", f"Z-avg {v:.1f} nm in CLT")
    if 40.0 <= v < 60.0 or 120.0 < v <= 150.0: return ("lnp_z_avg_particle_size", v, 120.0, True, "BRONZE", f"Z-avg {v:.1f} nm advisory")
    return ("lnp_z_avg_particle_size", v, 120.0, False, "FAIL", f"Z-avg {v:.1f} nm out of range")

def _gate_lnp_pdi(m: dict) -> Optional[tuple]:
    v = m.get("pdi")
    if v is None: return None
    v = float(v)
    if v < 0.2: return ("lnp_pdi", v, 0.2, True, "SILVER", f"PDI {v:.3f}")
    if v <= 0.3: return ("lnp_pdi", v, 0.2, True, "BRONZE", f"PDI {v:.3f}")
    return ("lnp_pdi", v, 0.2, False, "FAIL", f"PDI {v:.3f} > 0.3")

def _gate_lnp_encapsulation_efficiency(m: dict) -> Optional[tuple]:
    v = m.get("encapsulation_efficiency_pct")
    if v is None: return None
    v = float(v)
    if v >= 85.0: return ("lnp_encapsulation_efficiency", v, 85.0, True, "SILVER", f"EE {v:.1f}%")
    if v >= 70.0: return ("lnp_encapsulation_efficiency", v, 85.0, True, "BRONZE", f"EE {v:.1f}%")
    return ("lnp_encapsulation_efficiency", v, 85.0, False, "FAIL", f"EE {v:.1f}% < 70%")

def _gate_nlmixr2_eta_shrinkage(m: dict) -> Optional[tuple]:
    v = m.get("eta_shrinkage_pct_max")
    if v is None: return None
    v = float(v)
    if v < 20.0: return ("nlmixr2_eta_shrinkage", v, 20.0, True, "GOLD", f"η-shrinkage {v:.1f}%")
    if v <= 30.0: return ("nlmixr2_eta_shrinkage", v, 30.0, True, "SILVER", f"η-shrinkage {v:.1f}%")
    return ("nlmixr2_eta_shrinkage", v, 30.0, False, "FAIL", f"η-shrinkage {v:.1f}%")

def _gate_nlmixr2_condition_number(m: dict) -> Optional[tuple]:
    v = m.get("condition_number")
    if v is None: return None
    v = float(v)
    if v < 100.0: return ("nlmixr2_condition_number", v, 100.0, True, "SILVER", f"Cond {v:.1f}")
    if v <= 1000.0: return ("nlmixr2_condition_number", v, 1000.0, True, "BRONZE", f"Cond {v:.1f}")
    return ("nlmixr2_condition_number", v, 1000.0, False, "FAIL", f"Cond {v:.1f} ill-conditioned")

def _gate_nlmixr2_ofv_stability(m: dict) -> Optional[tuple]:
    v = m.get("ofv_delta_max")
    if v is None: return None
    v = float(v)
    if v < 1.0: return ("nlmixr2_ofv_stability", v, 1.0, True, "BRONZE", f"|ΔOFV| {v:.2f}")
    if v < 3.84: return ("nlmixr2_ofv_stability", v, 3.84, True, "BRONZE", f"|ΔOFV| {v:.2f}")
    return ("nlmixr2_ofv_stability", v, 3.84, False, "FAIL", f"|ΔOFV| {v:.2f}")

def _gate_ab_tap_cdr_length(m: dict) -> Optional[tuple]:
    v = m.get("tap_total_cdr_length")
    if v is None: return None
    v = float(v)
    if 43 <= v <= 63: return ("ab_tap_cdr_length", v, 63.0, True, "GOLD", f"CDR {v:.0f} CST")
    if 40 <= v < 43 or 63 < v <= 67: return ("ab_tap_cdr_length", v, 63.0, True, "SILVER", f"CDR {v:.0f}")
    return ("ab_tap_cdr_length", v, 63.0, False, "FAIL", f"CDR {v:.0f} outside")

def _gate_ab_tap_surface_hydrophobicity(m: dict) -> Optional[tuple]:
    v = m.get("tap_psh_score")
    if v is None: return None
    v = float(v)
    p = 90.0 <= v <= 150.0
    return ("ab_tap_surface_hydrophobicity", v, 150.0, p, "GOLD" if p else "FAIL", f"PSH {v:.1f}")

def _gate_ab_camsol_intrinsic_solubility(m: dict) -> Optional[tuple]:
    v = m.get("camsol_intrinsic_score")
    if v is None: return None
    v = float(v)
    if v >= 1.0: return ("ab_camsol_intrinsic_solubility", v, 1.0, True, "SILVER", f"CamSol {v:.2f}")
    if v >= 0.0: return ("ab_camsol_intrinsic_solubility", v, 1.0, True, "BRONZE", f"CamSol {v:.2f}")
    return ("ab_camsol_intrinsic_solubility", v, 0.0, False, "FAIL", f"CamSol {v:.2f}")

def _gate_sirna_seed_mismatch_count(m: dict) -> Optional[tuple]:
    v = m.get("min_seed_mismatches")
    if v is None: return None
    v = float(v)
    if v >= 2: return ("sirna_seed_mismatch_count", v, 2.0, True, "SILVER", f"Seed mm {int(v)}")
    if v >= 1: return ("sirna_seed_mismatch_count", v, 2.0, True, "BRONZE", f"Seed mm {int(v)} advisory")
    return ("sirna_seed_mismatch_count", v, 2.0, False, "FAIL", f"Seed mm {int(v)}")

def _gate_sirna_thermodynamic_asymmetry(m: dict) -> Optional[tuple]:
    v = m.get("delta_dg_asymmetry_kcal_mol")
    if v is None: return None
    v = float(v)
    if v >= 0.5: return ("sirna_thermodynamic_asymmetry", v, 0.5, True, "GOLD", f"ΔdG {v:.2f}")
    if v >= 0.0: return ("sirna_thermodynamic_asymmetry", v, 0.5, True, "SILVER", f"ΔdG {v:.2f}")
    return ("sirna_thermodynamic_asymmetry", v, 0.5, False, "FAIL", f"ΔdG {v:.2f}")

def _gate_assay_degradation_accelerated(m: dict) -> Optional[tuple]:
    v = m.get("assay_loss_pct_6mo_accelerated")
    if v is None: return None
    v = float(v)
    p = v < 5.0
    return ("assay_degradation_accelerated", v, 5.0, p, "GOLD" if p else "FAIL", f"Assay loss {v:.1f}%")

def _gate_polymorph_form_conversion(m: dict) -> Optional[tuple]:
    v = m.get("polymorph_conversion_pct")
    if v is None: return None
    v = float(v)
    p = v < 10.0
    return ("polymorph_form_conversion", v, 10.0, p, "SILVER" if p else "FAIL", f"Polymorph conv {v:.1f}%")

def _gate_shelf_life_projection(m: dict) -> Optional[tuple]:
    v = m.get("shelf_life_months_95lcb")
    if v is None: return None
    v = float(v)
    p = v >= 24.0
    return ("shelf_life_projection", v, 24.0, p, "SILVER" if p else "BRONZE", f"Shelf-life {v:.1f}mo")

def _gate_biomarker_positive_hazard_ratio(m: dict) -> Optional[tuple]:
    v = m.get("biomarker_pos_hr")
    if v is None: return None
    v = float(v)
    p = v <= 0.7
    return ("biomarker_positive_hazard_ratio", v, 0.7, p, "SILVER" if p else "FAIL", f"BM+ HR {v:.3f}")

def _gate_predictive_prevalence(m: dict) -> Optional[tuple]:
    v = m.get("biomarker_prevalence")
    if v is None: return None
    v = float(v)
    p = 0.10 <= v <= 0.50
    return ("predictive_prevalence", v, 0.50, p, "SILVER" if p else "BRONZE", f"Prev {v:.2f}")

def _gate_phase3_enrichment_factor(m: dict) -> Optional[tuple]:
    v = m.get("enrichment_factor")
    if v is None: return None
    v = float(v)
    p = v >= 1.5
    return ("phase3_enrichment_factor", v, 1.5, p, "BRONZE", f"EF {v:.2f}")

_GATE_REGISTRY.update({
    "lnp_formulation": [_gate_lnp_z_avg_particle_size, _gate_lnp_pdi, _gate_lnp_encapsulation_efficiency],
    "nlmixr2_poppk": [_gate_nlmixr2_eta_shrinkage, _gate_nlmixr2_condition_number, _gate_nlmixr2_ofv_stability],
    "antibody_developability": [_gate_ab_tap_cdr_length, _gate_ab_tap_surface_hydrophobicity, _gate_ab_camsol_intrinsic_solubility],
    "sirna_offtarget": [_gate_sirna_seed_mismatch_count, _gate_sirna_thermodynamic_asymmetry],
    "polymorph_stability": [_gate_assay_degradation_accelerated, _gate_polymorph_form_conversion, _gate_shelf_life_projection],
    "biomarker_enrichment": [_gate_biomarker_positive_hazard_ratio, _gate_predictive_prevalence, _gate_phase3_enrichment_factor],
})
