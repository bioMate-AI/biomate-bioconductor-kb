"""
rbfe_scorer.py
--------------
Scores relative binding free-energy (RBFE / FEP / MM-GBSA) ΔΔG predictions against
experimental reference values, for the DrugDev-series N1 `rbfe_benchmark`.

Reference ΔΔG are experimental relative binding free energies (kcal/mol), keyed by
ligand id or perturbation-edge id (relative to the series' reference ligand). Predicted
ΔΔG come from the agent's FEP/MM-GBSA run output.

Metrics (per congeneric series, then aggregated):
  * RMSE, MUE            — kcal/mol accuracy (mature FEP engines sit near ~1 kcal/mol;
                           the benchmark grades whether the agent RAN a valid FEP and
                           produced sane ΔΔG, not a claim of beating specialized engines)
  * Kendall-τ, Spearman  — rank fidelity (does the predicted ordering match experiment?)
  * within_frac          — fraction of ligands with |Δ| <= `within_kcal` (default 1.0)
  * score                — composite reward in [0,1]: 0.5·max(0,τ) + 0.5·within_frac
                           (rank fidelity + accuracy; multi-signal, not a single gameable
                           metric — the "Beyond Affinity" lesson)

All functions are stateless and pure (stdlib only; no scipy). CPU self-test:
    python3 evaluation/scorers/rbfe_scorer.py --selftest
"""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from typing import Any, Dict, List, Optional, Union

_DDG_ALIASES = {"ddg", "ddg_kcal_mol", "ddg_kcal", "delta_delta_g", "dg", "rel_dg",
                "relative_binding_free_energy", "ddg_pred", "predicted_ddg"}
_ID_ALIASES = {"ligand", "ligand_id", "id", "edge", "edge_id", "name", "compound"}


# ── parsing ──────────────────────────────────────────────────────────────────

def _safe_float(v: Any) -> Optional[float]:
    try:
        f = float(v)
        return f if math.isfinite(f) else None
    except (TypeError, ValueError):
        return None


def parse_rbfe_output(output_dir: Union[str, Path]) -> Dict[str, Optional[float]]:
    """Parse an agent's FEP output dir into {ligand_or_edge_id: ddg_kcal}. Accepts a
    CSV (id + ddg columns, by alias) or a JSON ({id: ddg} or [{ligand, ddg}, ...])."""
    d = Path(output_dir)
    for name in ("ddg_results.csv", "rbfe_results.csv", "fep_results.csv", "results.csv"):
        p = d / name
        if p.is_file():
            return _parse_csv(p)
    for name in ("ddg_results.json", "rbfe_results.json", "fep_results.json", "results.json"):
        p = d / name
        if p.is_file():
            return _parse_json(p)
    return {}


def _parse_csv(path: Path) -> Dict[str, Optional[float]]:
    out: Dict[str, Optional[float]] = {}
    with path.open() as f:
        rows = list(csv.reader(f))
    if not rows:
        return out
    header = [h.strip().lower() for h in rows[0]]
    id_i = next((i for i, h in enumerate(header) if h in _ID_ALIASES), 0)
    ddg_i = next((i for i, h in enumerate(header) if h in _DDG_ALIASES), None)
    if ddg_i is None:
        return out
    for row in rows[1:]:
        if len(row) <= max(id_i, ddg_i):
            continue
        out[str(row[id_i]).strip()] = _safe_float(row[ddg_i])
    return out


def _parse_json(path: Path) -> Dict[str, Optional[float]]:
    data = json.loads(path.read_text())
    out: Dict[str, Optional[float]] = {}
    if isinstance(data, dict):
        for k, v in data.items():
            out[str(k)] = _safe_float(v if not isinstance(v, dict)
                                      else next((v[a] for a in _DDG_ALIASES if a in v), None))
    elif isinstance(data, list):
        for item in data:
            if not isinstance(item, dict):
                continue
            key = next((str(item[a]) for a in _ID_ALIASES if a in item), None)
            val = next((item[a] for a in _DDG_ALIASES if a in item), None)
            if key is not None:
                out[key] = _safe_float(val)
    return out


# ── rank statistics (stdlib) ─────────────────────────────────────────────────

def _rank(xs: List[float]) -> List[float]:
    order = sorted(range(len(xs)), key=lambda i: xs[i])
    ranks = [0.0] * len(xs)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and xs[order[j + 1]] == xs[order[i]]:
            j += 1
        avg = (i + j) / 2.0 + 1.0  # 1-based average rank for ties
        for k in range(i, j + 1):
            ranks[order[k]] = avg
        i = j + 1
    return ranks


def _pearson(a: List[float], b: List[float]) -> Optional[float]:
    n = len(a)
    if n < 2:
        return None
    ma, mb = sum(a) / n, sum(b) / n
    cov = sum((ai - ma) * (bi - mb) for ai, bi in zip(a, b))
    va = math.sqrt(sum((ai - ma) ** 2 for ai in a))
    vb = math.sqrt(sum((bi - mb) ** 2 for bi in b))
    if va == 0 or vb == 0:
        return None
    return cov / (va * vb)


def _spearman(a: List[float], b: List[float]) -> Optional[float]:
    return _pearson(_rank(a), _rank(b))


def _kendall_tau(a: List[float], b: List[float]) -> Optional[float]:
    n = len(a)
    if n < 2:
        return None
    conc = disc = 0
    for i in range(n):
        for j in range(i + 1, n):
            s = (a[i] - a[j]) * (b[i] - b[j])
            if s > 0:
                conc += 1
            elif s < 0:
                disc += 1
    total = n * (n - 1) / 2
    return (conc - disc) / total if total else None


# ── scoring ──────────────────────────────────────────────────────────────────

def score_rbfe_series(predicted: Dict[str, Any], reference: Dict[str, Any],
                      *, within_kcal: float = 1.0) -> Dict[str, Any]:
    """Score one congeneric series. Matches on shared ids with non-null values on both
    sides. Returns metrics + a composite `score` in [0,1]."""
    keys = [k for k in reference
            if k in predicted
            and _safe_float(predicted[k]) is not None
            and _safe_float(reference[k]) is not None]
    n = len(keys)
    if n == 0:
        return {"n": 0, "rmse": None, "mue": None, "kendall_tau": None,
                "spearman": None, "within_frac": 0.0, "score": 0.0}
    p = [float(predicted[k]) for k in keys]
    r = [float(reference[k]) for k in keys]
    diffs = [pi - ri for pi, ri in zip(p, r)]
    rmse = math.sqrt(sum(d * d for d in diffs) / n)
    mue = sum(abs(d) for d in diffs) / n
    within = sum(1 for d in diffs if abs(d) <= within_kcal) / n
    tau = _kendall_tau(p, r)
    rho = _spearman(p, r)
    score = max(0.0, min(1.0, 0.5 * max(0.0, tau if tau is not None else 0.0) + 0.5 * within))
    return {"n": n, "rmse": rmse, "mue": mue, "kendall_tau": tau,
            "spearman": rho, "within_frac": within, "score": score}


def score_rbfe_batch(series: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Aggregate per-series results (each = {'predicted':..., 'reference':...}).
    Pools all matched ligands for RMSE/MUE; averages per-series rank stats + score."""
    per = [score_rbfe_series(s["predicted"], s["reference"],
                             within_kcal=s.get("within_kcal", 1.0)) for s in series]
    scored = [x for x in per if x["n"] > 0]
    if not scored:
        return {"n_series": 0, "mean_score": 0.0, "per_series": per}

    def _mean(key):
        vals = [x[key] for x in scored if x[key] is not None]
        return sum(vals) / len(vals) if vals else None

    return {
        "n_series": len(scored),
        "n_total": sum(x["n"] for x in scored),
        "mean_rmse": _mean("rmse"),
        "mean_mue": _mean("mue"),
        "mean_kendall_tau": _mean("kendall_tau"),
        "mean_spearman": _mean("spearman"),
        "mean_within_frac": _mean("within_frac"),
        "mean_score": sum(x["score"] for x in scored) / len(scored),
        "per_series": per,
    }


# ── CPU self-test (no external data) ─────────────────────────────────────────

def _selftest() -> int:
    ref = {"L1": 0.0, "L2": -1.2, "L3": 0.8, "L4": -2.1, "L5": 1.5, "L6": -0.4}
    R = []

    def ck(name, cond):
        print(("PASS" if cond else "FAIL"), "-", name)
        R.append(cond)

    oracle = score_rbfe_series(ref, dict(ref))
    ck("oracle: rmse 0, tau 1, within 1, score 1",
       oracle["rmse"] == 0.0 and oracle["kendall_tau"] == 1.0
       and oracle["within_frac"] == 1.0 and oracle["score"] == 1.0)

    noisy = {k: v + 0.3 for k, v in ref.items()}  # small shift, still within 1 kcal, rank kept
    sn = score_rbfe_series(noisy, ref)
    ck("small noise: within 1.0, rmse small, tau 1", sn["within_frac"] == 1.0
       and sn["rmse"] < 0.5 and sn["kendall_tau"] == 1.0 and sn["score"] == 1.0)

    flipped = {k: -v for k, v in ref.items()}  # sign flip -> rank reversed, large error
    sf = score_rbfe_series(flipped, ref)
    ck("sign-flip: tau negative, within < oracle, low score",
       sf["kendall_tau"] < 0 and sf["within_frac"] < 1.0 and sf["score"] < 0.3)

    partial = {"L1": 0.0, "L2": -1.2}  # only 2 of 6 present
    sp = score_rbfe_series(partial, ref)
    ck("partial coverage scored on matched subset only", sp["n"] == 2)

    ck("no overlap -> score 0", score_rbfe_series({"X": 1.0}, ref)["n"] == 0)

    batch = score_rbfe_batch([{"predicted": dict(ref), "reference": ref},
                              {"predicted": flipped, "reference": ref}])
    ck("batch mean_score between the two series",
       0.0 < batch["mean_score"] < 1.0 and batch["n_series"] == 2)

    passed = sum(1 for c in R if c)
    print(f"\n{passed}/{len(R)} passed")
    return 0 if passed == len(R) else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true", help="CPU self-test; no external data")
    args = ap.parse_args()
    if args.selftest:
        return _selftest()
    ap.error("nothing to do; use --selftest (scoring is called as a library)")


if __name__ == "__main__":
    import sys
    sys.exit(main())
