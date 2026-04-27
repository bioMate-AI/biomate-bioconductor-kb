"""
docking_scorer.py
-----------------
Parses docking workflow output and computes Spearman rank correlation
between predicted docking scores and experimental Kd values.

Docking scores follow Vina convention: more negative = better binding.
Experimental Kd/IC50 values: lower nM = tighter binding.
Spearman rho is computed between predicted rank order and experimental
rank order; a high positive rho means BioMate correctly ranks ligands
by predicted binding affinity in agreement with experimental data.
"""

from __future__ import annotations

import csv
import json
import math
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------

def parse_docking_output(output_dir: "str | Path") -> dict:
    """
    Look for docking result files in output_dir:
      - docking_results.csv  (SMILES/name, docking_score, pose_rmsd)
      - docking_scores.json
      - output.json  (BioMate standard wrapper)

    Returns: {ligand_name_or_smiles: {"docking_score": float, "pose_rmsd": Optional[float]}}
    Lower score = better binding (Vina uses kcal/mol, negative values).
    """
    out = Path(output_dir)
    if not out.exists():
        raise FileNotFoundError(f"Output directory does not exist: {out}")

    # Collect candidates with priority order
    csv_files: list[Path] = []
    json_files: list[Path] = []
    for pattern in ("docking_results.csv", "docking_scores.csv", "results.csv",
                    "docking_scores.json", "output.json", "docking_output.json"):
        csv_files.extend(p for p in out.rglob(pattern) if p.suffix.lower() == ".csv")
        json_files.extend(p for p in out.rglob(pattern) if p.suffix.lower() == ".json")

    # Deduplicate while preserving order
    seen: set[Path] = set()
    unique_csv = [p for p in csv_files if not (p in seen or seen.add(p))]
    seen = set()
    unique_json = [p for p in json_files if not (p in seen or seen.add(p))]

    if unique_csv:
        return _parse_docking_csv(unique_csv[0])
    for jf in unique_json:
        try:
            result = _parse_docking_json(jf)
            if result:
                return result
        except Exception:
            continue

    raise FileNotFoundError(
        f"No docking output file found in {out}. "
        "Expected: docking_results.csv, docking_scores.json, or output.json"
    )


def _parse_docking_csv(path: Path) -> dict:
    """Parse CSV docking output. Columns: name/smiles, docking_score, [pose_rmsd]."""
    results: dict = {}
    _NAME_COLS = {"name", "ligand", "ligand_name", "compound", "id", "smiles", "smi"}
    _SCORE_COLS = {"docking_score", "score", "vina_score", "glide_score",
                   "binding_score", "affinity", "predicted_affinity"}
    _RMSD_COLS = {"pose_rmsd", "rmsd", "rmsd_lb", "rmsd_ub"}

    def _norm(s: str) -> str:
        return s.strip().lower().replace(" ", "_").replace("-", "_")

    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        if not reader.fieldnames:
            return {}
        col_map = {_norm(c): c for c in reader.fieldnames if c}

        def _get(row: dict, aliases: set) -> Optional[str]:
            for alias in aliases:
                if alias in col_map:
                    return row.get(col_map[alias])
            return None

        for row in reader:
            name = _get(row, _NAME_COLS)
            score_raw = _get(row, _SCORE_COLS)
            rmsd_raw = _get(row, _RMSD_COLS)
            if not name or score_raw is None:
                continue
            try:
                score = float(score_raw)
            except (ValueError, TypeError):
                continue
            try:
                rmsd: Optional[float] = float(rmsd_raw) if rmsd_raw else None
            except (ValueError, TypeError):
                rmsd = None
            results[name.strip()] = {"docking_score": score, "pose_rmsd": rmsd}
    return results


def _parse_docking_json(path: Path) -> dict:
    """Parse JSON docking output — handles flat list and wrapped formats."""
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)

    results: dict = {}

    def _extract_one(entry: dict) -> Optional[tuple[str, dict]]:
        # Find identifier
        name = None
        for key in ("name", "ligand", "ligand_name", "compound", "id", "smiles", "smi"):
            if key in entry:
                name = str(entry[key])
                break
        if not name:
            return None
        # Find score
        score = None
        for key in ("docking_score", "score", "vina_score", "glide_score",
                    "binding_score", "affinity", "predicted_affinity"):
            if key in entry:
                try:
                    score = float(entry[key])
                    break
                except (ValueError, TypeError):
                    continue
        if score is None:
            return None
        rmsd = None
        for key in ("pose_rmsd", "rmsd", "rmsd_lb"):
            if key in entry:
                try:
                    rmsd = float(entry[key])
                    break
                except (ValueError, TypeError):
                    continue
        return name.strip(), {"docking_score": score, "pose_rmsd": rmsd}

    def _process_list(items: list) -> dict:
        out: dict = {}
        for item in items:
            if not isinstance(item, dict):
                continue
            r = _extract_one(item)
            if r:
                out[r[0]] = r[1]
        return out

    # BioMate wrapper: {"results": [...], ...} or {"ligands": [...]}
    if isinstance(data, dict):
        for key in ("results", "ligands", "compounds", "docking_results", "predictions"):
            if key in data and isinstance(data[key], list):
                return _process_list(data[key])
        # Flat dict keyed by ligand name
        if data and isinstance(next(iter(data.values()), None), dict):
            for name, val in data.items():
                r = _extract_one({**val, "name": name})
                if r:
                    results[r[0]] = r[1]
            return results
    elif isinstance(data, list):
        return _process_list(data)

    return results


# ---------------------------------------------------------------------------
# Spearman rank correlation
# ---------------------------------------------------------------------------

def _rank(values: list[float]) -> list[float]:
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


def spearman_rho(xs: list[float], ys: list[float]) -> float:
    """
    Spearman rank correlation. Returns float in [-1, 1].

    xs and ys must be the same length and have at least 2 elements.
    Returns NaN if fewer than 2 paired values.
    """
    n = len(xs)
    if n < 2 or len(ys) != n:
        return float("nan")
    rx = _rank(xs)
    ry = _rank(ys)
    mx = sum(rx) / n
    my = sum(ry) / n
    num = sum((rx[i] - mx) * (ry[i] - my) for i in range(n))
    denom = math.sqrt(
        sum((rx[i] - mx) ** 2 for i in range(n)) *
        sum((ry[i] - my) ** 2 for i in range(n))
    )
    if denom == 0:
        return 0.0
    return num / denom


# ---------------------------------------------------------------------------
# Per-system scoring
# ---------------------------------------------------------------------------

def score_docking_system(predicted_scores: dict, ligands: list[dict]) -> dict:
    """
    For one PDB system with multiple ligands, score BioMate's predicted ranking
    against the experimental binding affinity ranking.

    Parameters
    ----------
    predicted_scores : dict
        {ligand_name: {"docking_score": float, ...}} as returned by parse_docking_output.
        Lower score = better binding (Vina convention; kcal/mol, negative values).
    ligands : list of dict
        Each dict has keys: name, experimental_kd_nM (or experimental_ic50_nM), smiles.
        Lower Kd/IC50 nM = tighter binder.

    Returns
    -------
    dict with keys:
        spearman_rho:         float  — correlation between predicted rank and Kd rank
        top1_correct:         bool   — tightest experimental binder has best predicted score
        n_ligands:            int    — total ligands in system
        n_matched:            int    — ligands found in predicted_scores
        predicted_ranking:    list[str]  — names ordered by predicted score (best first)
        experimental_ranking: list[str]  — names ordered by Kd (tightest first)
    """
    # Build experimental ranking (ascending Kd = tighter binder first)
    def _exp_kd(lig: dict) -> float:
        return float(lig.get("experimental_kd_nM") or lig.get("experimental_ic50_nM") or 1e12)

    experimental_ranking = [lig["name"] for lig in sorted(ligands, key=_exp_kd)]

    # Match predicted scores to ligand names (try exact, then SMILES)
    matched_names: list[str] = []
    matched_pred_scores: list[float] = []
    matched_exp_kd: list[float] = []

    def _find_predicted(lig: dict) -> Optional[float]:
        """Try to find this ligand's predicted score by name or SMILES."""
        name = lig["name"]
        if name in predicted_scores:
            return predicted_scores[name]["docking_score"]
        # Case-insensitive fallback
        name_lower = name.lower()
        for k, v in predicted_scores.items():
            if k.lower() == name_lower:
                return v["docking_score"]
        # SMILES fallback
        smiles = lig.get("smiles", "")
        if smiles and smiles in predicted_scores:
            return predicted_scores[smiles]["docking_score"]
        return None

    for lig in ligands:
        pred = _find_predicted(lig)
        if pred is not None:
            matched_names.append(lig["name"])
            matched_pred_scores.append(pred)
            matched_exp_kd.append(_exp_kd(lig))

    # Predicted ranking: ascending score = better binding (most negative first)
    sorted_by_pred = sorted(
        zip(matched_names, matched_pred_scores),
        key=lambda x: x[1]
    )
    predicted_ranking = [name for name, _ in sorted_by_pred]

    # Compute Spearman rho between predicted score and Kd (both ascending = better)
    rho = float("nan")
    top1_correct = False

    if len(matched_names) >= 2:
        rho = spearman_rho(matched_pred_scores, matched_exp_kd)
        # top1_correct: does the ligand with the best (lowest) predicted score
        # match the ligand with the tightest (lowest Kd) experimental binding?
        best_pred_name = predicted_ranking[0] if predicted_ranking else None
        best_exp_name = experimental_ranking[0] if experimental_ranking else None
        top1_correct = (best_pred_name is not None and best_pred_name == best_exp_name)
    elif len(matched_names) == 1:
        # Only one ligand matched; top1 is correct iff it's the tightest binder
        top1_correct = (matched_names[0] == experimental_ranking[0])

    return {
        "spearman_rho": rho,
        "top1_correct": top1_correct,
        "n_ligands": len(ligands),
        "n_matched": len(matched_names),
        "predicted_ranking": predicted_ranking,
        "experimental_ranking": experimental_ranking,
    }


# ---------------------------------------------------------------------------
# Batch aggregation
# ---------------------------------------------------------------------------

def score_docking_batch(system_results: list[dict]) -> dict:
    """
    Aggregate docking scores over all PDB systems.

    Parameters
    ----------
    system_results : list of dict
        Each dict is the output of score_docking_system() for one system,
        plus an optional "completed" bool (defaults to True if spearman_rho is not NaN).

    Returns
    -------
    dict with keys:
        mean_spearman_rho:    float
        top1_accuracy:        float  — fraction of systems where top1_correct is True
        n_systems:            int    — total systems attempted
        n_systems_completed:  int    — systems with at least 2 matched ligands
    """
    rhos: list[float] = []
    top1_correct_count = 0
    n_completed = 0

    for r in system_results:
        rho = r.get("spearman_rho", float("nan"))
        n_matched = r.get("n_matched", 0)
        completed = n_matched >= 2 and not (isinstance(rho, float) and math.isnan(rho))
        if completed:
            n_completed += 1
            rhos.append(rho)
            if r.get("top1_correct", False):
                top1_correct_count += 1

    mean_rho = sum(rhos) / len(rhos) if rhos else float("nan")
    top1_acc = top1_correct_count / n_completed if n_completed > 0 else 0.0

    return {
        "mean_spearman_rho": mean_rho,
        "top1_accuracy": top1_acc,
        "n_systems": len(system_results),
        "n_systems_completed": n_completed,
    }
