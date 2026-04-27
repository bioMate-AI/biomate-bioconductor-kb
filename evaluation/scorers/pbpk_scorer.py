"""
pbpk_scorer.py
--------------
Parses PBPK workflow output files and computes 2-fold accuracy metrics.

Expected output formats from pbpk_simulation workflow:
  - pk_summary.csv       : Cmax_uM, AUC_uM_h, t_half_h, Tmax_h, CL_L_h, Vd_L
  - pk_parameters.csv    : same as above (alternate name)
  - simulation_results.json : nested dict with pk_parameters key
  - nca_parameters.json  : NCA-derived PK parameters

All functions are stateless and pure — safe to call from multiple threads.

Reference acceptance criterion (FDA PBPK Guidance):
  "within 2-fold" = predicted/observed in [0.5, 2.0]
  MAFE target: mean(|log2(predicted/observed)|) <= 1.0
"""

from __future__ import annotations

import csv
import json
import math
from pathlib import Path
from typing import Any, Dict, List, Optional, Union


# ---------------------------------------------------------------------------
# PK parameter column name aliases across different output file formats
# ---------------------------------------------------------------------------

_CMAX_ALIASES = {
    "cmax_um", "cmax", "c_max", "peak_concentration_um",
    "cmax_ng_ml",   # converted below if unit suffix detected
    "cmax_ug_l",
}
_AUC_ALIASES = {
    "auc_um_h", "auc", "auc_0inf", "auc_0_inf", "auc_0inf_um_h",
    "auc_last_um_h", "auc_0t", "area_under_curve",
}
_THALF_ALIASES = {
    "t_half_h", "thalf_h", "t_half", "half_life_h", "half_life",
    "terminal_half_life_h", "t1_2_h",
}
_TMAX_ALIASES = {
    "tmax_h", "tmax", "t_max_h", "t_max", "time_to_cmax_h",
}
_CL_ALIASES = {
    "cl_l_h", "cl", "clearance_l_h", "systemic_cl_l_h",
    "total_clearance_l_h",
}
_VD_ALIASES = {
    "vd_l", "vd", "volume_distribution_l", "vss_l",
    "apparent_volume_l",
}


def _find_col(header_row: List[str], aliases: set) -> Optional[int]:
    """Return the index of the first column whose normalised name matches any alias."""
    for i, col in enumerate(header_row):
        norm = col.strip().lower().replace(" ", "_").replace("-", "_")
        if norm in aliases:
            return i
    return None


def _safe_float(val: Any) -> Optional[float]:
    """Convert val to float; return None on failure."""
    try:
        return float(val)
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------------------
# Output parser
# ---------------------------------------------------------------------------

def parse_pbpk_output(output_dir: Union[str, Path]) -> Dict[str, Optional[float]]:
    """
    Parse PBPK workflow output into a standardised PK parameter dict.

    Search order:
      1. pk_summary.csv
      2. pk_parameters.csv
      3. simulation_results.json  (key: pk_parameters or nca_parameters)
      4. nca_parameters.json

    Returns:
        {
            "Cmax_uM":  float or None,
            "AUC_uM_h": float or None,
            "t_half_h": float or None,
            "Tmax_h":   float or None,
            "CL_L_h":   float or None,
            "Vd_L":     float or None,
        }
    All values are in SI-consistent units (uM for concentration, hours for time,
    L or L/h for distribution/clearance).
    """
    out: Dict[str, Optional[float]] = {
        "Cmax_uM":  None,
        "AUC_uM_h": None,
        "t_half_h": None,
        "Tmax_h":   None,
        "CL_L_h":   None,
        "Vd_L":     None,
    }

    d = Path(output_dir)
    if not d.exists():
        return out

    # ── Try CSV files first ────────────────────────────────────────────────
    for csv_name in ("pk_summary.csv", "pk_parameters.csv"):
        csv_path = d / csv_name
        if csv_path.exists():
            result = _parse_pk_csv(csv_path)
            if any(v is not None for v in result.values()):
                out.update(result)
                return out

    # ── Try JSON files ─────────────────────────────────────────────────────
    for json_name in ("simulation_results.json", "nca_parameters.json"):
        json_path = d / json_name
        if json_path.exists():
            result = _parse_pk_json(json_path)
            if any(v is not None for v in result.values()):
                out.update(result)
                return out

    return out


def _parse_pk_csv(csv_path: Path) -> Dict[str, Optional[float]]:
    """Parse a CSV file and extract PK parameters from the first data row."""
    out: Dict[str, Optional[float]] = {
        "Cmax_uM": None, "AUC_uM_h": None, "t_half_h": None,
        "Tmax_h": None, "CL_L_h": None, "Vd_L": None,
    }
    try:
        with open(csv_path, newline="") as f:
            reader = csv.reader(f)
            rows = list(reader)
        if len(rows) < 2:
            return out
        header = rows[0]
        data = rows[1]  # first data row

        mapping = [
            ("Cmax_uM",  _CMAX_ALIASES),
            ("AUC_uM_h", _AUC_ALIASES),
            ("t_half_h", _THALF_ALIASES),
            ("Tmax_h",   _TMAX_ALIASES),
            ("CL_L_h",   _CL_ALIASES),
            ("Vd_L",     _VD_ALIASES),
        ]
        for key, aliases in mapping:
            idx = _find_col(header, aliases)
            if idx is not None and idx < len(data):
                out[key] = _safe_float(data[idx])
    except Exception:
        pass
    return out


def _parse_pk_json(json_path: Path) -> Dict[str, Optional[float]]:
    """Parse a JSON file (flat dict or nested under pk_parameters/nca_parameters)."""
    out: Dict[str, Optional[float]] = {
        "Cmax_uM": None, "AUC_uM_h": None, "t_half_h": None,
        "Tmax_h": None, "CL_L_h": None, "Vd_L": None,
    }
    try:
        with open(json_path) as f:
            raw = json.load(f)
        # Unwrap nested containers
        if isinstance(raw, dict):
            for key in ("pk_parameters", "nca_parameters", "results", "pk"):
                if key in raw and isinstance(raw[key], dict):
                    raw = raw[key]
                    break

        if not isinstance(raw, dict):
            return out

        # Normalised key lookup
        norm_map: Dict[str, Any] = {
            k.strip().lower().replace(" ", "_").replace("-", "_"): v
            for k, v in raw.items()
        }

        def _lookup(aliases: set) -> Optional[float]:
            for alias in aliases:
                if alias in norm_map:
                    return _safe_float(norm_map[alias])
            return None

        out["Cmax_uM"]  = _lookup(_CMAX_ALIASES)
        out["AUC_uM_h"] = _lookup(_AUC_ALIASES)
        out["t_half_h"] = _lookup(_THALF_ALIASES)
        out["Tmax_h"]   = _lookup(_TMAX_ALIASES)
        out["CL_L_h"]   = _lookup(_CL_ALIASES)
        out["Vd_L"]     = _lookup(_VD_ALIASES)
    except Exception:
        pass
    return out


# ---------------------------------------------------------------------------
# 2-fold accuracy helpers
# ---------------------------------------------------------------------------

def within_2fold(predicted: float, observed: float) -> bool:
    """
    Return True if predicted is within a factor of 2 of observed.

    Acceptance criterion: 0.5 * observed <= predicted <= 2.0 * observed
    Both values must be positive finite numbers.
    """
    if predicted is None or observed is None:
        return False
    try:
        p = float(predicted)
        o = float(observed)
    except (TypeError, ValueError):
        return False
    if o <= 0 or p <= 0 or not math.isfinite(p) or not math.isfinite(o):
        return False
    return 0.5 * o <= p <= 2.0 * o


def _fold_error(predicted: float, observed: float) -> Optional[float]:
    """
    Return |log2(predicted/observed)| (absolute fold error in log2 units).
    Returns None if either value is non-positive.
    """
    if predicted is None or observed is None:
        return None
    try:
        p = float(predicted)
        o = float(observed)
    except (TypeError, ValueError):
        return None
    if o <= 0 or p <= 0 or not math.isfinite(p) or not math.isfinite(o):
        return None
    return abs(math.log2(p / o))


# ---------------------------------------------------------------------------
# Per-case scorer
# ---------------------------------------------------------------------------

def score_pbpk_case(
    predicted: Dict[str, Optional[float]],
    reference: Dict[str, float],
) -> Dict[str, Any]:
    """
    Score a single PBPK case against published reference PK parameters.

    Args:
        predicted:  dict from parse_pbpk_output — keys Cmax_uM, AUC_uM_h, t_half_h, Tmax_h
        reference:  dict from cases.yaml — same keys with published values

    Returns:
        {
            "cmax_2fold":    bool   — predicted Cmax within 2-fold of reference
            "auc_2fold":     bool   — predicted AUC within 2-fold
            "t_half_2fold":  bool   — predicted t½ within 2-fold
            "overall_2fold": float  — mean of the three 2-fold booleans
            "mafe":          float  — mean absolute fold error (log2) over available params
            "n_params_scored": int  — number of PK parameters with valid predicted values
            "details": {
                "Cmax_uM":  {"predicted": ..., "reference": ..., "fold_error": ..., "within_2fold": bool},
                "AUC_uM_h": {...},
                "t_half_h": {...},
            }
        }
    """
    pk_keys = [
        ("Cmax_uM",  "cmax_2fold"),
        ("AUC_uM_h", "auc_2fold"),
        ("t_half_h", "t_half_2fold"),
    ]

    results = {}
    fold_errors: List[float] = []
    two_fold_flags: List[bool] = []
    details: Dict[str, Any] = {}

    for param_key, score_key in pk_keys:
        pred_val = predicted.get(param_key)
        ref_val  = reference.get(param_key)

        if ref_val is None:
            # Reference not available — skip
            results[score_key] = None
            continue

        in_2fold = within_2fold(pred_val, ref_val)
        fe = _fold_error(pred_val, ref_val)

        results[score_key] = in_2fold
        two_fold_flags.append(in_2fold)
        if fe is not None:
            fold_errors.append(fe)

        details[param_key] = {
            "predicted": pred_val,
            "reference": ref_val,
            "fold_error": fe,
            "within_2fold": in_2fold,
        }

    # overall_2fold: mean of available binary scores
    valid_flags = [f for f in two_fold_flags if f is not None]
    results["overall_2fold"] = (
        sum(valid_flags) / len(valid_flags) if valid_flags else 0.0
    )
    results["mafe"] = (
        sum(fold_errors) / len(fold_errors) if fold_errors else None
    )
    results["n_params_scored"] = len(valid_flags)
    results["details"] = details
    return results


# ---------------------------------------------------------------------------
# Batch scorer
# ---------------------------------------------------------------------------

def score_pbpk_batch(
    all_results: List[Dict[str, Any]],
    cases: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """
    Aggregate PBPK scores over all 15 (or N) cases.

    Args:
        all_results: list of per-case score dicts from score_pbpk_case
        cases:       list of case dicts from cases.yaml (for metadata)

    Returns:
        {
            "n_cases":          int
            "cmax_2fold_frac":  float  — fraction of cases with Cmax within 2-fold
            "auc_2fold_frac":   float
            "t_half_2fold_frac": float
            "overall_2fold":    float  — mean of the three fractions
            "mafe_mean":        float  — mean MAFE across all cases
            "mafe_median":      float
            "by_difficulty":    dict   — breakdown by easy/medium/hard
            "passes_target":    bool   — overall_2fold >= 0.70
        }
    """
    if not all_results:
        return {
            "n_cases": 0,
            "cmax_2fold_frac": 0.0,
            "auc_2fold_frac": 0.0,
            "t_half_2fold_frac": 0.0,
            "overall_2fold": 0.0,
            "mafe_mean": None,
            "mafe_median": None,
            "by_difficulty": {},
            "passes_target": False,
        }

    n = len(all_results)
    cmax_hits = sum(1 for r in all_results if r.get("cmax_2fold") is True)
    auc_hits  = sum(1 for r in all_results if r.get("auc_2fold") is True)
    th_hits   = sum(1 for r in all_results if r.get("t_half_2fold") is True)

    valid_cmax  = sum(1 for r in all_results if r.get("cmax_2fold") is not None)
    valid_auc   = sum(1 for r in all_results if r.get("auc_2fold") is not None)
    valid_th    = sum(1 for r in all_results if r.get("t_half_2fold") is not None)

    cmax_frac  = cmax_hits / valid_cmax  if valid_cmax  else 0.0
    auc_frac   = auc_hits  / valid_auc   if valid_auc   else 0.0
    th_frac    = th_hits   / valid_th    if valid_th    else 0.0
    overall    = (cmax_frac + auc_frac + th_frac) / 3.0

    all_mafes = [r["mafe"] for r in all_results if r.get("mafe") is not None]
    mafe_mean   = sum(all_mafes) / len(all_mafes) if all_mafes else None
    mafe_median = None
    if all_mafes:
        sorted_m = sorted(all_mafes)
        mid = len(sorted_m) // 2
        mafe_median = (
            sorted_m[mid]
            if len(sorted_m) % 2 == 1
            else (sorted_m[mid - 1] + sorted_m[mid]) / 2
        )

    # Per-difficulty breakdown
    difficulty_map: Dict[str, List[Dict]] = {}
    for i, res in enumerate(all_results):
        diff = cases[i].get("difficulty", "unknown") if i < len(cases) else "unknown"
        difficulty_map.setdefault(diff, []).append(res)

    by_difficulty: Dict[str, Any] = {}
    for diff, group in difficulty_map.items():
        gn = len(group)
        g_overall = [r.get("overall_2fold", 0.0) for r in group]
        g_mafe    = [r["mafe"] for r in group if r.get("mafe") is not None]
        by_difficulty[diff] = {
            "n": gn,
            "mean_overall_2fold": sum(g_overall) / gn if gn else 0.0,
            "mean_mafe": sum(g_mafe) / len(g_mafe) if g_mafe else None,
        }

    return {
        "n_cases":           n,
        "cmax_2fold_frac":   cmax_frac,
        "auc_2fold_frac":    auc_frac,
        "t_half_2fold_frac": th_frac,
        "overall_2fold":     overall,
        "mafe_mean":         mafe_mean,
        "mafe_median":       mafe_median,
        "by_difficulty":     by_difficulty,
        "passes_target":     overall >= 0.70,
    }
