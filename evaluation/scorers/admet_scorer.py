"""
admet_scorer.py
---------------
Parses ADMET workflow output files and computes accuracy metrics.

Expected output formats from predict_admet_properties workflow:
  - results.csv            : SMILES, hERG_IC50_uM, hERG_class, DILI_class, Ames_class, Ro5_pass
  - admet_predictions.json : same data in JSON form
  - output.json            : BioMate standard output wrapper (contains the above nested)

All functions are stateless and pure — safe to call from multiple threads.

Reference thresholds (Cavalli 2005 / ICH S7B):
  hERG toxic    = IC50 <  1 µM
  hERG moderate = IC50 1–10 µM
  hERG safe     = IC50 > 10 µM
"""

from __future__ import annotations

import csv
import json
import math
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Union


# ---------------------------------------------------------------------------
# hERG classification thresholds (µM)
# ---------------------------------------------------------------------------
_HERG_TOXIC_THRESHOLD_uM = 1.0
_HERG_MODERATE_THRESHOLD_uM = 10.0


# ---------------------------------------------------------------------------
# Column name aliases — the workflow may use different capitalisation/naming
# ---------------------------------------------------------------------------

_SMILES_COLS = {"smiles", "smi", "canonical_smiles", "input_smiles"}
_HERG_IC50_COLS = {
    "herg_ic50_um", "herg_ic50", "herg_ic50_µm", "herg_ic50_micromolar",
    "herg_ic50(um)", "ic50_um", "ic50_uM",
}
_HERG_CLASS_COLS = {
    "herg_class", "herg_classification", "herg_risk", "herg_toxicity_class",
    "herg_category",
}
_DILI_CLASS_COLS = {
    "dili_class", "dili", "dili_classification", "dili_risk",
    "dili_label", "dili_positive",
}
_AMES_CLASS_COLS = {
    "ames_class", "ames", "ames_classification", "ames_mutagenicity",
    "ames_positive", "ames_label",
}
_RO5_COLS = {
    "ro5_pass", "lipinski_ro5", "lipinski_pass", "ro5", "rule_of_five",
    "ro5_compliant",
}


def _norm_col(name: str) -> str:
    """Normalise a column name to lowercase-underscored form for lookup."""
    return name.strip().lower().replace(" ", "_").replace("-", "_")


def _norm_binary(val: Any) -> Optional[str]:
    """Normalise a binary (positive/negative or true/false) value."""
    if val is None:
        return None
    s = str(val).strip().lower()
    if s in {"positive", "true", "1", "yes", "t", "y", "pos"}:
        return "positive"
    if s in {"negative", "false", "0", "no", "f", "n", "neg"}:
        return "negative"
    return s  # unknown — return as-is for caller inspection


def _norm_ro5(val: Any) -> Optional[bool]:
    """Normalise a Ro5 pass/fail value to bool."""
    if val is None:
        return None
    s = str(val).strip().lower()
    if s in {"true", "1", "yes", "pass", "t", "y"}:
        return True
    if s in {"false", "0", "no", "fail", "f", "n"}:
        return False
    return None


def _norm_herg_class(val: Any) -> Optional[str]:
    """Normalise a hERG class label."""
    if val is None:
        return None
    s = str(val).strip().lower()
    if s in {"toxic", "high", "high_risk", "blocker"}:
        return "toxic"
    if s in {"moderate", "medium", "medium_risk", "borderline"}:
        return "moderate"
    if s in {"safe", "low", "low_risk", "no_risk", "non-blocker"}:
        return "safe"
    return s


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def classify_herg(ic50_uM: Optional[float]) -> str:
    """
    Classify a hERG IC50 value (µM) into toxic / moderate / safe.

    Parameters
    ----------
    ic50_uM : float or None
        Measured or predicted IC50 in micromolar.
        None is treated as safe (not measurable → IC50 > 100 µM).

    Returns
    -------
    str
        One of: "toxic", "moderate", "safe"
    """
    if ic50_uM is None or math.isnan(ic50_uM):
        return "safe"
    if ic50_uM < _HERG_TOXIC_THRESHOLD_uM:
        return "toxic"
    if ic50_uM <= _HERG_MODERATE_THRESHOLD_uM:
        return "moderate"
    return "safe"


def parse_admet_output(output_dir: Union[str, Path]) -> Dict[str, Dict[str, Any]]:
    """
    Parse ADMET workflow output files and return a dict keyed by SMILES.

    Searches the output directory for (in priority order):
      1. results.csv
      2. admet_predictions.json
      3. output.json  (BioMate standard wrapper)

    Returns
    -------
    dict
        {smiles_string: {
            "herg_class":   str  (toxic/moderate/safe or None),
            "herg_ic50_uM": float or None,
            "dili_class":   str  (positive/negative or None),
            "ames_class":   str  (positive/negative or None),
            "ro5_pass":     bool or None,
        }}

    Raises
    ------
    FileNotFoundError
        If no recognised output file is found in output_dir.
    """
    out = Path(output_dir)
    if not out.exists():
        raise FileNotFoundError(f"Output directory does not exist: {out}")

    # ---- Search for candidate files (recurse one level) -------------------
    candidates: List[Path] = []
    for pattern in ("results.csv", "admet_predictions.json", "output.json",
                    "admet_results.csv", "predictions.csv", "admet_output.json"):
        candidates.extend(out.rglob(pattern))

    # Priority: CSV first (most structured), then JSON
    csv_files  = [p for p in candidates if p.suffix.lower() == ".csv"]
    json_files = [p for p in candidates if p.suffix.lower() == ".json"]

    if csv_files:
        return _parse_csv(csv_files[0])
    if json_files:
        for jf in json_files:
            try:
                result = _parse_json(jf)
                if result:
                    return result
            except Exception:
                continue

    raise FileNotFoundError(
        f"No ADMET output file found in {out}. "
        "Expected one of: results.csv, admet_predictions.json, output.json"
    )


def _parse_csv(path: Path) -> Dict[str, Dict[str, Any]]:
    """Parse a CSV output file from the ADMET workflow."""
    results: Dict[str, Dict[str, Any]] = {}
    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        if reader.fieldnames is None:
            return {}
        # Build column → normalised name mapping
        col_map: Dict[str, str] = {_norm_col(c): c for c in reader.fieldnames if c}

        def _get(row: dict, aliases: set) -> Optional[str]:
            for alias in aliases:
                if alias in col_map:
                    return row.get(col_map[alias])
            return None

        for row in reader:
            smiles = _get(row, _SMILES_COLS)
            if not smiles:
                continue

            ic50_raw = _get(row, _HERG_IC50_COLS)
            try:
                ic50 = float(ic50_raw) if ic50_raw and ic50_raw.strip() not in ("", "null", "None") else None
            except (ValueError, AttributeError):
                ic50 = None

            herg_class_raw = _get(row, _HERG_CLASS_COLS)
            herg_class = _norm_herg_class(herg_class_raw) if herg_class_raw else classify_herg(ic50)

            results[smiles.strip()] = {
                "herg_class":   herg_class,
                "herg_ic50_uM": ic50,
                "dili_class":   _norm_binary(_get(row, _DILI_CLASS_COLS)),
                "ames_class":   _norm_binary(_get(row, _AMES_CLASS_COLS)),
                "ro5_pass":     _norm_ro5(_get(row, _RO5_COLS)),
            }
    return results


def _parse_json(path: Path) -> Dict[str, Dict[str, Any]]:
    """Parse a JSON output file; handles both flat list and wrapped formats."""
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)

    # BioMate output.json wrapper: {"results": [...], "status": ...}
    if isinstance(data, dict):
        if "results" in data and isinstance(data["results"], list):
            return _extract_from_list(data["results"])
        if "compounds" in data and isinstance(data["compounds"], list):
            return _extract_from_list(data["compounds"])
        if "predictions" in data and isinstance(data["predictions"], list):
            return _extract_from_list(data["predictions"])
        # Maybe the JSON is a dict keyed by SMILES already
        if data and isinstance(next(iter(data.values())), dict):
            return {
                smi: _normalise_compound_dict(v)
                for smi, v in data.items()
            }

    # Flat list of compound dicts
    if isinstance(data, list):
        return _extract_from_list(data)

    return {}


def _extract_from_list(items: list) -> Dict[str, Dict[str, Any]]:
    results: Dict[str, Dict[str, Any]] = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        smiles = None
        for alias in _SMILES_COLS:
            for key in item:
                if _norm_col(key) == alias:
                    smiles = item[key]
                    break
            if smiles:
                break
        if not smiles:
            continue
        results[smiles.strip()] = _normalise_compound_dict(item)
    return results


def _normalise_compound_dict(item: dict) -> Dict[str, Any]:
    """Extract standardised ADMET fields from an arbitrary compound dict."""
    col_map: Dict[str, Any] = {_norm_col(k): v for k, v in item.items()}

    def _get_by_aliases(aliases: set) -> Any:
        for alias in aliases:
            if alias in col_map:
                return col_map[alias]
        return None

    ic50_raw = _get_by_aliases(_HERG_IC50_COLS)
    try:
        ic50 = float(ic50_raw) if ic50_raw is not None and str(ic50_raw).strip() not in ("", "null", "None") else None
    except (ValueError, TypeError):
        ic50 = None

    herg_class_raw = _get_by_aliases(_HERG_CLASS_COLS)
    herg_class = _norm_herg_class(herg_class_raw) if herg_class_raw else classify_herg(ic50)

    return {
        "herg_class":   herg_class,
        "herg_ic50_uM": ic50,
        "dili_class":   _norm_binary(_get_by_aliases(_DILI_CLASS_COLS)),
        "ames_class":   _norm_binary(_get_by_aliases(_AMES_CLASS_COLS)),
        "ro5_pass":     _norm_ro5(_get_by_aliases(_RO5_COLS)),
    }


def score_admet_case(predicted: Dict[str, Any], reference: Dict[str, Any]) -> Dict[str, float]:
    """
    Score predicted ADMET properties for a single compound against reference values.

    Parameters
    ----------
    predicted : dict
        Keys: herg_class, herg_ic50_uM, dili_class, ames_class, ro5_pass
        (as returned by parse_admet_output for one SMILES)
    reference : dict
        Same keys; from cases.yaml reference block.

    Returns
    -------
    dict
        {
          "herg_accuracy":    float  0.0 or 1.0  (correct class match),
          "dili_accuracy":    float  0.0 or 1.0,
          "ames_accuracy":    float  0.0 or 1.0,
          "ro5_accuracy":     float  0.0 or 1.0,
          "overall_accuracy": float  mean of above 4,
          "completeness":     float  fraction of 4 properties present,
          "herg_ic50_uM":     float or None  (raw IC50 for Spearman ranking),
        }
    """
    scores: Dict[str, float] = {}
    present_count = 0

    # hERG class
    pred_herg = _norm_herg_class(predicted.get("herg_class"))
    ref_herg  = reference.get("herg_class")
    if pred_herg is not None:
        present_count += 1
        scores["herg_accuracy"] = 1.0 if pred_herg == ref_herg else 0.0
    else:
        scores["herg_accuracy"] = 0.0

    # DILI class
    pred_dili = _norm_binary(predicted.get("dili_class"))
    ref_dili  = reference.get("dili_class")
    if pred_dili is not None:
        present_count += 1
        scores["dili_accuracy"] = 1.0 if pred_dili == ref_dili else 0.0
    else:
        scores["dili_accuracy"] = 0.0

    # Ames class
    pred_ames = _norm_binary(predicted.get("ames_class"))
    ref_ames  = reference.get("ames_class")
    if pred_ames is not None:
        present_count += 1
        scores["ames_accuracy"] = 1.0 if pred_ames == ref_ames else 0.0
    else:
        scores["ames_accuracy"] = 0.0

    # Ro5 pass
    pred_ro5 = _norm_ro5(predicted.get("ro5_pass"))
    ref_ro5  = reference.get("ro5_pass")
    if pred_ro5 is not None:
        present_count += 1
        scores["ro5_accuracy"] = 1.0 if pred_ro5 == ref_ro5 else 0.0
    else:
        scores["ro5_accuracy"] = 0.0

    scores["overall_accuracy"] = sum([
        scores["herg_accuracy"],
        scores["dili_accuracy"],
        scores["ames_accuracy"],
        scores["ro5_accuracy"],
    ]) / 4.0
    scores["completeness"] = present_count / 4.0
    scores["herg_ic50_uM"] = predicted.get("herg_ic50_uM")

    return scores


def score_admet_batch(
    all_predicted: Dict[str, Dict[str, Any]],
    cases: list,
) -> Dict[str, Any]:
    """
    Aggregate ADMET scores across all 20 reference compounds.

    Parameters
    ----------
    all_predicted : dict
        {smiles: {herg_class, herg_ic50_uM, dili_class, ames_class, ro5_pass}}
        as returned by parse_admet_output().
    cases : list
        List of case dicts from cases.yaml (each has 'smiles' + 'reference' keys).

    Returns
    -------
    dict
        {
          "n_total":              int,
          "n_matched":            int,   # compounds found in predictions
          "herg_accuracy":        float,
          "dili_accuracy":        float,
          "ames_accuracy":        float,
          "ro5_accuracy":         float,
          "overall_accuracy":     float,
          "mean_completeness":    float,
          "spearman_rho":         float or None,  # IC50 rank correlation
          "per_compound":         dict,  # {case_id: per-compound scores}
        }
    """
    per_compound: Dict[str, Any] = {}
    herg_accs: List[float] = []
    dili_accs: List[float] = []
    ames_accs: List[float] = []
    ro5_accs:  List[float] = []
    completeness: List[float] = []

    # For Spearman: collect (reference_rank, predicted_rank) pairs
    ref_ic50_pairs: List[tuple] = []   # (case_id, ref_ic50_or_110, pred_ic50_or_110)

    for case in cases:
        case_id = case["id"]
        smiles  = case["smiles"]
        ref     = case["reference"]

        # Try to match predicted — exact SMILES or case-insensitive
        predicted = all_predicted.get(smiles) or all_predicted.get(smiles.strip())
        if predicted is None:
            # Fallback: try partial SMILES match (canonicalisation may differ)
            for pred_smi, pred_data in all_predicted.items():
                if _smiles_similar(smiles, pred_smi):
                    predicted = pred_data
                    break

        if predicted is None:
            per_compound[case_id] = {
                "matched": False,
                "herg_accuracy": 0.0,
                "dili_accuracy": 0.0,
                "ames_accuracy": 0.0,
                "ro5_accuracy":  0.0,
                "overall_accuracy": 0.0,
                "completeness": 0.0,
            }
            continue

        case_scores = score_admet_case(predicted, ref)
        case_scores["matched"] = True
        case_scores["compound_name"] = case.get("name", case_id)
        per_compound[case_id] = case_scores

        herg_accs.append(case_scores["herg_accuracy"])
        dili_accs.append(case_scores["dili_accuracy"])
        ames_accs.append(case_scores["ames_accuracy"])
        ro5_accs.append( case_scores["ro5_accuracy"])
        completeness.append(case_scores["completeness"])

        # IC50 for Spearman: use 110 (beyond measurable range) for safe compounds
        ref_ic50 = ref.get("herg_ic50_uM")
        if ref_ic50 is None:
            ref_ic50 = 110.0  # >100 µM sentinel
        pred_ic50 = case_scores.get("herg_ic50_uM")
        if pred_ic50 is None:
            pred_ic50 = 110.0
        ref_ic50_pairs.append((case_id, ref_ic50, pred_ic50))

    n_matched = len(herg_accs)

    def _safe_mean(lst: list) -> float:
        return sum(lst) / len(lst) if lst else 0.0

    # Spearman rank correlation on hERG IC50 continuous values
    spearman_rho = None
    if len(ref_ic50_pairs) >= 4:
        try:
            spearman_rho = _spearman_rho(
                [x[1] for x in ref_ic50_pairs],
                [x[2] for x in ref_ic50_pairs],
            )
        except Exception:
            spearman_rho = None

    return {
        "n_total":           len(cases),
        "n_matched":         n_matched,
        "herg_accuracy":     _safe_mean(herg_accs),
        "dili_accuracy":     _safe_mean(dili_accs),
        "ames_accuracy":     _safe_mean(ames_accs),
        "ro5_accuracy":      _safe_mean(ro5_accs),
        "overall_accuracy":  _safe_mean(
            [_safe_mean(herg_accs), _safe_mean(dili_accs),
             _safe_mean(ames_accs), _safe_mean(ro5_accs)]
        ) if n_matched else 0.0,
        "mean_completeness": _safe_mean(completeness),
        "spearman_rho":      spearman_rho,
        "per_compound":      per_compound,
    }


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _rank(values: List[float]) -> List[float]:
    """Convert a list of values to their ranks (1-based, average ties)."""
    n = len(values)
    indexed = sorted(enumerate(values), key=lambda x: x[1])
    ranks = [0.0] * n
    i = 0
    while i < n:
        j = i
        while j < n - 1 and indexed[j + 1][1] == indexed[j][1]:
            j += 1
        avg_rank = (i + j) / 2.0 + 1.0
        for k in range(i, j + 1):
            ranks[indexed[k][0]] = avg_rank
        i = j + 1
    return ranks


def _spearman_rho(x: List[float], y: List[float]) -> float:
    """Compute Spearman rank correlation coefficient."""
    n = len(x)
    if n < 2:
        return float("nan")
    rx = _rank(x)
    ry = _rank(y)
    mx = sum(rx) / n
    my = sum(ry) / n
    num   = sum((rx[i] - mx) * (ry[i] - my) for i in range(n))
    denom = math.sqrt(
        sum((rx[i] - mx) ** 2 for i in range(n)) *
        sum((ry[i] - my) ** 2 for i in range(n))
    )
    if denom == 0:
        return 0.0
    return num / denom


def _smiles_similar(s1: str, s2: str) -> bool:
    """
    Loose SMILES similarity check — normalise whitespace/case and compare.
    Does NOT do full canonicalisation (that would require RDKit).
    """
    def _clean(s: str) -> str:
        return re.sub(r"\s+", "", s.strip())
    return _clean(s1) == _clean(s2)
