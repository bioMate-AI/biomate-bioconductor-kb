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
    # %ID/g magnitude depends on timepoint, so the unit-kind encodes it (never pool 4h with 48h)
    for t, tag in (("kidney_pid_g_1h", "pidg_1h"), ("kidney_pid_g_4h", "pidg_4h"), ("kidney_pid_g_6h", "pidg_6h"),
                   ("kidney_pid_g_24h", "pidg_24h"), ("kidney_pid_g_48h", "pidg_48h")):
        if r.get(t) is not None:
            return (float(np.log1p(r[t])), tag)
    return None


import re as _re
_MODEL_SUFFIX = _re.compile(r"[-_](AR42J|CA20948|HT29(CCK2R)?|HT1080|HEK293|LNCaP|BxPC3|B16|A431|PC3)$", _re.I)


def _canonical(cid: str) -> str:
    """Strip tumor-model suffix so the SAME molecule measured in multiple xenograft models collapses to
    one construct (de-pseudo-replication: those are near-replicates of the same kidney biology)."""
    return _MODEL_SUFFIX.sub("", cid)


def _feature_vector(feats):
    """Modality/mechanism-aware features: BOTH signed charge AND |charge| (the charge->retention sign
    flips between cationic and anionic peptides), plus an is_peptide modality flag (peptides clear by
    filtration+megalin; small molecules by tubular transporters)."""
    q = feats.net_charge_with_chelate
    return [q, abs(q), feats.n_lys, feats.n_arg, feats.n_his, feats.n_asp_glu,
            feats.basic_residue_frac, feats.seq_len, 1 if feats.seq_len > 0 else 0]


def assemble(aggregate=False):
    rows = [json.loads(l) for l in open(os.path.join(HERE, "renal_seed_corpus.jsonl"))]
    usable = []
    for r in rows:
        feats = rf.features_for_row(r)                          # row's own sourced sequence, else curated dict
        lab = _retention_label(r)
        if feats is None or lab is None:
            continue
        usable.append({"id": r["construct_id"], "canon": _canonical(r["construct_id"]),
                       "x": _feature_vector(feats), "y": lab[0], "kind": lab[1],
                       "net_charge": feats.net_charge_with_chelate, "is_peptide": 1 if feats.seq_len > 0 else 0,
                       "species": r.get("species"), "protection": r.get("renal_protection")})
    if aggregate:                                               # collapse pseudo-replicates (same molecule x models)
        import collections, statistics
        groups = collections.defaultdict(list)
        for u in usable:
            groups[(u["canon"], u["kind"])].append(u)
        out = []
        for (_canon, _kind), g in groups.items():
            rep = dict(g[0]); rep["y"] = statistics.median(p["y"] for p in g); rep["n_rep"] = len(g)
            out.append(rep)
        usable = out
    return rows, usable


def strata(rows):
    """Diagnostic: where the labelled data actually lives, and whether a net charge is computable.
    A homogeneous surrogate stratum needs ONE unit-kind x species, with computable sequences."""
    import collections
    by = collections.Counter()
    seq_by = collections.Counter()
    for r in rows:
        lab = _retention_label(r)
        if lab is None:
            continue
        key = (lab[1], r.get("species") or "?")
        by[key] += 1
        if rf.features_for_row(r) is not None:
            seq_by[key] += 1
    return {f"{k[0]}|{k[1]}": {"n_labelled": by[k], "n_with_sequence": seq_by[k]} for k in by}


def _spearman(a, b):
    from scipy.stats import spearmanr
    return float(spearmanr(a, b).correlation)


def _target_class(cid_row):
    t = (cid_row.get("target") or "?").lower()
    for k in ("psma", "sstr", "grpr", "fap", "avb6", "avb3", "cck", "mc1r", "glp"):
        if k in t:
            return k
    return t


def cross_target_readiness(min_unit="pidg_4h"):
    """Does the asset generalize to NEW targets? Report per-target-class usable counts within the
    dense preclinical stratum. LOTO (leave-one-target-out) becomes runnable once >=2 classes each have
    enough points AND the pooled training set is large enough. This MEASURES target transfer; it does
    not assume it."""
    import collections
    rows, usable = assemble(aggregate=True)
    # restrict to one homogeneous unit (preclinical %ID/g is the dense, mechanism-relevant stratum)
    pool = [u for u in usable if u["kind"] == min_unit]
    by_class = collections.Counter()
    # need the target field -> re-join from rows by id
    tgt = {r["construct_id"]: _target_class(r) for r in rows}
    for u in pool:
        by_class[tgt.get(u["id"], "?")] += 1
    return {"unit": min_unit, "n_pool": len(pool), "classes": dict(by_class),
            "n_classes_with_data": sum(1 for v in by_class.values() if v >= 1),
            "loto_runnable": sum(1 for v in by_class.values() if v >= 3) >= 2 and len(pool) >= 12}


def loto(min_unit="pidg_4h"):
    """Leave-One-Target-Out: train on all target classes but one, predict the held-out class.
    The direct test of 'contributes to a target it never saw'. Returns per-held-out-class Spearman
    (model vs net-charge baseline) when runnable, else the readiness report explaining why not."""
    ready = cross_target_readiness(min_unit)
    if not ready["loto_runnable"]:
        return {"runnable": False, "readiness": ready,
                "note": "need >=2 target classes with >=3 points each and >=12 pooled in one unit; "
                        "run #2 (dense preclinical %ID/g across CCK2/GLP-1R/MC1R/RGD) targets this."}
    import collections
    from sklearn.ensemble import GradientBoostingRegressor
    rows, usable = assemble(aggregate=True)
    tgt = {r["construct_id"]: _target_class(r) for r in rows}
    pool = [dict(u, cls=tgt.get(u["id"], "?")) for u in usable if u["kind"] == min_unit]
    classes = [c for c, n in collections.Counter(p["cls"] for p in pool).items() if n >= 3]
    out = {}
    for held in classes:
        tr = [p for p in pool if p["cls"] != held]
        te = [p for p in pool if p["cls"] == held]
        if len(tr) < 6 or len(te) < 3:
            continue
        m = GradientBoostingRegressor(n_estimators=200, max_depth=2, learning_rate=0.05, random_state=0)
        m.fit(np.array([p["x"] for p in tr]), np.array([p["y"] for p in tr]))
        pred = m.predict(np.array([p["x"] for p in te]))
        yte = np.array([p["y"] for p in te]); base = np.array([p["net_charge"] for p in te])
        out[held] = {"n_test": len(te), "spearman_model": round(_spearman(pred, yte), 3),
                     "spearman_net_charge": round(_spearman(base, yte), 3)}
    return {"runnable": True, "unit": min_unit, "per_held_out_class": out}


def gate_a():
    rows, usable = assemble()
    n_total, n_usable = len(rows), len(usable)
    n_seq = sum(1 for r in rows if rf.features_for_row(r) is not None)
    n_lab = sum(1 for r in rows if _retention_label(r) is not None)

    strat = strata(rows)
    # a valid charge-surrogate stratum is ONE unit-kind x species with computable sequences; pick the best
    best_key = max(strat, key=lambda k: strat[k]["n_with_sequence"]) if strat else None
    best_seq = strat[best_key]["n_with_sequence"] if best_key else 0

    report = {"n_corpus": n_total, "n_with_sequence": n_seq, "n_with_label": n_lab,
              "n_usable_both": n_usable, "min_gate_n": MIN_GATE_N, "strata": strat,
              "best_stratum": best_key, "best_stratum_n_with_sequence": best_seq}

    if best_seq < MIN_GATE_N:
        report["verdict"] = "REFUSE_TO_CERTIFY"
        report["reason"] = (
            f"corpus has {n_lab} labelled constructs (dosimetry is plentiful) but only {n_seq} have a "
            f"computable sequence, and the largest homogeneous stratum ({best_key}) has just {best_seq} "
            f"sequence-bearing constructs (< {MIN_GATE_N}). A charge->retention surrogate needs ONE unit x "
            f"species stratum with >= {MIN_GATE_N} sequence-resolved peptides.")
        report["binding_constraint"] = ("SEQUENCE-RESOLVED, UNIT-HOMOGENEOUS peptide records — NOT dosimetry "
            "counts. Next extraction must: (1) attach one-letter sequences to the peptide constructs already "
            "collected; (2) add a SMILES->formal-charge path so small-molecule radioligands (PSMA/FAPI urea/"
            "quinoline) get a net charge too; (3) keep unit (Gy/GBq vs %ID/g vs T:K) + species + protection "
            "stratified, never pooled.")
        report["extraction_target"] = ("fill each existing construct's sequence/SMILES, then extend to "
                                       "300-800 cited constructs; renal_protection mandatory (never impute).")
        # still surface the mechanistic signal we DO have (direction, not a model):
        if n_usable >= 2:
            charges = [u["net_charge"] for u in usable]
            ys = [u["y"] for u in usable]
            report["charge_vs_retention_direction"] = {
                "constructs": [(u["id"], round(u["net_charge"], 2), round(u["y"], 2), u["kind"]) for u in usable],
                "note": "higher net charge should track higher retention (megalin thesis); "
                        "n too small for a correlation, shown as directional evidence only"}
        return report

    # --- best stratum has >= MIN_GATE_N: real Gate A WITHIN that homogeneous stratum (LOO surrogate vs baseline) ---
    bk_kind, bk_sp = best_key.split("|")
    strat_rows = [u for u in usable if u["kind"] == bk_kind and (u["species"] or "?") == bk_sp]
    report["gate_stratum"] = best_key; report["gate_stratum_n"] = len(strat_rows)
    from sklearn.ensemble import GradientBoostingRegressor
    X = np.array([u["x"] for u in strat_rows]); y = np.array([u["y"] for u in strat_rows])
    base = np.array([u["net_charge"] for u in strat_rows])
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
    print(f"corpus={r['n_corpus']}  with_label={r['n_with_label']} (dosimetry)  with_sequence={r['n_with_sequence']} "
          f"(computable charge)  usable_both={r['n_usable_both']}\n")
    print("  strata (unit|species -> labelled / with-sequence):")
    for k, v in sorted(r["strata"].items(), key=lambda kv: -kv[1]["n_labelled"]):
        print(f"    {k:22s}  labelled={v['n_labelled']:3d}  with_sequence={v['n_with_sequence']:3d}")
    print(f"\n  best charge-surrogate stratum: {r['best_stratum']}  (sequence-bearing={r['best_stratum_n_with_sequence']}, need >= {r['min_gate_n']})")
    # cross-target generalization (answers: does the asset contribute to NEW targets?) — ALL runnable strata
    print("\n  CROSS-TARGET (new-target) generalization — Leave-One-Target-Out, per homogeneous %ID/g stratum:")
    any_run = False
    for unit in ("pidg_1h", "pidg_4h", "pidg_6h", "pidg_24h", "pidg_48h"):
        lt = loto(min_unit=unit)
        if lt.get("runnable"):
            any_run = True
            print(f"    [{unit}]")
            for cls, v in lt["per_held_out_class"].items():
                print(f"      held-out {cls:6s} (n={v['n_test']}): model rho={v['spearman_model']:+.3f} vs net-charge {v['spearman_net_charge']:+.3f}")
    if not any_run:
        print("    none runnable yet (need >=2 target classes with >=3 charge-computable constructs in one unit)")
    print(f"\nVERDICT: {r['verdict']}")
    if r["verdict"] == "REFUSE_TO_CERTIFY":
        print(f"  reason: {r['reason']}")
        print(f"  BINDING CONSTRAINT: {r['binding_constraint']}")
        print(f"  extraction target: {r['extraction_target']}")
        if "charge_vs_retention_direction" in r:
            print("\n  directional evidence we DO have (net charge -> retention, NOT a fitted model):")
            for cid, q, yv, kind in r["charge_vs_retention_direction"]["constructs"]:
                print(f"    {cid:28s} net_charge={q:+.2f}  retention({kind})={yv}")
    else:
        print(f"  gate stratum {r['gate_stratum']} (n={r['gate_stratum_n']}): surrogate Spearman={r['spearman_surrogate']} "
              f"vs net-charge baseline={r['spearman_net_charge_baseline']}")
    print("\nGate A is the spend gate: it must PASS on real extracted data before any synthesis commitment.")
