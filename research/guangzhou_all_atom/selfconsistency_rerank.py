#!/usr/bin/env python3
"""Self-consistency re-ranker + designability for cyclic co-design (base vs cyclic-FT).

The lever: UniMoMo's realistic pick-1 (flow-likelihood selected) is DockQ ~0.22 while the oracle
best-of-N is ~0.41 — a ~0.19 gap. This re-ranks each target's candidates by SELF-CONSISTENCY
(scRMSD between the designed bound pose and an INDEPENDENT re-fold of the same sequence, via Boltz
cyclic prediction) instead of by the generator's own likelihood, and reports:
  * dockq_pick1_likelihood   — the generator's own pick (baseline, known ~0.20/0.22)
  * dockq_pick1_selfconsistency — pick the lowest-scRMSD candidate; DockQ of THAT candidate
  * dockq_oracle             — per-target max DockQ (ceiling, known ~0.40/0.41)
  * designability_frac_scRMSD_lt2 — fraction of targets whose best candidate has scRMSD < 2 Å
    (RFpeptides / Baker-lab designability metric; the SOTA-comparable number)
  * mean_scRMSD

This module is the DECOUPLED core: it consumes a per-target `candidates.jsonl` (produced on-instance
by launch_unimomo_selfconsistency.sh) so it is fully testable without a GPU. One record per target:
  {"id": "<tgt>", "candidates": [
      {"cand": 0, "dockq": 0.33, "likelihood": -12.4, "scrmsd": 1.7, "confidence": 0.81}, ... ]}
`likelihood`: generator score, HIGHER = more likely (the generator's own pick = argmax likelihood).
`scrmsd`: Å between designed pose and independent re-fold, LOWER = more self-consistent.
`confidence`: re-folder ipTM/pLDDT in [0,1], HIGHER = better (tiebreak).
"""
import argparse, json, sys

DESIGNABLE_SCRMSD = 2.0   # Å, RFpeptides-style designability threshold

def _mean(xs): return round(sum(xs) / len(xs), 4) if xs else None

def _pick(cands, key, best):
    """Return the candidate optimizing key (best=max|min); None if no candidate has that key."""
    have = [c for c in cands if c.get(key) is not None]
    if not have: return None
    return (max if best == "max" else min)(have, key=lambda c: c[key])

def summarize_one(records, designable_th=DESIGNABLE_SCRMSD):
    dq_like, dq_sc, dq_oracle, best_scrmsd = [], [], [], []
    n_sc_targets = 0
    for d in records:
        cands = d.get("candidates") or []
        if not cands: continue
        dqs = [c["dockq"] for c in cands if c.get("dockq") is not None]
        if dqs: dq_oracle.append(max(dqs))
        lk = _pick(cands, "likelihood", "max")
        if lk and lk.get("dockq") is not None: dq_like.append(lk["dockq"])
        # self-consistency pick: lowest scrmsd, tiebreak highest confidence
        sc_have = [c for c in cands if c.get("scrmsd") is not None]
        if sc_have:
            n_sc_targets += 1
            pick = min(sc_have, key=lambda c: (c["scrmsd"], -(c.get("confidence") or 0)))
            if pick.get("dockq") is not None: dq_sc.append(pick["dockq"])
            best_scrmsd.append(min(c["scrmsd"] for c in sc_have))
    desig = round(sum(1 for s in best_scrmsd if s < designable_th) / len(best_scrmsd), 4) if best_scrmsd else None
    return {
        "n_targets": len(records),
        "n_targets_with_refold": n_sc_targets,
        "dockq_oracle": _mean(dq_oracle),
        "dockq_pick1_likelihood": _mean(dq_like),
        "dockq_pick1_selfconsistency": _mean(dq_sc),
        "designability_frac_scRMSD_lt2": desig,
        "mean_scRMSD": _mean(best_scrmsd),
    }

def load(path):
    out = []
    for ln in open(path):
        ln = ln.strip()
        if ln.startswith("{"):
            try: out.append(json.loads(ln))
            except Exception: pass
    return out

def build(base_path, ft_path):
    base, ft = summarize_one(load(base_path)), summarize_one(load(ft_path))
    def delta(k):
        return None if (base[k] is None or ft[k] is None) else round(ft[k] - base[k], 4)
    return {
        "benchmark": "PepBDB-cyclic test — self-consistency re-rank + designability",
        "refolder": "Boltz cyclic prediction (independent of the UniMoMo generator)",
        "metrics": {
            "dockq_pick1_likelihood": "generator's own pick (baseline)",
            "dockq_pick1_selfconsistency": "pick lowest-scRMSD candidate — the deployable number",
            "dockq_oracle": "per-target best (ceiling)",
            "designability_frac_scRMSD_lt2": "RFpeptides-style designability (primary SOTA-comparable metric)",
        },
        "base": base, "ft": ft,
        "delta_ft_minus_base": {k: delta(k) for k in
            ("dockq_oracle", "dockq_pick1_likelihood", "dockq_pick1_selfconsistency",
             "designability_frac_scRMSD_lt2", "mean_scRMSD")},
    }

def _selftest():
    # 3 targets. For each, the lowest-scrmsd candidate should be chosen and its dockq reported.
    def tgt(i, cands): return {"id": i, "candidates": cands}
    recs = [
        # likelihood-argmax (cand0, likelihood -5) has low dockq 0.20; self-consistent cand2 (scrmsd 0.9) has dockq 0.55
        tgt("t1", [
            {"cand": 0, "dockq": 0.20, "likelihood": -5.0, "scrmsd": 3.5, "confidence": 0.4},
            {"cand": 1, "dockq": 0.40, "likelihood": -9.0, "scrmsd": 2.2, "confidence": 0.6},
            {"cand": 2, "dockq": 0.55, "likelihood": -12.0, "scrmsd": 0.9, "confidence": 0.9}]),
        tgt("t2", [
            {"cand": 0, "dockq": 0.30, "likelihood": -3.0, "scrmsd": 1.1, "confidence": 0.8},   # also best-scrmsd AND likelihood pick
            {"cand": 1, "dockq": 0.25, "likelihood": -8.0, "scrmsd": 4.0, "confidence": 0.3}]),
        tgt("t3", [
            {"cand": 0, "dockq": 0.10, "likelihood": -2.0, "scrmsd": 2.5, "confidence": 0.5},
            {"cand": 1, "dockq": 0.45, "likelihood": -6.0, "scrmsd": 2.1, "confidence": 0.5}]),  # no cand <2A -> not designable
    ]
    s = summarize_one(recs)
    import math
    checks = {
        "oracle = mean(0.55,0.30,0.45)": s["dockq_oracle"] == round((0.55+0.30+0.45)/3, 4),
        "likelihood pick-1 = mean(0.20,0.30,0.10)": s["dockq_pick1_likelihood"] == round((0.20+0.30+0.10)/3, 4),
        "self-consistency pick-1 = mean(0.55,0.30,0.45)": s["dockq_pick1_selfconsistency"] == round((0.55+0.30+0.45)/3, 4),
        "self-consistency >> likelihood": s["dockq_pick1_selfconsistency"] > s["dockq_pick1_likelihood"],
        "designability: t1(0.9) + t2(1.1) <2A, t3(2.1) not -> 2/3": s["designability_frac_scRMSD_lt2"] == round(2/3, 4),
        "mean best scrmsd = mean(0.9,1.1,2.1)": s["mean_scRMSD"] == round((0.9+1.1+2.1)/3, 4),
    }
    for k, v in checks.items(): print(f"  {'PASS' if v else 'FAIL'}  {k}")
    ok = all(checks.values()); print("ALL_CHECKS_PASS=" + str(ok)); return 0 if ok else 1

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--base"); ap.add_argument("--ft"); ap.add_argument("--out")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest: sys.exit(_selftest())
    if not (a.base and a.ft and a.out): ap.error("need --base --ft --out (or --selftest)")
    s = build(a.base, a.ft)
    open(a.out, "w").write(json.dumps(s, indent=2))
    print(json.dumps(s, indent=2))
