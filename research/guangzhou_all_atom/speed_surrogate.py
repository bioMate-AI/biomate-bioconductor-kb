"""Speed surrogate: predict cyclic-peptide DESIGNABILITY (self-consistency scRMSD) from the
SEQUENCE ALONE, so the expensive co-fold (~60-120 s/candidate, the DBTL throughput bottleneck)
only has to run on the fraction the surrogate ranks as promising.

Why this is honest and not gated on our 2 CRO targets:
  The training label is `filter_rmsd` — the Boltz refold self-consistency backbone RMSD of a
  generated design vs its designed pose. That label is TARGET-AGNOSTIC (it measures whether a
  sequence folds back to its own backbone, a structural property), so it can be learned from ANY
  prior generation+refold run. We already have 949 such labelled designs across 7 targets from the
  BoltzGen oversample/benchmark runs on S3 (data/processed/designability_v1.csv) — no new wet-lab
  round and no co-fold is needed to TRAIN or EVALUATE this.

Features: SEQUENCE-ONLY (length, 20 AA fractions, Kyte-Doolittle hydrophobicity, net charge,
aromatic/Gly/Pro fractions, ...). Deliberately NO post-fold columns (plddt/iptm/pae/*_refolded/
filter_rmsd) — using those would be circular (they come from the fold we are trying to skip).

Honest evaluation = LEAVE-ONE-TARGET-OUT (LOTO): train on some targets, predict designability on a
HELD-OUT target. This is the generalization that matters (does it work on a target with no prior
data), and it includes holding out 5o45 (PD-L1) and 9xmm (alpha-v-beta-6) — our own targets —
predicted purely from the OTHER targets' designs.

Operational metric = screening efficiency: rank a held-out target's candidates by predicted
designability; co-fold only the top fraction; report how much co-fold work is saved at a fixed
recall of the true designables.
"""
from __future__ import annotations

import argparse
import csv
import json
import time
from collections import Counter, defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent
DEFAULT_CSV = ROOT / "data/processed/designability_v1.csv"
DESIGNABLE_THRESH = 2.0  # scRMSD < 2 A = designable (field-standard)

# Kyte-Doolittle hydropathy
_KD = {"A": 1.8, "R": -4.5, "N": -3.5, "D": -3.5, "C": 2.5, "Q": -3.5, "E": -3.5,
       "G": -0.4, "H": -3.2, "I": 4.5, "L": 3.8, "K": -3.9, "M": 1.9, "F": 2.8,
       "P": -1.6, "S": -0.8, "T": -0.7, "W": -0.9, "Y": -1.3, "V": 4.2}
_AAS = "ACDEFGHIKLMNPQRSTVWY"
_AROMATIC = set("FWY")
_CHARGE_POS = set("KR")
_CHARGE_NEG = set("DE")

FEATURE_NAMES = (["length", "kd_hydropathy_mean", "net_charge", "frac_pos", "frac_neg",
                  "frac_aromatic", "frac_gly", "frac_pro"] + [f"frac_{a}" for a in _AAS])

# Generation-time (PRE-REFOLD) features: the generator's OWN confidence, produced during the design
# pass — available BEFORE the expensive independent refold co-fold that yields the label. Using these
# to triage which designs to co-fold is the honest speedup. (Explicitly excludes any *_refolded column
# and the label itself.)
DESIGN_FEATS = ["design_to_target_iptm", "min_design_to_target_pae", "design_ptm",
                "design_hydrophobicity", "loop", "helix", "sheet", "num_tokens"]


def featurize(seq: str) -> List[float]:
    """Sequence-only feature vector (no structure, no fold)."""
    seq = seq.upper()
    n = len(seq) or 1
    cnt = Counter(c for c in seq if c in _AAS)
    kd = sum(_KD.get(c, 0.0) for c in seq) / n
    pos = sum(1 for c in seq if c in _CHARGE_POS)
    neg = sum(1 for c in seq if c in _CHARGE_NEG)
    feats = [
        float(len(seq)),
        kd,
        float(pos - neg),
        pos / n,
        neg / n,
        sum(1 for c in seq if c in _AROMATIC) / n,
        cnt.get("G", 0) / n,
        cnt.get("P", 0) / n,
    ]
    feats += [cnt.get(a, 0) / n for a in _AAS]
    return feats


# ------------------------------------------------------------------------------- data
def load_rows(csv_path: Path) -> List[dict]:
    rows = []
    for r in csv.DictReader(open(csv_path)):
        try:
            fr = float(r["filter_rmsd"])
        except (KeyError, TypeError, ValueError):
            continue
        seq = (r.get("sequence") or "").strip()
        if not seq:
            continue
        rec = {"sequence": seq, "target": r.get("target", "?"),
               "filter_rmsd": fr, "designable": int(fr < DESIGNABLE_THRESH)}
        for c in DESIGN_FEATS:  # may be absent (seq-only dataset) -> left out
            try:
                rec[c] = float(r[c])
            except (KeyError, TypeError, ValueError):
                pass
        rows.append(rec)
    return rows


def row_features(row: dict, mode: str) -> List[float]:
    """mode: 'seq' (sequence-only), 'design' (generator confidence only), 'combined' (both)."""
    seq_f = featurize(row["sequence"])
    des_f = [row.get(c, 0.0) for c in DESIGN_FEATS]
    if mode == "seq":
        return seq_f
    if mode == "design":
        return des_f
    return seq_f + des_f


def has_design_feats(rows: List[dict]) -> bool:
    return bool(rows) and all(c in rows[0] for c in DESIGN_FEATS)


# ------------------------------------------------------------------- leave-one-target-out
def _spearman(a, b) -> float:
    import numpy as np
    a = np.asarray(a, float); b = np.asarray(b, float)
    if len(a) < 3 or np.std(a) == 0 or np.std(b) == 0:
        return float("nan")
    ra = a.argsort().argsort(); rb = b.argsort().argsort()
    return float(np.corrcoef(ra, rb)[0, 1])


def _auc(y_true, score) -> float:
    """ROC-AUC via rank statistic (no sklearn dep needed)."""
    import numpy as np
    y = np.asarray(y_true, int); s = np.asarray(score, float)
    pos = s[y == 1]; neg = s[y == 0]
    if len(pos) == 0 or len(neg) == 0:
        return float("nan")
    order = s.argsort(); ranks = np.empty_like(order, dtype=float)
    ranks[order] = np.arange(1, len(s) + 1)
    # average ties
    _, inv, counts = np.unique(s, return_inverse=True, return_counts=True)
    sums = np.zeros(len(counts)); np.add.at(sums, inv, ranks)
    ranks = (sums / counts)[inv]
    rpos = ranks[y == 1].sum()
    return float((rpos - len(pos) * (len(pos) + 1) / 2) / (len(pos) * len(neg)))


def screening_efficiency(y_true, score, recall_target=0.8) -> dict:
    """Rank by predicted designability; find the smallest top-fraction of candidates to co-fold
    that still recovers `recall_target` of the true designables. Fold-work saved = 1 - that fraction."""
    import numpy as np
    y = np.asarray(y_true, int); s = np.asarray(score, float)
    n_pos = int(y.sum())
    if n_pos == 0:
        return {"note": "no positives in held-out set"}
    order = s.argsort()[::-1]  # best-first
    cum = np.cumsum(y[order])
    need = int(np.ceil(recall_target * n_pos))
    k = int(np.argmax(cum >= need)) + 1  # candidates to co-fold
    frac_screened = k / len(y)
    return {"recall_target": recall_target, "candidates_cofolded": k, "total": len(y),
            "frac_cofolded": round(frac_screened, 3),
            "cofold_work_saved_pct": round(100 * (1 - frac_screened), 1),
            "precision_at_k": round(float(cum[k - 1]) / k, 3)}


def fit_predict(Xtr, ytr, Xte, *, classifier=True, seed=0):
    from sklearn.ensemble import HistGradientBoostingClassifier, HistGradientBoostingRegressor
    import numpy as np
    if classifier:
        if len(set(ytr)) < 2:  # degenerate fold -> fall back to base rate
            return np.full(len(Xte), float(np.mean(ytr)))
        m = HistGradientBoostingClassifier(max_iter=200, learning_rate=0.06,
                                           max_leaf_nodes=15, l2_regularization=1.0,
                                           random_state=seed)
        m.fit(Xtr, ytr)
        return m.predict_proba(Xte)[:, 1]
    m = HistGradientBoostingRegressor(max_iter=200, learning_rate=0.06, max_leaf_nodes=15,
                                      l2_regularization=1.0, random_state=seed)
    m.fit(Xtr, ytr)
    return m.predict(Xte)


# A target is "triage-relevant" only if there is actually a screening decision to make: a
# non-degenerate designable rate (enough positives AND negatives). On a target where ~everything is
# designable (rate>0.7) or ~nothing is (rate<0.05), AUC is unstable/meaningless and triage is moot —
# averaging those in hides whether the surrogate works where it matters.
TRIAGE_RATE_LO, TRIAGE_RATE_HI = 0.05, 0.70


def _triage_macro_auc(per_target: dict):
    import numpy as np
    xs = [v["auc_designable"] for v in per_target.values()
          if v["auc_designable"] == v["auc_designable"]
          and TRIAGE_RATE_LO <= v.get("designable_rate", 0) <= TRIAGE_RATE_HI]
    return round(float(np.mean(xs)), 3) if xs else None


def loto_eval(rows: List[dict], min_rows=20, mode="seq") -> dict:
    import numpy as np
    by_t = defaultdict(list)
    for r in rows:
        by_t[r["target"]].append(r)
    targets = [t for t, rs in by_t.items() if len(rs) >= min_rows]
    per_target = {}
    for held in targets:
        tr = [r for r in rows if r["target"] != held]
        te = by_t[held]
        Xtr = np.array([row_features(r, mode) for r in tr])
        ytr_c = np.array([r["designable"] for r in tr])
        ytr_r = np.array([r["filter_rmsd"] for r in tr])
        Xte = np.array([row_features(r, mode) for r in te])
        yte_c = [r["designable"] for r in te]
        yte_r = [r["filter_rmsd"] for r in te]
        proba = fit_predict(Xtr, ytr_c, Xte, classifier=True)
        reg = fit_predict(Xtr, ytr_r, Xte, classifier=False)
        per_target[held] = {
            "n_held": len(te), "designable_rate": round(float(np.mean(yte_c)), 3),
            "auc_designable": round(_auc(yte_c, proba), 3),
            "spearman_scrmsd": round(_spearman(yte_r, reg), 3),
            # ranking for screening uses the regressor (lower scRMSD = better) -> negate
            "screening@0.8recall": screening_efficiency(yte_c, -reg, 0.8),
        }
    aucs = [v["auc_designable"] for v in per_target.values() if v["auc_designable"] == v["auc_designable"]]
    saved = [v["screening@0.8recall"].get("cofold_work_saved_pct") for v in per_target.values()
             if isinstance(v["screening@0.8recall"], dict) and "cofold_work_saved_pct" in v["screening@0.8recall"]]
    return {
        "protocol": "leave-one-target-out (train on all other targets, predict held-out target)",
        "label": f"designable = filter_rmsd < {DESIGNABLE_THRESH} A (refold self-consistency)",
        "features": mode,
        "targets_evaluated": targets,
        "per_target": per_target,
        "macro_auc_designable": round(float(np.mean(aucs)), 3) if aucs else None,
        "macro_auc_triage_relevant": _triage_macro_auc(per_target),
        "mean_cofold_work_saved_pct@0.8recall": round(float(np.mean(saved)), 1) if saved else None,
        "baseline_auc": 0.5,
    }


def within_target_eval(rows: List[dict], min_rows=40, k=5, seed=0, mode="seq") -> dict:
    """Operationally-relevant test: WITHIN a single target, can the surrogate triage designs?
    (generate N for a target, co-fold a seed batch, train, triage the rest.) Per-target stratified
    k-fold; report AUC + screening efficiency. This is the use-case the surrogate is actually for;
    LOTO (cold-start a brand-new target) is the harder, separate question."""
    import numpy as np
    by_t = defaultdict(list)
    for r in rows:
        by_t[r["target"]].append(r)
    rng = np.random.default_rng(seed)
    per_target = {}
    for t, rs in by_t.items():
        y = np.array([r["designable"] for r in rs])
        if len(rs) < min_rows or len(set(y.tolist())) < 2 or min(y.sum(), (1 - y).sum()) < k:
            continue
        X = np.array([row_features(r, mode) for r in rs])
        yr = np.array([r["filter_rmsd"] for r in rs])
        idx = np.arange(len(rs)); rng.shuffle(idx)
        folds = np.array_split(idx, k)
        proba = np.full(len(rs), np.nan); reg = np.full(len(rs), np.nan)
        for f in range(k):
            te = folds[f]; tr = np.concatenate([folds[j] for j in range(k) if j != f])
            if len(set(y[tr].tolist())) < 2:
                continue
            proba[te] = fit_predict(X[tr], y[tr], X[te], classifier=True)
            reg[te] = fit_predict(X[tr], yr[tr], X[te], classifier=False)
        ok = ~np.isnan(proba)
        per_target[t] = {
            "n": int(ok.sum()), "designable_rate": round(float(y[ok].mean()), 3),
            "auc_designable": round(_auc(y[ok], proba[ok]), 3),
            "spearman_scrmsd": round(_spearman(yr[ok], reg[ok]), 3),
            "screening@0.8recall": screening_efficiency(y[ok], -reg[ok], 0.8),
        }
    aucs = [v["auc_designable"] for v in per_target.values() if v["auc_designable"] == v["auc_designable"]]
    saved = [v["screening@0.8recall"].get("cofold_work_saved_pct") for v in per_target.values()
             if isinstance(v["screening@0.8recall"], dict) and "cofold_work_saved_pct" in v["screening@0.8recall"]]
    return {
        "protocol": f"within-target stratified {k}-fold CV (triage designs for a target with seed folds)",
        "features": mode,
        "targets_evaluated": list(per_target.keys()),
        "per_target": per_target,
        "macro_auc_designable": round(float(np.mean(aucs)), 3) if aucs else None,
        "macro_auc_triage_relevant": _triage_macro_auc(per_target),
        "mean_cofold_work_saved_pct@0.8recall": round(float(np.mean(saved)), 1) if saved else None,
    }


def timing_demo(rows: List[dict], n=200) -> dict:
    import numpy as np
    seqs = [r["sequence"] for r in rows[:n]] or ["ACDEFGHIK"]
    t0 = time.perf_counter()
    for s in seqs:
        featurize(s)
    dt = time.perf_counter() - t0
    per = dt / len(seqs)
    return {"surrogate_featurize_s_per_seq": round(per, 8),
            "cofold_s_per_seq_typical": 90.0,
            "speedup_x": int(90.0 / per) if per > 0 else None,
            "note": "surrogate inference is sequence-only featurize + one GBM forward; co-fold is a Boltz prediction"}


def _selftest() -> int:
    # synthetic: designability correlated with hydrophobicity -> surrogate must beat 0.5 AUC
    import numpy as np
    rng = np.random.default_rng(0)
    rows = []
    for t in ["tA", "tB", "tC"]:
        for _ in range(60):
            L = int(rng.integers(8, 16))
            seq = "".join(rng.choice(list(_AAS), L))
            kd = sum(_KD[c] for c in seq) / L
            fr = 2.2 - 0.6 * kd + rng.normal(0, 0.4)  # hydrophobic -> lower scRMSD (healthy pos rate)
            rows.append({"sequence": seq, "target": t, "filter_rmsd": fr,
                         "designable": int(fr < 2.0)})
    res = loto_eval(rows, min_rows=20)
    # assert on the regressor ranking signal (what screening uses) — robust to class imbalance
    sp = [v["spearman_scrmsd"] for v in res["per_target"].values()]
    mean_sp = sum(sp) / len(sp)
    assert mean_sp > 0.4, (mean_sp, res)
    assert len(featurize("ACDEFG")) == len(FEATURE_NAMES)
    assert _auc([0, 0, 1, 1], [0.1, 0.2, 0.8, 0.9]) == 1.0
    print(f"speed_surrogate self-test: OK (LOTO mean Spearman={mean_sp:.2f}>0.4, featurizer, AUC)")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Sequence-only cyclic-peptide designability speed surrogate.")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--csv", type=Path, default=DEFAULT_CSV, help="labelled designs CSV")
    ap.add_argument("--min-rows", type=int, default=20, help="min designs for a target to be a LOTO fold")
    ap.add_argument("--out", type=Path, help="write the eval report JSON here")
    ap.add_argument("--predict", help="predict designability for one sequence (uses all data to fit)")
    args = ap.parse_args(argv)

    if args.selftest:
        return _selftest()
    if not args.csv.exists():
        print(f"[error] dataset not found: {args.csv}")
        return 2
    rows = load_rows(args.csv)

    if args.predict:
        import numpy as np
        mode = "seq"  # a bare sequence has no design-time features
        Xtr = np.array([row_features(r, mode) for r in rows])
        ytr = np.array([r["designable"] for r in rows])
        proba = fit_predict(Xtr, ytr, np.array([row_features({"sequence": args.predict}, mode)]), classifier=True)
        print(json.dumps({"sequence": args.predict, "p_designable": round(float(proba[0]), 3),
                          "note": "sequence-only prediction (weak signal; see report)"}, indent=2))
        return 0

    report = {"dataset": str(args.csv), "n": len(rows),
              "n_targets": len(set(r["target"] for r in rows)),
              "designable_rate": round(sum(r["designable"] for r in rows) / len(rows), 3),
              "by_target": dict(Counter(r["target"] for r in rows)),
              "has_design_features": has_design_feats(rows)}
    # Honest comparison across feature sets. 'design'/'combined' need the generation-time columns.
    modes = ["seq", "design", "combined"] if has_design_feats(rows) else ["seq"]
    report["loto"] = {m: loto_eval(rows, min_rows=args.min_rows, mode=m) for m in modes}
    report["within_target"] = {m: within_target_eval(rows, mode=m) for m in modes}
    report["timing"] = timing_demo(rows)
    print(json.dumps(report, indent=2))
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
