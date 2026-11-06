"""methodology_close_multi.py — the verified-reward generator-close as a STATISTICAL result, not n=1.

A single target (αvβ6) or a single property (permeability) is an anecdote. This runs the close over many
INSTANCES with a proper protocol and aggregates:
  - REPLICATION across seeds (different disjoint oracle A/B splits + generation seeds) -> is Δ real or a
    lucky split? sign test + Wilcoxon on Δ_independent_evaluator > 0 across runs.
  - GENERALIZATION across targets (the 5 display-binding targets) + permeability -> does the close improve
    the generator across instances, not one cherry-picked case?
  - Each run keeps the anti-circular held-out oracle (reward oracle_A vs independent evaluator oracle_B on
    DISJOINT sequence halves) and reports oracle quality (cross-split R2) so weak-reward instances are visible.
Honest expectation: improvement tracks reward-signal quality (permeability R2~0.28 strong; display enrichment
R2~0.05 near-noise) — reported, not hidden. CPU; reuses the validated leaf functions from methodology_close.
"""
from __future__ import annotations
import argparse, json, os, copy
import numpy as np
import torch
from scipy.stats import wilcoxon

import design
import methodology_close as mc
from train_cyclic_llm_v3 import TFEAT_DIM

ROOT = mc.ROOT


def run_instance(signal, target, seed, steps, pool_n, eval_n, batch, lr, beta, temp):
    """One close: fresh v4 + disjoint oracles(seed) + anti-circular eval. Returns a compact result dict."""
    torch.manual_seed(seed); np.random.seed(seed)
    if signal == "permeability":
        rows = mc.load_cycpept(); e_tok, p_tok = "<e_na>", "<p_hi>"
    else:
        rows = mc.load_display_binding(target); e_tok, p_tok = "<e_hi>", "<p_na>"
    if len(rows) < 200:
        return {"signal": signal, "target": target, "seed": seed, "skipped": f"too few rows ({len(rows)})"}
    feat, _ = mc.build_featurizer(rows)
    oa, ob, ostat = mc.train_oracles(rows, feat, seed=seed)
    train_keys = {tuple(m) for m, _ in rows}

    model, toks, stoi, a, dev = design.load(mc.CKPT); block = a["block"]
    tf = np.zeros(TFEAT_DIM, "float32") if signal == "permeability" else design.tfeat_for(target, mc.DEFAULT_TARGETS_JSON if hasattr(mc, "DEFAULT_TARGETS_JSON") else os.path.join(ROOT, "data/display/target_proteins.json"))
    tf_t = torch.tensor(np.asarray(tf), device=dev)[None]
    gate_target = target if signal == "binding" else None

    base = mc.gen(model, toks, stoi, tf, dev, block, eval_n, temp, e_tok=e_tok, p_tok=p_tok)
    mb = mc.metrics(base, ob, feat, train_keys, gate_target); baseA = mc.metrics(base, oa, feat, train_keys, gate_target)["oracle_mean"]

    pool = list({tuple(m): m for m in mc.gen(model, toks, stoi, tf, dev, block, pool_n, temp, e_tok=e_tok, p_tok=p_tok)}.values())
    scored = sorted(((oa.predict(feat(m)[None])[0], m) for m in pool), key=lambda t: -t[0])
    k = min(len(scored) // 2, 1200)
    hi, lo = scored[:k], scored[::-1][:k]
    pairs = [{"chosen": hi[i][1], "rejected": lo[i][1]} for i in range(k) if hi[i][1] != lo[i][1]]
    if len(pairs) < 10:
        return {"signal": signal, "target": target, "seed": seed, "skipped": "too few pairs"}
    mc.dpo_finetune(model, stoi, pairs, tf_t, dev, steps, beta, lr, batch, e_tok=e_tok, p_tok=p_tok, log=lambda *_: None)

    aft = mc.gen(model, toks, stoi, tf, dev, block, eval_n, temp, e_tok=e_tok, p_tok=p_tok)
    ma = mc.metrics(aft, ob, feat, train_keys, gate_target); aftA = mc.metrics(aft, oa, feat, train_keys, gate_target)["oracle_mean"]
    return {"signal": signal, "target": target, "seed": seed, "oracleA_on_B_r2": ostat["oracleA_on_B_r2"],
            "n_rows": len(rows), "n_pairs": len(pairs),
            "dB": round(ma["oracle_mean"] - mb["oracle_mean"], 4), "dA": round(aftA - baseA, 4),
            "div_before": mb["diversity"], "div_after": ma["diversity"],
            "adm_before": mb["kb_admissible"], "adm_after": ma["kb_admissible"]}


def main():
    ap = argparse.ArgumentParser(description="Statistical (multi-instance) verified-reward generator-close.")
    ap.add_argument("--seeds", type=int, default=6, help="replication seeds for the permeability instance")
    ap.add_argument("--binding-targets", default="PADI4,hPCSK9,FIKK13,Abeta42,hIAPP")
    ap.add_argument("--steps", type=int, default=120); ap.add_argument("--pool", type=int, default=800)
    ap.add_argument("--eval-n", type=int, default=250); ap.add_argument("--batch", type=int, default=8)
    ap.add_argument("--lr", type=float, default=1e-5); ap.add_argument("--beta", type=float, default=0.1)
    ap.add_argument("--temp", type=float, default=1.0)
    ap.add_argument("--out", default=os.path.join(ROOT, "results/methodology_close_multi.json"))
    args = ap.parse_args()

    runs = []
    # (1) REPLICATION: permeability across seeds (is the improvement statistically real?)
    for s in range(args.seeds):
        print(f"[perm seed {s}] running ...", flush=True)
        r = run_instance("permeability", None, s, args.steps, args.pool, args.eval_n, args.batch, args.lr, args.beta, args.temp)
        print(f"   -> {r.get('dB')} (dA {r.get('dA')}, oracleR2 {r.get('oracleA_on_B_r2')})", flush=True)
        runs.append(r)
    # (2) GENERALIZATION: across display-binding targets (seed 0 each)
    for t in [x for x in args.binding_targets.split(",") if x]:
        print(f"[binding {t}] running ...", flush=True)
        r = run_instance("binding", t, 0, args.steps, args.pool, args.eval_n, args.batch, args.lr, args.beta, args.temp)
        print(f"   -> {r.get('dB')} (dA {r.get('dA')}, oracleR2 {r.get('oracleA_on_B_r2')})", flush=True)
        runs.append(r)

    ok = [r for r in runs if "dB" in r]
    dB = np.array([r["dB"] for r in ok]); dA = np.array([r["dA"] for r in ok])

    def agg(sub, label):
        if not sub:
            return {"label": label, "n": 0}
        v = np.array([r["dB"] for r in sub])
        n_pos = int((v > 0).sum())
        try:
            p = float(wilcoxon(v).pvalue) if len(v) >= 6 else None
        except Exception:
            p = None
        return {"label": label, "n": len(v), "mean_dB": round(float(v.mean()), 4),
                "se_dB": round(float(v.std(ddof=1) / np.sqrt(len(v))), 4) if len(v) > 1 else None,
                "n_improved": n_pos, "sign_test_frac": round(n_pos / len(v), 3),
                "wilcoxon_p": (round(p, 4) if p is not None else "n<6")}

    perm = [r for r in ok if r["signal"] == "permeability"]
    bind = [r for r in ok if r["signal"] == "binding"]
    # anti-circularity across instances: Δ_B should track Δ_A (not Δ_A >> Δ_B)
    circ = round(float(np.corrcoef(dB, dA)[0, 1]), 3) if len(ok) > 2 else None
    res = {"what": "verified-reward generator-close as a STATISTICAL result (replication + generalization)",
           "protocol": "per instance: fresh v4; disjoint reward-oracle_A / independent-evaluator_B; DPO close; "
                       "Δ reported on the INDEPENDENT oracle_B (anti-circular). Permeability replicated across seeds; "
                       "generalization across display-binding targets.",
           "permeability_replication": agg(perm, "permeability x seeds"),
           "binding_generalization": agg(bind, "display-binding targets"),
           "all_instances": agg(ok, "all"),
           "anticircular_corr_dB_dA": circ,
           "per_instance": runs}
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    json.dump(res, open(args.out, "w"), indent=2)
    print("\n=== STATISTICAL SUMMARY ===")
    for key in ("permeability_replication", "binding_generalization", "all_instances"):
        a = res[key]; print(f"  {a['label']:28s} n={a.get('n')} mean_dB={a.get('mean_dB')} "
                             f"improved={a.get('n_improved')}/{a.get('n')} wilcoxon_p={a.get('wilcoxon_p')}")
    print(f"  anti-circular corr(dB,dA) = {circ}  (≈1 => real shift, not reward-hacking)")
    print(f"wrote {os.path.relpath(args.out, ROOT)}")


if __name__ == "__main__":
    main()
