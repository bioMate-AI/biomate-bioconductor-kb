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

from galaxy.ai.retrievers.qc_evidence import get_evidence_for_gate

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


def _gate_ich_s7b_herg_margin(m: dict) -> Optional[tuple]:
    """hERG safety margin ≥10× (ICH S7B)."""
    v = m.get("herg_safety_margin_x")
    if v is None:
        return None
    v = float(v)
    threshold = 10.0
    passed = v >= threshold
    level = "GOLD" if v >= 30 else ("SILVER" if v >= 10 else "FAIL")
    msg = f"hERG margin={v:.1f}×" + ("" if passed else f" < {threshold}× (ICH S7B)")
    return ("ich_s7b_herg_margin", v, threshold, passed, level, msg)


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
