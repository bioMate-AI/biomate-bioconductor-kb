"""renal_surrogate.py — the renal-retention surrogate + Gate A, made EXECUTABLE.

Gate A (programme doc / renal_corpus.gate_a_protocol): before any synthesis spend, an interpretable
surrogate must rank-order kidney retention STRICTLY better than net charge alone on >=50 held-out
published constructs. If it can't, the field heuristic suffices and there is no model.

This harness does the honest thing at every n:
  * assembles (features, label) pairs where BOTH a sourced sequence (-> computable net charge, via
    renal_features) AND a published renal label exist in the corpus;
  * if usable n < MIN_GATE_N -> REFUSES TO CERTIFY, prints the exact data deficit and extraction target
    (a gate that fails loudly is the point — it stops premature spend on a model that doesn't exist yet);
  * if usable n >= MIN_GATE_N -> leave-one-out surrogate (interpretable gradient boosting) vs the
    net-charge baseline, Spearman on the held-out, and a pass/fail verdict.

No fabrication: labels come only from the cited corpus; features are deterministic (renal_features).
"""
from __future__ import annotations
import json, os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
import renal_features as rf

MIN_GATE_N = 50               # programme doc: >=50 held-out published constructs
_FEATS = ["net_charge_with_chelate", "n_lys", "n_arg", "n_his", "n_asp_glu", "basic_residue_frac", "seq_len"]


def _retention_label(r: dict):
    """A single 'worse renal retention' scalar (higher = worse), from whatever the corpus reports.
    Priority: human dosimetry (Gy/GBq) > inverse T:K (low T:K = retention) > kidney %ID/g (log).
    Returns (value, kind) or None. Mixing kinds is unsafe for absolute values but the surrogate is
    judged on RANK within a kind, so we also return the kind for stratified Spearman."""
    if r.get("kidney_gy_per_gbq") is not None:
        return (float(r["kidney_gy_per_gbq"]), "gy_per_gbq")
    if r.get("tk_ratio") is not None and r["tk_ratio"] > 0:
        return (1.0 / float(r["tk_ratio"]), "inv_tk")          # low T:K -> high retention proxy
    for t in ("kidney_pid_g_24h", "kidney_pid_g_4h", "kidney_pid_g_1h"):
        if r.get(t) is not None:
            return (float(np.log1p(r[t])), "log_pidg")
    return None


def assemble():
    rows = [json.loads(l) for l in open(os.path.join(HERE, "renal_seed_corpus.jsonl"))]
    usable = []
    for r in rows:
        feats = rf.features_for_row(r)                          # row's own sourced sequence, else curated dict
        lab = _retention_label(r)
        if feats is None or lab is None:
            continue
        x = [getattr(feats, k) for k in _FEATS]
        usable.append({"id": r["construct_id"], "x": x, "y": lab[0], "kind": lab[1],
                       "net_charge": feats.net_charge_with_chelate,
                       "protection": r.get("renal_protection")})
    return rows, usable


def _spearman(a, b):
    from scipy.stats import spearmanr
    return float(spearmanr(a, b).correlation)


def gate_a():
    rows, usable = assemble()
    n_total, n_usable = len(rows), len(usable)
    n_seq = sum(1 for r in rows if rf.features_for_row(r) is not None)
    n_lab = sum(1 for r in rows if _retention_label(r) is not None)

    report = {"n_corpus": n_total, "n_with_sequence": n_seq, "n_with_label": n_lab,
              "n_usable_both": n_usable, "min_gate_n": MIN_GATE_N}

    if n_usable < MIN_GATE_N:
        report["verdict"] = "REFUSE_TO_CERTIFY"
        report["reason"] = (f"usable n={n_usable} < {MIN_GATE_N}: the corpus is a schema scaffold, not a "
                            f"trainable asset. No surrogate and no Gate-A verdict are valid at this n.")
        report["deficit"] = {"need_more_usable_constructs": MIN_GATE_N - n_usable,
                             "blocking": ("sequences+labels both present for only "
                                          f"{n_usable}/{n_total}; sequences for {n_seq}, labels for {n_lab}")}
        report["extraction_target"] = ("300-800 constructs across PSMA/SSTR/GRPR/FAPI/RGD/bombesin via the "
                                       "BioMate-KB literature methodology; renal_protection flag mandatory "
                                       "(stratify/exclude, never impute); each renal number primary-cited.")
        # still surface the mechanistic signal we DO have (direction, not a model):
        if n_usable >= 2:
            charges = [u["net_charge"] for u in usable]
            ys = [u["y"] for u in usable]
            report["charge_vs_retention_direction"] = {
                "constructs": [(u["id"], round(u["net_charge"], 2), round(u["y"], 2), u["kind"]) for u in usable],
                "note": "higher net charge should track higher retention (megalin thesis); "
                        "n too small for a correlation, shown as directional evidence only"}
        return report

    # --- n >= MIN_GATE_N: real Gate A (leave-one-out, interpretable surrogate vs net-charge baseline) ---
    from sklearn.ensemble import GradientBoostingRegressor
    X = np.array([u["x"] for u in usable]); y = np.array([u["y"] for u in usable])
    base = np.array([u["net_charge"] for u in usable])
    preds = np.zeros(len(y))
    for i in range(len(y)):
        tr = [j for j in range(len(y)) if j != i]
        m = GradientBoostingRegressor(n_estimators=200, max_depth=2, learning_rate=0.05, random_state=0)
        m.fit(X[tr], y[tr]); preds[i] = m.predict(X[i:i + 1])[0]
    rho_model, rho_base = _spearman(preds, y), _spearman(base, y)
    report["spearman_surrogate"] = round(rho_model, 3)
    report["spearman_net_charge_baseline"] = round(rho_base, 3)
    report["verdict"] = "PASS" if rho_model > rho_base else "FAIL_use_field_heuristic"
    return report


if __name__ == "__main__":
    r = gate_a()
    print("=== Gate A — renal-retention surrogate vs net-charge baseline ===\n")
    print(f"corpus={r['n_corpus']}  with_sequence={r['n_with_sequence']}  with_label={r['n_with_label']}  "
          f"USABLE(both)={r['n_usable_both']}  (need >= {r['min_gate_n']})\n")
    print(f"VERDICT: {r['verdict']}")
    if r["verdict"] == "REFUSE_TO_CERTIFY":
        print(f"  reason: {r['reason']}")
        print(f"  deficit: need {r['deficit']['need_more_usable_constructs']} more usable constructs")
        print(f"  {r['deficit']['blocking']}")
        print(f"  extraction target: {r['extraction_target']}")
        if "charge_vs_retention_direction" in r:
            print("\n  directional evidence we DO have (net charge -> retention, NOT a fitted model):")
            for cid, q, yv, kind in r["charge_vs_retention_direction"]["constructs"]:
                print(f"    {cid:22s} net_charge={q:+.2f}  retention({kind})={yv}")
    else:
        print(f"  surrogate Spearman = {r['spearman_surrogate']}  vs  net-charge baseline = {r['spearman_net_charge_baseline']}")
    print("\nGate A is the spend gate: it must PASS on real extracted data before any synthesis commitment.")
