"""Binding SELECTOR from the display-conditioned LM (the within-target WIN, not a null).

Claim being proven: our enrichment-conditioned cyclic LM isn't just a generator trick — used as a
SELECTOR it ranks held-out binders above non-binders FOR A TARGET. For each held-out sequence we score
the conditional log-likelihood ratio

    LLR(seq) = logP(seq | <e_hi>) - logP(seq | <e_lo>)

under the trained LM. A real binder should be more likely under the high-enrichment conditioning. We
train on a sequence-disjoint TRAIN split and evaluate LLR-vs-is_binder on the HELD-OUT split:
  - AUC(is_binder ~ LLR)                       (ranking quality)
  - binder lift in the top-5%/10% by LLR       (practical selection enrichment)
This is WITHIN-target (the regime SOTA defers + where display conditioning works), honestly held out by
sequence. Reuses v2's model/vocab. Run per target with enough binders (PADI4/hPCSK9/Abeta42/hIAPP).
"""
from __future__ import annotations
import argparse, gzip, json, random, time
from pathlib import Path
import train_cyclic_llm_v2 as v2
from train_cyclic_llm_v2 import AA, TOKS, STOI, PAD, BOS, EOS, make_model, encode

HI, LO = 2.0, 0.0  # absolute log2fc thresholds (same tail-isolation as v2/v3.1)


def load_target(csv_gz, target, max_rows=None):
    """Aggregate (seq -> max enrichment, is_binder) for one display target."""
    agg = {}
    with gzip.open(csv_gz, "rt") as f:
        hdr = f.readline().rstrip("\n").split(","); ix = {c: i for i, c in enumerate(hdr)}
        for n, line in enumerate(f):
            if max_rows and n >= max_rows: break
            p = line.rstrip("\n").split(",")
            if p[ix["target"]].split(" ")[0] != target: continue
            seq = p[ix["sequence"]].strip().upper()
            if not seq or any(c not in AA for c in seq) or not (6 <= len(seq) <= 14): continue
            try: enr = float(p[ix["enrichment_log2fc"]])
            except ValueError: continue
            binder = p[ix["is_binder"]] in ("1", "True", "true")
            cur = agg.get(seq)
            if cur is None or enr > cur[0]: agg[seq] = (enr, binder or (cur[1] if cur else False))
    return [{"seq": s, "enr": e, "is_binder": b} for s, (e, b) in agg.items()]


def _bucket(e):
    return "hi" if e >= HI else ("lo" if e <= LO else "mid")


def seq_loglik(model, seq, enr_b, dev):
    """sum log P(residues+EOS | <e_enr_b>, BOS, ...) under the LM."""
    import torch
    ids = [STOI[f"<e_{enr_b}>"], STOI[BOS]] + [STOI[c] for c in seq] + [STOI[EOS]]
    x = torch.tensor([ids], device=dev)
    with torch.no_grad():
        logits = model(x[:, :-1])                       # predict ids[1:]
        logp = torch.log_softmax(logits[0], -1)
    tgt = x[0, 1:]
    # sum log-prob from the first RESIDUE onward (skip BOS prediction) through EOS
    tok_lp = logp[torch.arange(len(tgt)), tgt]
    return float(tok_lp[1:].sum())                      # positions: residues + EOS


def run(args):
    import torch, numpy as np
    from sklearn.metrics import roc_auc_score
    recs = load_target(args.csv, args.target, args.max_rows)
    random.Random(0).shuffle(recs)
    n_test = max(200, int(len(recs) * 0.2))
    test, train = recs[:n_test], recs[n_test:]
    # cap the SCORED test set (2 loglik passes each) so big targets (PADI4 ~74k) stay tractable;
    # keep all binders + sample non-binders to preserve enough positives for AUC/lift.
    if len(test) > args.max_test:
        binders = [r for r in test if r["is_binder"]]
        nonb = [r for r in test if not r["is_binder"]]
        keep_nb = max(0, args.max_test - len(binders))
        test = binders + nonb[:keep_nb]
        random.Random(1).shuffle(test)
    for r in train: r["enr_b"] = _bucket(r["enr"])
    tr = [r for r in train if r["enr_b"] in ("hi", "lo", "mid")]
    his = [r for r in tr if r["enr_b"] == "hi"]
    tr_os = tr + his * (args.oversample_hi - 1)
    n_test_bind = sum(r["is_binder"] for r in test)
    print(f"target={args.target} n_total={len(recs)} train={len(tr)} (hi={len(his)}) "
          f"test={len(test)} test_binders={n_test_bind}")
    if n_test_bind < 10:
        print(json.dumps({"target": args.target, "status": "too_few_test_binders", "n": n_test_bind}))
        return
    dev = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
    block = 32
    model = make_model(len(TOKS), d_model=args.d_model, n_layer=args.n_layer, n_head=args.n_head, block=block).to(dev)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.1, betas=(0.9, 0.95))
    pad = STOI[PAD]
    def batch():
        ids = [encode(tr_os[random.randrange(len(tr_os))], block) for _ in range(args.batch)]
        mx = max(len(x) for x in ids)
        X = torch.full((len(ids), mx), pad, dtype=torch.long)
        for i, s in enumerate(ids): X[i, :len(s)] = torch.tensor(s)
        return X.to(dev)
    model.train(); t0 = time.time()
    for step in range(1, args.max_steps + 1):
        X = batch(); logits = model(X[:, :-1])
        loss = torch.nn.functional.cross_entropy(logits.reshape(-1, logits.size(-1)), X[:, 1:].reshape(-1), ignore_index=pad)
        opt.zero_grad(); loss.backward(); torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step()
        if step % max(1, args.max_steps // 10) == 0:
            print(f"  step {step}/{args.max_steps} loss {loss.item():.3f} ({(time.time()-t0)/step:.3f}s/it)", flush=True)
    # score held-out test by LLR(hi - lo)
    model.eval()
    llr = np.array([seq_loglik(model, r["seq"], "hi", dev) - seq_loglik(model, r["seq"], "lo", dev) for r in test])
    y = np.array([1 if r["is_binder"] else 0 for r in test])
    auc = float(roc_auc_score(y, llr))
    base_rate = float(y.mean())
    def lift(frac):
        k = max(1, int(len(test) * frac)); idx = np.argsort(-llr)[:k]
        return round(float(y[idx].mean()) / base_rate, 3) if base_rate > 0 else None
    res = {"target": args.target, "n_test": len(test), "test_binders": int(y.sum()),
           "base_binder_rate": round(base_rate, 4),
           "selector_AUC_binder_vs_LLR": round(auc, 4),
           "binder_lift_top5pct": lift(0.05), "binder_lift_top10pct": lift(0.10),
           "verdict": ("WIN: display-conditioned LM ranks held-out binders (AUC>0.6, lift>1.5)"
                       if (auc > 0.6 and (lift(0.05) or 0) > 1.5) else
                       ("partial: AUC>0.55" if auc > 0.55 else "no selector signal")),
           "note": "WITHIN-target, sequence-held-out. LLR = logP(seq|hi)-logP(seq|lo) under our v2-style "
                   "display-conditioned LM used AS A SELECTOR. This is the axis SOTA defers (display-based "
                   "binding), not cross-target."}
    print("SELECT", json.dumps(res))
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True); json.dump(res, open(args.out, "w"), indent=2)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True); ap.add_argument("--target", required=True)
    ap.add_argument("--max-rows", type=int, default=None)
    ap.add_argument("--max-steps", type=int, default=2000); ap.add_argument("--batch", type=int, default=128)
    ap.add_argument("--d-model", type=int, default=256); ap.add_argument("--n-layer", type=int, default=6)
    ap.add_argument("--n-head", type=int, default=8); ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--oversample-hi", type=int, default=8); ap.add_argument("--out")
    ap.add_argument("--max-test", type=int, default=4000)
    run(ap.parse_args())


if __name__ == "__main__":
    main()
