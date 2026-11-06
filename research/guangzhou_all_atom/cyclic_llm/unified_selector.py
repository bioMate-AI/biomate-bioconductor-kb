"""Unified multi-target binding SELECTOR — one model for all display targets (the scale-up).

Instead of a separate selector per target, train ONE target-conditioned LM on ALL display targets jointly
(per-record target-feature prefix a la v3.1 + enrichment-bucket token a la v2), then score each held-out
sequence per target by LLR = logP(seq | target_feats, <e_hi>) - logP(seq | target_feats, <e_lo>). Evaluate
per-target held-out-SEQUENCE AUC(is_binder) and compare to the single-target selectors. This is NOT
cross-target zero-shot (every target is in training, v3.1 showed that's a field-wide null) — it is "one
binding brain serves many targets", the deployable system shape. Reuses v3.1's model/target features.
"""
from __future__ import annotations
import argparse, gzip, csv, json, random, time
from pathlib import Path
import train_cyclic_llm_v3 as v3
from train_cyclic_llm_v3 import AA, TOKS, STOI, PAD, BOS, EOS, target_feature, TFEAT_DIM, make_model, encode

TARGETS = ["PADI4", "hPCSK9", "FIKK13", "Abeta42", "hIAPP"]
HI, LO = 2.0, 0.0


def load_all(csv_gz, targets_json):
    tproteins = json.load(open(targets_json))
    agg = {}  # (target,seq) -> [enr, binder]
    with gzip.open(csv_gz, "rt") as f:
        hdr = f.readline().rstrip("\n").split(","); ix = {c: i for i, c in enumerate(hdr)}
        for line in f:
            p = line.rstrip("\n").split(",")
            tgt = p[ix["target"]].split(" ")[0]
            if tgt not in TARGETS or tgt not in tproteins: continue
            seq = p[ix["sequence"]].strip().upper()
            if not seq or any(c not in AA for c in seq) or not (6 <= len(seq) <= 14): continue
            try: enr = float(p[ix["enrichment_log2fc"]])
            except ValueError: continue
            binder = p[ix["is_binder"]] in ("1", "True", "true")
            k = (tgt, seq); cur = agg.get(k)
            if cur is None or enr > cur[0]: agg[k] = [enr, binder or (cur[1] if cur else False)]
    tfeats = {t: target_feature(tproteins[t]["seq"]).astype("float32") for t in TARGETS if t in tproteins}
    recs = [{"target": t, "seq": s, "enr": e, "is_binder": b,
             "enr_b": ("hi" if e >= HI else "lo" if e <= LO else "mid")} for (t, s), (e, b) in agg.items()]
    return recs, tfeats


def seq_loglik(model, seq, enr_b, tfeat, dev):
    import torch, numpy as np
    ids = [STOI[f"<e_{enr_b}>"], STOI[BOS]] + [STOI[c] for c in seq] + [STOI[EOS]]
    x = torch.tensor([ids], device=dev); tf = torch.tensor(np.asarray(tfeat), device=dev)[None]
    with torch.no_grad():
        logits = model(x, tf)                       # v3 model: prefix + tokens, logits[:, :-1] predicts idx[1:]... here predicts full
        logp = torch.log_softmax(logits[0], -1)
    # v3 forward prepends a target-prefix slot -> output length t+1; token at input pos k predicted by logp[k]
    # logp rows: [pref, e_tok, BOS, r1..rn, EOS]; predict idx[i] from logp[i] (idx has no prefix). Align:
    tgt = x[0]                                      # [e_tok, BOS, r1..rn, EOS]
    # logits includes prefix row at index 0 predicting e_tok(idx0); so logp[i] predicts tgt[i]
    tok_lp = logp[torch.arange(len(tgt)), tgt]
    res_lp = tok_lp[2:2 + len(seq)]                 # residues only (after e_tok,BOS), exclude EOS
    return float(res_lp.sum()), len(seq)


def run(args):
    import torch, numpy as np
    from sklearn.metrics import roc_auc_score
    recs, tfeats = load_all(args.csv, args.targets)
    from collections import Counter
    print("loaded:", dict(Counter(r["target"] for r in recs)))
    random.Random(0).shuffle(recs)
    # per-target sequence held-out split
    test, train = [], []
    by_t = {t: [r for r in recs if r["target"] == t] for t in TARGETS}
    for t, rs in by_t.items():
        n_test = min(args.max_test, max(200, int(len(rs) * 0.2)))
        binders = [r for r in rs if r["is_binder"]]; non = [r for r in rs if not r["is_binder"]]
        te = binders[:n_test//2] + non[:n_test - len(binders[:n_test//2])]
        teset = set(id(r) for r in te)
        test += te; train += [r for r in rs if id(r) not in teset]
    his = [r for r in train if r["enr_b"] == "hi"]
    tr = train + his * (args.oversample_hi - 1)
    random.Random(1).shuffle(tr)
    dev = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
    block = args.block
    model = make_model(len(TOKS), TFEAT_DIM, d_model=args.d_model, n_layer=args.n_layer, n_head=args.n_head, block=block).to(dev)
    print(f"UNIFIED MODEL params={sum(p.numel() for p in model.parameters())/1e6:.1f}M dev={dev} n_tr={len(tr)} targets={len(tfeats)}")
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.1, betas=(0.9, 0.95)); pad = STOI[PAD]
    tf_t = {t: torch.tensor(np.asarray(v), device=dev) for t, v in tfeats.items()}
    def batch():
        picks = [tr[random.randrange(len(tr))] for _ in range(args.batch)]
        ids = [encode(r, block) for r in picks]; mx = max(len(x) for x in ids)
        X = torch.full((len(ids), mx), pad, dtype=torch.long)
        for i, s in enumerate(ids): X[i, :len(s)] = torch.tensor(s)
        TF = torch.stack([tf_t[r["target"]] for r in picks])
        return X.to(dev), TF
    model.train(); t0 = time.time()
    for step in range(1, args.max_steps + 1):
        X, TF = batch(); logits = model(X, TF)
        loss = torch.nn.functional.cross_entropy(logits[:, :-1].reshape(-1, logits.size(-1)), X.reshape(-1), ignore_index=pad)
        opt.zero_grad(); loss.backward(); torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step()
        if step % max(1, args.max_steps // 10) == 0: print(f"  step {step}/{args.max_steps} loss {loss.item():.3f} ({(time.time()-t0)/step:.3f}s/it)", flush=True)
    model.eval()
    per_target = {}
    for t in TARGETS:
        if t not in tfeats: continue
        te = [r for r in test if r["target"] == t]
        y = np.array([1 if r["is_binder"] else 0 for r in te])
        if y.sum() < 10 or y.sum() == len(y): continue
        llr = np.array([ (lambda hs, ls: hs - ls)(seq_loglik(model, r["seq"], "hi", tfeats[t], dev)[0],
                                                   seq_loglik(model, r["seq"], "lo", tfeats[t], dev)[0]) for r in te ])
        auc = float(roc_auc_score(y, llr)); base = float(y.mean())
        k = max(1, int(len(te) * 0.05)); lift5 = round(float(y[np.argsort(-llr)[:k]].mean()) / base, 2) if base > 0 else None
        per_target[t] = {"n_test": len(te), "binders": int(y.sum()), "AUC": round(auc, 3), "lift_top5pct": lift5}
    res = {"model": "unified_target_conditioned_selector", "n_train": len(tr), "targets_trained": list(tfeats),
           "per_target": per_target,
           "note": "ONE model, all targets (each target IN training; per-target held-out-SEQUENCE eval). "
                   "Compare AUC to single-target selectors (PADI4 0.97/Abeta42 0.99/hIAPP 0.68/hPCSK9 0.34). "
                   "Match/beat => one binding brain serves all targets (deployable system shape); NOT "
                   "cross-target zero-shot (that is the v3.1 field-wide null)."}
    print("UNIFIED", json.dumps(res))
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True); json.dump(res, open(args.out, "w"), indent=2)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default="../data/display/display_ngs_multitarget.csv.gz")
    ap.add_argument("--targets", default="../data/display/target_proteins.json")
    ap.add_argument("--max-steps", type=int, default=3000); ap.add_argument("--batch", type=int, default=128)
    ap.add_argument("--block", type=int, default=32); ap.add_argument("--d-model", type=int, default=256)
    ap.add_argument("--n-layer", type=int, default=6); ap.add_argument("--n-head", type=int, default=8)
    ap.add_argument("--lr", type=float, default=3e-4); ap.add_argument("--oversample-hi", type=int, default=8)
    ap.add_argument("--max-test", type=int, default=4000); ap.add_argument("--out")
    run(ap.parse_args())


if __name__ == "__main__":
    main()
