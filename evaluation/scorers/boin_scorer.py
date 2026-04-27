"""
boin_scorer.py
--------------
Parses BOIN/clinical_trial_simulation workflow output files and computes
MTD accuracy metrics.

Expected output formats from clinical_trial_simulation workflow:
  - mtd_recommendation.json     : recommended MTD level + safety flags
  - dose_escalation_report.csv  : per-level DLT rates from simulation
  - simulation_summary.json     : operating characteristics + MTD distribution

All functions are stateless and pure — safe to call from multiple threads.

Reference: Yuan Y et al. "Bayesian optimal interval design: a simple and
well-performing design for Phase I oncology trials."
Clin Cancer Res. 2016;22(17):4291-4301.

Targets:
  MTD exact accuracy >= 0.70
  MTD adjacent accuracy >= 0.90  (|predicted_level - true_level| <= 1)
  DLT rate at MTD within [target*0.7, target*1.3] for >= 90% of simulations
"""

from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Union


# ---------------------------------------------------------------------------
# Safety flag constants
# ---------------------------------------------------------------------------

FLAG_MTD_NOT_REACHED       = "MTD_NOT_REACHED"
FLAG_HIGH_DLT_START        = "HIGH_DLT_AT_STARTING_DOSE"
FLAG_TRIAL_SHOULD_STOP     = "TRIAL_SHOULD_STOP"

# DLT rate at starting dose that triggers HIGH_DLT_AT_STARTING_DOSE
HIGH_DLT_THRESHOLD = 0.33


def _safe_float(val: Any) -> Optional[float]:
    try:
        return float(val)
    except (TypeError, ValueError):
        return None


def _safe_int(val: Any) -> Optional[int]:
    try:
        return int(val)
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------------------
# Output parser
# ---------------------------------------------------------------------------

def parse_boin_output(output_dir: Union[str, Path]) -> Dict[str, Any]:
    """
    Parse clinical_trial_simulation workflow output into a standardised dict.

    Search order:
      1. mtd_recommendation.json
      2. simulation_summary.json  (key: mtd or recommended_dose)
      3. dose_escalation_report.csv  (pick the dose level with highest selection %)
      4. operating_characteristics.json  (BOIN output table)

    Returns:
        {
            "recommended_MTD_mg":    float or None,
            "recommended_MTD_level": int or None,   (1-indexed dose level)
            "DLT_rate_at_MTD":       float or None,
            "safety_flags":          list[str],     (e.g. ["MTD_NOT_REACHED"])
            "selection_pct_per_level": list[float] or None,
            "operating_characteristics": dict or None,
        }
    """
    result: Dict[str, Any] = {
        "recommended_MTD_mg":       None,
        "recommended_MTD_level":    None,
        "DLT_rate_at_MTD":          None,
        "safety_flags":             [],
        "selection_pct_per_level":  None,
        "operating_characteristics": None,
    }

    d = Path(output_dir)
    if not d.exists():
        return result

    # ── mtd_recommendation.json ────────────────────────────────────────────
    mtd_path = d / "mtd_recommendation.json"
    if mtd_path.exists():
        try:
            with open(mtd_path) as f:
                raw = json.load(f)
            result.update(_extract_from_mtd_json(raw))
            return result
        except Exception:
            pass

    # ── simulation_summary.json ────────────────────────────────────────────
    sim_path = d / "simulation_summary.json"
    if sim_path.exists():
        try:
            with open(sim_path) as f:
                raw = json.load(f)
            extracted = _extract_from_sim_summary(raw)
            if extracted.get("recommended_MTD_level") is not None:
                result.update(extracted)
                return result
        except Exception:
            pass

    # ── dose_escalation_report.csv ────────────────────────────────────────
    csv_path = d / "dose_escalation_report.csv"
    if csv_path.exists():
        extracted = _extract_from_escalation_csv(csv_path)
        if extracted.get("recommended_MTD_level") is not None:
            result.update(extracted)
            return result

    # ── operating_characteristics.json ────────────────────────────────────
    oc_path = d / "operating_characteristics.json"
    if oc_path.exists():
        try:
            with open(oc_path) as f:
                raw = json.load(f)
            extracted = _extract_from_oc_json(raw)
            result.update(extracted)
            return result
        except Exception:
            pass

    return result


def _extract_from_mtd_json(raw: dict) -> dict:
    """Extract MTD fields from mtd_recommendation.json."""
    result: Dict[str, Any] = {}

    # Normalise keys
    norm = {k.lower().replace("-", "_").replace(" ", "_"): v for k, v in raw.items()}

    # recommended dose
    for key in ("recommended_mtd_mg", "mtd_mg", "recommended_dose_mg", "mtd"):
        if key in norm:
            result["recommended_MTD_mg"] = _safe_float(norm[key])
            break

    # recommended level
    for key in ("recommended_mtd_level", "mtd_level", "recommended_dose_level",
                "dose_level", "level"):
        if key in norm:
            result["recommended_MTD_level"] = _safe_int(norm[key])
            break

    # DLT rate at MTD
    for key in ("dlt_rate_at_mtd", "dlt_rate", "estimated_dlt_rate",
                "toxicity_rate_at_mtd"):
        if key in norm:
            result["DLT_rate_at_MTD"] = _safe_float(norm[key])
            break

    # Safety flags
    flags: List[str] = []
    raw_flags = norm.get("safety_flags") or norm.get("flags") or []
    if isinstance(raw_flags, list):
        flags = [str(f).upper() for f in raw_flags]
    elif isinstance(raw_flags, str):
        flags = [raw_flags.upper()]

    # Infer MTD not reached
    if norm.get("mtd_not_reached") or norm.get("no_mtd_found"):
        if FLAG_MTD_NOT_REACHED not in flags:
            flags.append(FLAG_MTD_NOT_REACHED)
        result["recommended_MTD_mg"] = None
        result["recommended_MTD_level"] = None

    result["safety_flags"] = flags

    # Operating characteristics (pass through if present)
    if "operating_characteristics" in norm:
        result["operating_characteristics"] = norm["operating_characteristics"]

    # Selection percentages
    if "selection_pct_per_level" in norm:
        result["selection_pct_per_level"] = norm["selection_pct_per_level"]
    elif "selection_percentages" in norm:
        result["selection_pct_per_level"] = norm["selection_percentages"]

    return result


def _extract_from_sim_summary(raw: dict) -> dict:
    """Extract from simulation_summary.json (flexible key names)."""
    result: Dict[str, Any] = {}
    norm = {k.lower().replace("-", "_").replace(" ", "_"): v for k, v in raw.items()}

    # Try nested mtd block
    for key in ("mtd", "recommended_dose", "mtd_recommendation"):
        if key in norm and isinstance(norm[key], dict):
            return _extract_from_mtd_json(norm[key])

    # Flat keys
    for key in ("recommended_mtd_level", "mtd_level", "optimal_dose_level"):
        if key in norm:
            result["recommended_MTD_level"] = _safe_int(norm[key])
            break

    for key in ("recommended_mtd_mg", "mtd_mg", "optimal_dose_mg"):
        if key in norm:
            result["recommended_MTD_mg"] = _safe_float(norm[key])
            break

    flags: List[str] = []
    if norm.get("mtd_not_reached"):
        flags.append(FLAG_MTD_NOT_REACHED)
        result["recommended_MTD_level"] = None
        result["recommended_MTD_mg"] = None
    result["safety_flags"] = flags
    return result


def _extract_from_escalation_csv(csv_path: Path) -> dict:
    """
    Parse dose_escalation_report.csv.
    Expects columns: dose_level, dose_mg, dlt_rate, selection_pct
    (or similar). Returns the dose level with the highest selection_pct.
    """
    result: Dict[str, Any] = {}
    try:
        with open(csv_path, newline="") as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        if not rows:
            return result

        # Normalise column names
        norm_rows = []
        for row in rows:
            norm_row = {
                k.strip().lower().replace("-", "_").replace(" ", "_"): v.strip()
                for k, v in row.items()
            }
            norm_rows.append(norm_row)

        # Find selection_pct column
        pct_col = None
        for col in ("selection_pct", "selection_percentage", "pct_selected",
                    "selection_prob", "percent_selected"):
            if col in norm_rows[0]:
                pct_col = col
                break

        level_col = None
        for col in ("dose_level", "level", "dose_index"):
            if col in norm_rows[0]:
                level_col = col
                break

        mg_col = None
        for col in ("dose_mg", "dose", "mg"):
            if col in norm_rows[0]:
                mg_col = col
                break

        dlt_col = None
        for col in ("dlt_rate", "dlt_probability", "toxicity_rate",
                    "observed_dlt_rate"):
            if col in norm_rows[0]:
                dlt_col = col
                break

        # Pick highest selection %
        best_row = None
        best_pct = -1.0
        for row in norm_rows:
            if pct_col:
                pct = _safe_float(row.get(pct_col, 0)) or 0.0
                if pct > best_pct:
                    best_pct = pct
                    best_row = row

        if best_row is None:
            best_row = norm_rows[-1]  # fallback to last level

        if level_col:
            result["recommended_MTD_level"] = _safe_int(best_row.get(level_col))
        if mg_col:
            result["recommended_MTD_mg"] = _safe_float(best_row.get(mg_col))
        if dlt_col:
            result["DLT_rate_at_MTD"] = _safe_float(best_row.get(dlt_col))

        # Selection percentages per level
        if pct_col:
            result["selection_pct_per_level"] = [
                _safe_float(r.get(pct_col)) for r in norm_rows
            ]

        result["safety_flags"] = []
    except Exception:
        pass
    return result


def _extract_from_oc_json(raw: dict) -> dict:
    """Extract from operating_characteristics.json."""
    result: Dict[str, Any] = {"safety_flags": []}
    norm = {k.lower().replace("-", "_").replace(" ", "_"): v for k, v in raw.items()}

    for key in ("recommended_level", "mtd_level", "selected_dose_level"):
        if key in norm:
            result["recommended_MTD_level"] = _safe_int(norm[key])
            break

    for key in ("recommended_dose_mg", "mtd_mg", "selected_dose_mg"):
        if key in norm:
            result["recommended_MTD_mg"] = _safe_float(norm[key])
            break

    result["operating_characteristics"] = raw
    return result


# ---------------------------------------------------------------------------
# Per-case scorer
# ---------------------------------------------------------------------------

def score_boin_case(
    predicted: Dict[str, Any],
    reference: Dict[str, Any],
    dlt_rate_target: float = 0.25,
) -> Dict[str, Any]:
    """
    Score a single BOIN/clinical trial case against reference.

    Args:
        predicted:        dict from parse_boin_output
        reference:        dict from cases.yaml — keys: true_MTD_level,
                          true_MTD_mg, safety_flags, true_dlt_rate_per_level
        dlt_rate_target:  target DLT rate from the scenario inputs

    Returns:
        {
            "mtd_exact":          bool   — predicted level == true level
            "mtd_adjacent":       bool   — |predicted - true| <= 1
            "safety_flags_correct": bool  — all required safety flags present
            "dlt_rate_in_band":   bool   — predicted DLT at MTD within [target*0.7, target*1.3]
            "overall_score":      float  — weighted composite (0.0–1.0)
            "details": {
                "predicted_MTD_level": ...,
                "true_MTD_level": ...,
                "predicted_MTD_mg": ...,
                "true_MTD_mg": ...,
                "predicted_safety_flags": [...],
                "reference_safety_flags": [...],
            }
        }
    """
    true_level  = reference.get("true_MTD_level")   # may be None if MTD not reached
    true_mg     = reference.get("true_MTD_mg")
    ref_flags   = [str(f).upper() for f in (reference.get("safety_flags") or [])]

    pred_level  = predicted.get("recommended_MTD_level")
    pred_mg     = predicted.get("recommended_MTD_mg")
    pred_dlt    = predicted.get("DLT_rate_at_MTD")
    pred_flags  = [str(f).upper() for f in (predicted.get("safety_flags") or [])]

    # ── mtd_exact ─────────────────────────────────────────────────────────
    # Special case: if true MTD is null (MTD_NOT_REACHED), exact match means
    # the predicted level is also None/null.
    if true_level is None:
        mtd_exact = (pred_level is None)
    else:
        mtd_exact = (pred_level is not None and pred_level == true_level)

    # ── mtd_adjacent ──────────────────────────────────────────────────────
    if true_level is None:
        # adjacent = predicted level is also None
        mtd_adjacent = (pred_level is None)
    elif pred_level is None:
        mtd_adjacent = False
    else:
        mtd_adjacent = abs(pred_level - true_level) <= 1

    # ── safety_flags_correct ─────────────────────────────────────────────
    # All reference flags must appear in predicted flags.
    # No false positives penalty (to avoid penalising conservative warnings).
    if ref_flags:
        safety_flags_correct = all(f in pred_flags for f in ref_flags)
    else:
        # Reference has no required flags — correct if BioMate also raises none
        # that look like false alarms (allow empty predicted flags)
        safety_flags_correct = True

    # ── dlt_rate_in_band ─────────────────────────────────────────────────
    if pred_dlt is not None and dlt_rate_target > 0:
        lo = dlt_rate_target * 0.7
        hi = dlt_rate_target * 1.3
        dlt_rate_in_band = lo <= pred_dlt <= hi
    else:
        # If MTD not reached, DLT rate check is N/A — treat as passing
        # (not penalised for missing output)
        dlt_rate_in_band = true_level is None

    # ── overall_score ─────────────────────────────────────────────────────
    # Weights: mtd_exact=0.40, mtd_adjacent=0.30, safety_flags=0.20, dlt_band=0.10
    overall_score = (
        0.40 * float(mtd_exact)
        + 0.30 * float(mtd_adjacent)
        + 0.20 * float(safety_flags_correct)
        + 0.10 * float(dlt_rate_in_band)
    )

    return {
        "mtd_exact":            mtd_exact,
        "mtd_adjacent":         mtd_adjacent,
        "safety_flags_correct": safety_flags_correct,
        "dlt_rate_in_band":     dlt_rate_in_band,
        "overall_score":        overall_score,
        "details": {
            "predicted_MTD_level":    pred_level,
            "true_MTD_level":         true_level,
            "predicted_MTD_mg":       pred_mg,
            "true_MTD_mg":            true_mg,
            "predicted_DLT_at_MTD":   pred_dlt,
            "predicted_safety_flags": pred_flags,
            "reference_safety_flags": ref_flags,
        },
    }


# ---------------------------------------------------------------------------
# Batch scorer
# ---------------------------------------------------------------------------

def score_boin_batch(
    all_results: List[Dict[str, Any]],
    cases: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """
    Aggregate BOIN scores over all 20 (or N) scenarios.

    Args:
        all_results: list of per-case score dicts from score_boin_case
        cases:       list of case dicts from cases.yaml (for metadata)

    Returns:
        {
            "n_cases":             int
            "mtd_exact_rate":      float  — fraction with exact MTD match
            "mtd_adjacent_rate":   float  — fraction within 1 level
            "safety_flag_rate":    float  — fraction with correct safety flags
            "dlt_band_rate":       float  — fraction with DLT in acceptance band
            "mean_overall_score":  float  — mean composite score
            "by_difficulty":       dict   — breakdown by easy/medium/hard
            "passes_exact_target":    bool  — mtd_exact_rate >= 0.70
            "passes_adjacent_target": bool  — mtd_adjacent_rate >= 0.90
        }
    """
    if not all_results:
        return {
            "n_cases": 0,
            "mtd_exact_rate": 0.0,
            "mtd_adjacent_rate": 0.0,
            "safety_flag_rate": 0.0,
            "dlt_band_rate": 0.0,
            "mean_overall_score": 0.0,
            "by_difficulty": {},
            "passes_exact_target": False,
            "passes_adjacent_target": False,
        }

    n = len(all_results)
    exact_hits    = sum(1 for r in all_results if r.get("mtd_exact") is True)
    adj_hits      = sum(1 for r in all_results if r.get("mtd_adjacent") is True)
    flag_hits     = sum(1 for r in all_results if r.get("safety_flags_correct") is True)
    band_hits     = sum(1 for r in all_results if r.get("dlt_rate_in_band") is True)
    overall_scores = [r.get("overall_score", 0.0) for r in all_results]

    exact_rate   = exact_hits / n
    adj_rate     = adj_hits / n
    flag_rate    = flag_hits / n
    band_rate    = band_hits / n
    mean_overall = sum(overall_scores) / n

    # Per-difficulty breakdown
    difficulty_map: Dict[str, List[Dict]] = {}
    for i, res in enumerate(all_results):
        diff = cases[i].get("difficulty", "unknown") if i < len(cases) else "unknown"
        difficulty_map.setdefault(diff, []).append(res)

    by_difficulty: Dict[str, Any] = {}
    for diff, group in difficulty_map.items():
        gn = len(group)
        by_difficulty[diff] = {
            "n":                  gn,
            "mtd_exact_rate":     sum(1 for r in group if r.get("mtd_exact")) / gn,
            "mtd_adjacent_rate":  sum(1 for r in group if r.get("mtd_adjacent")) / gn,
            "mean_overall_score": sum(r.get("overall_score", 0) for r in group) / gn,
        }

    return {
        "n_cases":             n,
        "mtd_exact_rate":      exact_rate,
        "mtd_adjacent_rate":   adj_rate,
        "safety_flag_rate":    flag_rate,
        "dlt_band_rate":       band_rate,
        "mean_overall_score":  mean_overall,
        "by_difficulty":       by_difficulty,
        "passes_exact_target":    exact_rate >= 0.70,
        "passes_adjacent_target": adj_rate >= 0.90,
    }
