"""v2: ENRICHMENT-conditioned cyclic-peptide sequence generator (display-NGS as the PRIMARY signal).

The innovation-thesis core test: can display-selection ENRICHMENT (not a docking/structure proxy) drive
conditional generation of binder-like cyclic peptides? Trained on the harvested PADI4 RaPID mRNA-display
dataset (~370k unique peptides x 5 rounds). Each peptide = its variable AA sequence (the macrocyclization
scaffold — ClAc initiator + Cys thioether — is constant across the library, kept as metadata). A small
GPT over the 20-AA alphabet, conditioned on a terminal-round ENRICHMENT bucket (log2fc_R6_vs_R2) via a
control token.

Honest eval (the point): generate HIGH vs LOW enrichment-conditioned, and test whether HIGH is measurably
binder-like — (a) mean predicted enrichment under a HELD-OUT regressor; (b) similarity to the validated
binder family (top binder VYSMKEWKY / consensus (V/A/M/L)YSMKEWKY); (c) enriched-kmer motif recovery;
plus validity, novelty, and a memorization check (is it just copying the top binder?). Single-target
(PADI4): a proof the display signal is LEARNABLE, not multi-target generalization.

Deps on instance: torch, numpy, pandas, scikit-learn.
"""
from __future__ import annotations
import argparse, json, math, os, random, time
from pathlib import Path

AA = "ACDEFGHIKLMNPQRSTVWY"
BOS, EOS, PAD = "<bos>", "<eos>", "<pad>"
ENR_TOKS = ["<e_lo>", "<e_mid>", "<e_hi>"]
SPECIAL = [PAD, BOS, EOS] + ENR_TOKS
TOKS = SPECIAL + list(AA)
STOI = {t: i for i, t in enumerate(TOKS)}
TOP_BINDER = "VYSMKEWKY"
CORE_MOTIF = "YSMKEWKY"  # the validated enriched core

# ----------------------------------------------------------------------------- data
def _bucket(v, q1, q2):
    return "lo" if v < q1 else ("hi" if v >= q2 else "mid")

def build_dataset(enr_csv, out_jsonl):
    import pandas as pd, numpy as np
    df = pd.read_csv(enr_csv)
    enr_col = "log2fc_R6_vs_R2" if "log2fc_R6_vs_R2" in df.columns else \
        [c for c in df.columns if c.startswith("log2fc_R6")][0]
    recs = []
    for _, r in df.iterrows():
        seq = str(r.get("sequence", "")).strip().upper()
        if not seq or any(c not in AA for c in seq):
            continue
        try:
            e = float(r.get(enr_col))
        except (TypeError, ValueError):
            continue
        if math.isnan(e):
            continue
        recs.append({"seq": seq, "enr": e, "maxc": int(r.get("max_count", 0) or 0)})
    enrs = np.array([r["enr"] for r in recs], float)
    # buckets by terminal-enrichment quantiles (hi = enriched binders, lo = de-enriched)
    q1, q2 = float(np.quantile(enrs, 0.50)), float(np.quantile(enrs, 0.90))
    for r in recs:
        r["enr_b"] = _bucket(r["enr"], q1, q2)
    Path(out_jsonl).parent.mkdir(parents=True, exist_ok=True)
    with open(out_jsonl, "w") as f:
        for r in recs:
            f.write(json.dumps(r) + "\n")
    meta = {"n": len(recs), "enr_q50": q1, "enr_q90": q2,
            "n_hi": sum(r["enr_b"] == "hi" for r in recs),
            "n_mid": sum(r["enr_b"] == "mid" for r in recs),
            "n_lo": sum(r["enr_b"] == "lo" for r in recs),
            "top_binder_in_data": any(r["seq"] == TOP_BINDER for r in recs)}
    print("DATA", json.dumps(meta))
    return meta

# ----------------------------------------------------------------------------- model (nanoGPT-style, reused)
def make_model(vocab, d_model=256, n_layer=6, n_head=8, block=32, dropout=0.1):
    import torch, torch.nn as nn
    class Block(nn.Module):
        def __init__(s):
            super().__init__()
            s.ln1 = nn.LayerNorm(d_model); s.ln2 = nn.LayerNorm(d_model)
            s.attn = nn.MultiheadAttention(d_model, n_head, dropout=dropout, batch_first=True)
            s.mlp = nn.Sequential(nn.Linear(d_model, 4*d_model), nn.GELU(), nn.Linear(4*d_model, d_model), nn.Dropout(dropout))
        def forward(s, x, mask):
            a, _ = s.attn(s.ln1(x), s.ln1(x), s.ln1(x), attn_mask=mask, need_weights=False)
            x = x + a; x = x + s.mlp(s.ln2(x)); return x
    class GPT(nn.Module):
        def __init__(s):
            super().__init__()
            s.tok = nn.Embedding(vocab, d_model); s.pos = nn.Embedding(block, d_model)
            s.blocks = nn.ModuleList([Block() for _ in range(n_layer)])
            s.lnf = nn.LayerNorm(d_model); s.head = nn.Linear(d_model, vocab, bias=False); s.block = block
        def forward(s, idx):
            import torch
            b, t = idx.shape
            x = s.tok(idx) + s.pos(torch.arange(t, device=idx.device))[None]
            mask = torch.triu(torch.full((t, t), float("-inf"), device=idx.device), 1)
            for blk in s.blocks: x = blk(x, mask)
            return s.head(s.lnf(x))
    return GPT()

def encode(rec, block):
    toks = [f"<e_{rec['enr_b']}>", BOS] + list(rec["seq"]) + [EOS]
    return [STOI[t] for t in toks][:block]

# ----------------------------------------------------------------------------- train
def train(args):
    import torch
    recs = [json.loads(l) for l in open(args.data)]
    random.Random(0).shuffle(recs)
    n_val = max(200, int(0.05 * len(recs)))
    val, tr = recs[:n_val], recs[n_val:]
    train_seqs = set(r["seq"] for r in tr)
    json.dump(sorted(train_seqs), open(args.out_ckpt + ".trainseqs.json", "w"))
    json.dump([{"seq": r["seq"], "enr": r["enr"]} for r in val], open(args.out_ckpt + ".val.json", "w"))
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    block = args.block
    model = make_model(len(TOKS), d_model=args.d_model, n_layer=args.n_layer, n_head=args.n_head, block=block).to(dev)
    print(f"MODEL params={sum(p.numel() for p in model.parameters())/1e6:.1f}M vocab={len(TOKS)} dev={dev} n_tr={len(tr)}")
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.1, betas=(0.9, 0.95))
    pad = STOI[PAD]
    def batch():
        ids = [encode(tr[random.randrange(len(tr))], block) for _ in range(args.batch)]
        mx = max(len(x) for x in ids)
        X = torch.full((len(ids), mx), pad, dtype=torch.long)
        for i, s in enumerate(ids): X[i, :len(s)] = torch.tensor(s)
        return X.to(dev)
    model.train(); t0 = time.time()
    for step in range(1, args.max_steps + 1):
        X = batch(); logits = model(X[:, :-1]); tgt = X[:, 1:]
        loss = torch.nn.functional.cross_entropy(logits.reshape(-1, logits.size(-1)), tgt.reshape(-1), ignore_index=pad)
        opt.zero_grad(); loss.backward(); torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step()
        if step % max(1, args.max_steps // 20) == 0 or step == 1:
            print(f"step {step}/{args.max_steps} loss {loss.item():.4f} ({(time.time()-t0)/step:.3f}s/it)", flush=True)
    torch.save({"model": model.state_dict(), "args": vars(args)}, args.out_ckpt)
    print("SAVED", args.out_ckpt)

# ----------------------------------------------------------------------------- sample + eval
def sample(model, enr_b, n, block, dev, temp=1.0, max_new=16):
    import torch
    itos = {i: t for t, i in STOI.items()}
    start = [STOI[f"<e_{enr_b}>"], STOI[BOS]]
    out = []
    for _ in range(n):
        ids = torch.tensor([start], device=dev)
        for _ in range(max_new):
            logits = model(ids[:, -block:])[0, -1] / temp
            nxt = int(torch.multinomial(torch.softmax(logits, -1), 1))
            if nxt == STOI[EOS]: break
            ids = torch.cat([ids, torch.tensor([[nxt]], device=dev)], 1)
        seq = "".join(itos[int(i)] for i in ids[0, 2:])
        out.append(seq)
    return out

def _valid(s):
    return len(s) >= 6 and len(s) <= 14 and all(c in AA for c in s)

def _ident_to(s, ref):
    # best ungapped overlap identity to ref (same-length windows), normalized by len(ref)
    best = 0
    for off in range(-(len(ref)-1), len(s)):
        m = sum(1 for k in range(len(ref)) if 0 <= off+k < len(s) and s[off+k] == ref[k])
        best = max(best, m)
    return best / len(ref)

def _kmers(seqs, k=3):
    from collections import Counter
    c = Counter()
    for s in seqs:
        for i in range(len(s)-k+1): c[s[i:i+k]] += 1
    return c

def eval_model(args):
    import torch, numpy as np
    from sklearn.ensemble import RandomForestRegressor
    ck = torch.load(args.ckpt, map_location="cpu", weights_only=False); a = ck["args"]
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    model = make_model(len(TOKS), d_model=a["d_model"], n_layer=a["n_layer"], n_head=a["n_head"], block=a["block"]).to(dev)
    model.load_state_dict(ck["model"]); model.eval()
    train_seqs = set(json.load(open(args.ckpt + ".trainseqs.json")))
    val = json.load(open(args.ckpt + ".val.json"))
    # HELD-OUT enrichment regressor (AA-composition + length features) trained on the VAL split only
    def feat(s):
        v = np.zeros(len(AA) + 1, np.float32)
        for c in s:
            if c in AA: v[AA.index(c)] += 1
        v[:len(AA)] /= max(1, len(s)); v[-1] = len(s)
        return v
    Xv = np.array([feat(r["seq"]) for r in val]); yv = np.array([r["enr"] for r in val])
    rf = RandomForestRegressor(n_estimators=300, n_jobs=-1, random_state=0).fit(Xv, yv) if len(val) >= 50 else None
    # enriched reference k-mers (from the known binder family)
    ref_kmers = set(_kmers([TOP_BINDER, CORE_MOTIF], 3))
    N = args.n_sample
    def gen(b): return sample(model, b, N, a["block"], dev, temp=args.temp)
    hi, lo = gen("hi"), gen("lo")
    def stats(seqs, name):
        valid = [s for s in seqs if _valid(s)]
        vr = len(valid)/len(seqs)
        pred = float(rf.predict(np.array([feat(s) for s in valid])).mean()) if (rf is not None and valid) else None
        ident = float(np.mean([_ident_to(s, TOP_BINDER) for s in valid])) if valid else 0.0
        core = sum(CORE_MOTIF in s for s in valid)/max(1, len(valid))
        km = _kmers(valid, 3)
        motif_recov = sum(km[k] for k in ref_kmers)/max(1, sum(km.values()))
        uniq = len(set(valid))/max(1, len(valid))
        topcopy = sum(s == TOP_BINDER for s in valid)/max(1, len(valid))
        novel = len(set(valid) - train_seqs)/max(1, len(set(valid)))
        return {"validity": round(vr, 3), "pred_enrichment_mean": round(pred, 3) if pred is not None else None,
                "mean_identity_to_top_binder": round(ident, 3), "frac_with_core_motif": round(core, 3),
                "enriched_kmer_recovery": round(motif_recov, 4), "unique_frac": round(uniq, 3),
                "exact_top_binder_copy_frac": round(topcopy, 3), "novelty_frac": round(novel, 3)}
    rhi, rlo = stats(hi, "hi"), stats(lo, "lo")
    res = {"n_sample": N, "high_cond": rhi, "low_cond": rlo,
           "deltas_hi_minus_lo": {
               "pred_enrichment": round((rhi["pred_enrichment_mean"] or 0) - (rlo["pred_enrichment_mean"] or 0), 3),
               "identity_to_top_binder": round(rhi["mean_identity_to_top_binder"] - rlo["mean_identity_to_top_binder"], 3),
               "core_motif_frac": round(rhi["frac_with_core_motif"] - rlo["frac_with_core_motif"], 3),
               "kmer_recovery": round(rhi["enriched_kmer_recovery"] - rlo["enriched_kmer_recovery"], 4)},
           "verdict": {}}
    d = res["deltas_hi_minus_lo"]
    res["verdict"] = {
        "validity_ok": rhi["validity"] >= 0.8,
        "enrichment_conditioning_works": d["pred_enrichment"] > 0.2,
        "binder_family_recovered": d["identity_to_top_binder"] > 0.02 or d["core_motif_frac"] > 0.01,
        "not_just_memorizing": rhi["novelty_frac"] >= 0.5 and rhi["exact_top_binder_copy_frac"] < 0.5,
    }
    print("EVAL", json.dumps(res, indent=2))
    if args.out: json.dump(res, open(args.out, "w"), indent=2)
    return res

def main():
    ap = argparse.ArgumentParser(); sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build-data"); b.add_argument("--enr", required=True); b.add_argument("--out", default="v2data.jsonl")
    t = sub.add_parser("train"); t.add_argument("--data", required=True); t.add_argument("--out-ckpt", default="cyclic_llm_v2.pt")
    t.add_argument("--max-steps", type=int, default=3000); t.add_argument("--batch", type=int, default=128)
    t.add_argument("--block", type=int, default=32); t.add_argument("--d-model", type=int, default=256)
    t.add_argument("--n-layer", type=int, default=6); t.add_argument("--n-head", type=int, default=8); t.add_argument("--lr", type=float, default=3e-4)
    e = sub.add_parser("eval"); e.add_argument("--ckpt", required=True); e.add_argument("--data", required=True)
    e.add_argument("--n-sample", type=int, default=400); e.add_argument("--temp", type=float, default=1.0); e.add_argument("--out", default="v2eval.json")
    a = ap.parse_args()
    if a.cmd == "build-data": build_dataset(a.enr, a.out)
    elif a.cmd == "train": train(a)
    elif a.cmd == "eval": eval_model(a)

if __name__ == "__main__":
    main()
