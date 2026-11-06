#!/usr/bin/env python3
"""
train_cyclic_llm_v3.py — CROSS-TARGET GENERALIZATION probe for our cyclic-peptide LLM.

Question: can a TARGET-CONDITIONED display-trained cyclic LLM steer generation toward a
HELD-OUT target it never saw binders for?

Design (honest, underpowered by construction — see docs):
  * Condition on TARGET FEATURES (deterministic vector from the target PROTEIN sequence:
    AA composition + length + hydrophobicity + net charge + aromatic frac) — NOT a bare
    target ID — so a held-out target has a well-defined conditioning vector at test time.
  * Also condition on the ENRICHMENT-TAIL bucket (<e_hi>/<e_mid>/<e_lo>), bucketed by the
    enriched tail (log2fc>=thresh), per the v2 lesson (tail, not quantiles).
  * Within-REGIME held-out splits only (same display chemistry on both sides):
       A (RaPID thioether-ncAA): train PADI4,  hold out FIKK13
       B (M13-phage disulfide):  train Abeta42, hold out hIAPP
  * The held-out target's rows are EXCLUDED from training entirely (no leakage); they are
    used only to (a) fit a held-out-target enrichment regressor and (b) supply the known
    binder reference for identity scoring.

Cross-target eval compares three conditionings, scored by the HELD-OUT-target regressor and
by similarity to the held-out target's known binder:
    (held-out feats, hi)  vs  (held-out feats, lo)  vs  (train feats, hi)
Transfer is real only if (held-out feats, hi) is more held-out-binder-like than BOTH the
low-enrichment control AND the train-target conditioning. If target features are ignored
(held-out-hi ~= train-hi), that is the NULL — expected with n=1 training target per regime,
and a valid/publishable data-wall result. We do NOT manufacture a positive.

Subcommands: build-data | train | eval  (see --help).
"""
import argparse, gzip, json, math, random, time
from pathlib import Path

AA = "ACDEFGHIKLMNPQRSTVWY"
PAD, BOS, EOS = "<pad>", "<bos>", "<eos>"
ENR_TOKS = ["<e_lo>", "<e_mid>", "<e_hi>"]
TOKS = [PAD, BOS, EOS] + ENR_TOKS + list(AA)
STOI = {t: i for i, t in enumerate(TOKS)}

# within-regime held-out splits (train_target -> held_out_target), same display chemistry
SPLITS = {
    "A_rapid_thioether": {"train": "PADI4", "heldout": "FIKK13",
                          "ref_binder": "ESCRYRQVLQL"},   # known FIKK13 RaPID binder (lit ref)
    "B_phage_disulfide": {"train": "Abeta42", "heldout": "hIAPP",
                          "ref_binder": "CHVVGVIC"},       # known hIAPP cyclic binder motif (lit ref)
}

# Kyte-Doolittle hydropathy
KD = {"A":1.8,"R":-4.5,"N":-3.5,"D":-3.5,"C":2.5,"Q":-3.5,"E":-3.5,"G":-0.4,"H":-3.2,
      "I":4.5,"L":3.8,"K":-3.9,"M":1.9,"F":2.8,"P":-1.6,"S":-0.8,"T":-0.7,"W":-0.9,"Y":-1.3,"V":4.2}

# ----------------------------------------------------------------------------- target features
def target_feature(seq):
    """Deterministic descriptor of a target PROTEIN: 20 AA-composition + loglen + hydrophobicity
    + net-charge frac + aromatic frac -> 24-d vector. Distinct & chemically meaningful per target."""
    import numpy as np
    seq = "".join(c for c in seq.upper() if c in AA)
    n = max(1, len(seq))
    comp = np.zeros(len(AA), np.float32)
    for c in seq:
        comp[AA.index(c)] += 1
    comp /= n
    hyd = float(np.mean([KD[c] for c in seq])) / 4.5
    charge = (sum(seq.count(x) for x in "KRH") - sum(seq.count(x) for x in "DE")) / n
    arom = sum(seq.count(x) for x in "FWY") / n
    loglen = math.log10(len(seq) + 1) / 4.0
    return np.concatenate([comp, [loglen, hyd, charge, arom]]).astype(np.float32)

TFEAT_DIM = len(AA) + 4

# ----------------------------------------------------------------------------- data
def _bucket(e, lo, hi):
    return "hi" if e >= hi else ("lo" if e <= lo else "mid")

def build_dataset(csv_gz, targets_json, split_key, out_jsonl,
                  hi_thresh=2.0, lo_thresh=0.0, oversample_hi=8):
    """Aggregate per (target,sequence) -> max enrichment; keep only the two targets in the split.
    Train records = train target only; heldout records = held-out target only (for eval)."""
    import numpy as np
    sp = SPLITS[split_key]
    targets = json.load(open(targets_json))
    keep = {sp["train"], sp["heldout"]}
    agg = {}  # (target,seq) -> {enr, binder}
    with gzip.open(csv_gz, "rt") as f:
        header = f.readline().rstrip("\n").split(",")
        ix = {c: i for i, c in enumerate(header)}
        for line in f:
            p = line.rstrip("\n").split(",")
            tgt = p[ix["target"]].split(" ")[0]  # "PADI4 (human ...)" -> "PADI4"
            if tgt not in keep:
                continue
            seq = p[ix["sequence"]].strip().upper()
            if not seq or any(c not in AA for c in seq) or not (6 <= len(seq) <= 14):
                continue
            try:
                enr = float(p[ix["enrichment_log2fc"]])
            except ValueError:
                continue
            binder = p[ix["is_binder"]] in ("1", "True", "true")
            k = (tgt, seq)
            cur = agg.get(k)
            if cur is None or enr > cur["enr"]:
                agg[k] = {"enr": enr, "binder": binder or (cur["binder"] if cur else False)}
    recs = {"train": [], "heldout": []}
    for (tgt, seq), v in agg.items():
        side = "train" if tgt == sp["train"] else "heldout"
        recs[side].append({"target": tgt, "seq": seq, "enr": v["enr"],
                           "enr_b": _bucket(v["enr"], lo_thresh, hi_thresh),
                           "is_binder": bool(v["binder"])})
    # oversample hi tail in the TRAIN set only
    tr = recs["train"]
    his = [r for r in tr if r["enr_b"] == "hi"]
    tr_out = tr + his * (oversample_hi - 1) if oversample_hi > 1 else tr
    tfeats = {t: target_feature(targets[t]["seq"]).tolist() for t in keep}
    Path(out_jsonl).parent.mkdir(parents=True, exist_ok=True)
    blob = {"split": split_key, "train_target": sp["train"], "heldout_target": sp["heldout"],
            "ref_binder": sp["ref_binder"], "target_feats": tfeats,
            "hi_thresh": hi_thresh, "lo_thresh": lo_thresh, "oversample_hi": oversample_hi,
            "train": tr_out, "heldout": recs["heldout"]}
    json.dump(blob, open(out_jsonl, "w"))
    meta = {"split": split_key, "train_target": sp["train"], "heldout_target": sp["heldout"],
            "n_train_unique": len(tr), "n_train_oversampled": len(tr_out),
            "n_train_hi": len(his), "n_heldout": len(recs["heldout"]),
            "n_heldout_hi": sum(r["enr_b"] == "hi" for r in recs["heldout"]),
            "n_heldout_binder": sum(r["is_binder"] for r in recs["heldout"]),
            "ref_binder": sp["ref_binder"]}
    print("DATA", json.dumps(meta))
    return meta

# ----------------------------------------------------------------------------- model
def make_model(vocab, tfeat_dim, d_model=256, n_layer=6, n_head=8, block=32, dropout=0.1):
    import torch, torch.nn as nn
    class Block(nn.Module):
        def __init__(s):
            super().__init__()
            s.ln1 = nn.LayerNorm(d_model); s.ln2 = nn.LayerNorm(d_model)
            s.attn = nn.MultiheadAttention(d_model, n_head, dropout=dropout, batch_first=True)
            s.mlp = nn.Sequential(nn.Linear(d_model, 4*d_model), nn.GELU(),
                                  nn.Linear(4*d_model, d_model), nn.Dropout(dropout))
        def forward(s, x, mask):
            a, _ = s.attn(s.ln1(x), s.ln1(x), s.ln1(x), attn_mask=mask, need_weights=False)
            x = x + a; x = x + s.mlp(s.ln2(x)); return x
    class GPT(nn.Module):
        def __init__(s):
            super().__init__()
            s.tok = nn.Embedding(vocab, d_model)
            s.pos = nn.Embedding(block + 1, d_model)        # +1 for the target prefix slot
            s.tproj = nn.Sequential(nn.Linear(tfeat_dim, d_model), nn.GELU(),
                                    nn.Linear(d_model, d_model))
            s.blocks = nn.ModuleList([Block() for _ in range(n_layer)])
            s.lnf = nn.LayerNorm(d_model); s.head = nn.Linear(d_model, vocab, bias=False)
            s.block = block
        def forward(s, idx, tfeat):
            import torch
            b, t = idx.shape
            tok = s.tok(idx)                                # (b,t,d)
            pref = s.tproj(tfeat)[:, None]                  # (b,1,d) target-conditioning prefix
            h = torch.cat([pref, tok], 1)                   # (b,t+1,d)
            T = t + 1
            h = h + s.pos(torch.arange(T, device=idx.device))[None]
            mask = torch.triu(torch.full((T, T), float("-inf"), device=idx.device), 1)
            for blk in s.blocks: h = blk(h, mask)
            return s.head(s.lnf(h))                          # (b,T,vocab); [:, :-1] predicts idx
    return GPT()

def encode(rec, block):
    toks = [f"<e_{rec['enr_b']}>", BOS] + list(rec["seq"]) + [EOS]
    return [STOI[t] for t in toks][:block]

# ----------------------------------------------------------------------------- train
def train(args):
    import torch, numpy as np
    blob = json.load(open(args.data))
    tr = blob["train"]
    tfeat = np.array(blob["target_feats"][blob["train_target"]], np.float32)  # constant: n=1 train target
    random.Random(0).shuffle(tr)
    json.dump({"train_seqs": sorted({r["seq"] for r in tr}),
               "meta": {k: blob[k] for k in ("split","train_target","heldout_target","ref_binder",
                                             "hi_thresh","lo_thresh","target_feats")}},
              open(args.out_ckpt + ".meta.json", "w"))
    dev = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
    block = args.block
    model = make_model(len(TOKS), TFEAT_DIM, d_model=args.d_model, n_layer=args.n_layer,
                       n_head=args.n_head, block=block).to(dev)
    print(f"MODEL params={sum(p.numel() for p in model.parameters())/1e6:.1f}M dev={dev} "
          f"n_tr={len(tr)} split={blob['split']} train={blob['train_target']} heldout={blob['heldout_target']}")
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.1, betas=(0.9, 0.95))
    pad = STOI[PAD]
    tf = torch.tensor(tfeat, device=dev)
    def batch():
        ids = [encode(tr[random.randrange(len(tr))], block) for _ in range(args.batch)]
        mx = max(len(x) for x in ids)
        X = torch.full((len(ids), mx), pad, dtype=torch.long)
        for i, s in enumerate(ids): X[i, :len(s)] = torch.tensor(s)
        return X.to(dev), tf[None].expand(len(ids), -1)
    model.train(); t0 = time.time()
    for step in range(1, args.max_steps + 1):
        X, TF = batch()
        logits = model(X, TF)              # (b, t+1, V); predict X from logits[:, :-1]
        loss = torch.nn.functional.cross_entropy(
            logits[:, :-1].reshape(-1, logits.size(-1)), X.reshape(-1), ignore_index=pad)
        opt.zero_grad(); loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step()
        if step % max(1, args.max_steps // 20) == 0 or step == 1:
            print(f"step {step}/{args.max_steps} loss {loss.item():.4f} ({(time.time()-t0)/step:.3f}s/it)", flush=True)
    torch.save({"model": model.state_dict(), "args": vars(args)}, args.out_ckpt)
    print("SAVED", args.out_ckpt)

# ----------------------------------------------------------------------------- sample + eval
def sample(model, tfeat_vec, enr_b, n, block, dev, temp=1.0, max_new=16):
    import torch
    itos = {i: t for t, i in STOI.items()}
    start = [STOI[f"<e_{enr_b}>"], STOI[BOS]]
    tf = torch.tensor(tfeat_vec, device=dev)[None]
    out = []
    for _ in range(n):
        ids = torch.tensor([start], device=dev)
        for _ in range(max_new):
            logits = model(ids[:, -block:], tf)[0, -1] / temp
            nxt = int(torch.multinomial(torch.softmax(logits, -1), 1))
            if nxt == STOI[EOS]: break
            ids = torch.cat([ids, torch.tensor([[nxt]], device=dev)], 1)
        out.append("".join(itos[int(i)] for i in ids[0, 2:]))
    return out

def _valid(s): return 6 <= len(s) <= 14 and all(c in AA for c in s)

def _ident_to(s, ref):
    best = 0
    for off in range(-(len(ref)-1), len(s)):
        m = sum(1 for k in range(len(ref)) if 0 <= off+k < len(s) and s[off+k] == ref[k])
        best = max(best, m)
    return best / len(ref)

def _comp_feat(s):
    import numpy as np
    v = np.zeros(len(AA) + 1, np.float32)
    for c in s:
        if c in AA: v[AA.index(c)] += 1
    v[:len(AA)] /= max(1, len(s)); v[-1] = len(s)
    return v

def eval_model(args):
    import torch, numpy as np
    from sklearn.ensemble import RandomForestRegressor
    ck = torch.load(args.ckpt, map_location="cpu", weights_only=False); a = ck["args"]
    meta = json.load(open(args.ckpt + ".meta.json"))["meta"]
    blob = json.load(open(args.data))
    train_seqs = set(json.load(open(args.ckpt + ".meta.json"))["train_seqs"])
    heldout = blob["heldout"]
    tfeats = meta["target_feats"]
    train_t, held_t = meta["train_target"], meta["heldout_target"]
    ref = meta["ref_binder"]
    dev = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
    model = make_model(len(TOKS), TFEAT_DIM, d_model=a["d_model"], n_layer=a["n_layer"],
                       n_head=a["n_head"], block=a["block"]).to(dev)
    model.load_state_dict(ck["model"]); model.eval()

    # HELD-OUT-target enrichment regressor (fit on held-out rows only — scores binder-likeness FOR the held-out target)
    ho = [r for r in heldout if _valid(r["seq"])]
    rf = None
    if len(ho) >= 50:
        Xh = np.array([_comp_feat(r["seq"]) for r in ho]); yh = np.array([r["enr"] for r in ho])
        rf = RandomForestRegressor(n_estimators=300, n_jobs=-1, random_state=0).fit(Xh, yh)
    ho_binders = [r["seq"] for r in ho if r["is_binder"]]

    N = args.n_sample
    def gen(tname, b):
        return sample(model, tfeats[tname], b, N, a["block"], dev, temp=args.temp)

    def stats(seqs):
        valid = [s for s in seqs if _valid(s)]
        vr = len(valid) / max(1, len(seqs))
        predH = float(rf.predict(np.array([_comp_feat(s) for s in valid])).mean()) if (rf is not None and valid) else None
        identref = float(np.mean([_ident_to(s, ref) for s in valid])) if valid else 0.0
        # max identity to ANY known held-out binder
        identbind = float(np.mean([max((_ident_to(s, b) for b in ho_binders), default=0.0) for s in valid])) if (valid and ho_binders) else 0.0
        novel = len(set(valid) - train_seqs) / max(1, len(set(valid)))
        uniq = len(set(valid)) / max(1, len(valid))
        return {"validity": round(vr, 3),
                "pred_heldout_enrichment": round(predH, 3) if predH is not None else None,
                "identity_to_ref_binder": round(identref, 3),
                "mean_max_identity_to_heldout_binders": round(identbind, 3),
                "novelty_frac": round(novel, 3), "unique_frac": round(uniq, 3)}

    cond = {
        "heldout_feats_hi": stats(gen(held_t, "hi")),
        "heldout_feats_lo": stats(gen(held_t, "lo")),
        "train_feats_hi":   stats(gen(train_t, "hi")),
        "train_feats_lo":   stats(gen(train_t, "lo")),
    }
    def d(a_, b_, key):
        x, y = cond[a_][key], cond[b_][key]
        return round((x or 0) - (y or 0), 3)

    # within-TRAIN enrichment conditioning sanity would need a train regressor; we use held-out
    # regressor consistently for the cross-target comparison and report identity deltas too.
    res = {
        "split": meta["split"], "train_target": train_t, "heldout_target": held_t,
        "ref_binder": ref, "n_sample": N, "n_heldout_rows": len(ho),
        "n_heldout_binders": len(ho_binders), "heldout_regressor_fitted": rf is not None,
        "conditionings": cond,
        "cross_target_deltas": {
            # does conditioning on HELD-OUT target features + hi beat the low-enrichment control?
            "hi_vs_lo_pred_heldout_enr": d("heldout_feats_hi", "heldout_feats_lo", "pred_heldout_enrichment"),
            "hi_vs_lo_ident_ref":        d("heldout_feats_hi", "heldout_feats_lo", "identity_to_ref_binder"),
            "hi_vs_lo_ident_binders":    d("heldout_feats_hi", "heldout_feats_lo", "mean_max_identity_to_heldout_binders"),
            # does HELD-OUT-target conditioning differ from TRAIN-target conditioning (the real transfer test)?
            "heldoutfeats_vs_trainfeats_pred_heldout_enr": d("heldout_feats_hi", "train_feats_hi", "pred_heldout_enrichment"),
            "heldoutfeats_vs_trainfeats_ident_ref":        d("heldout_feats_hi", "train_feats_hi", "identity_to_ref_binder"),
            "heldoutfeats_vs_trainfeats_ident_binders":    d("heldout_feats_hi", "train_feats_hi", "mean_max_identity_to_heldout_binders"),
        },
        "verdict": {},
    }
    cd = res["cross_target_deltas"]
    # enrichment conditioning fires at all (held-out regressor rises hi>lo under held-out feats)
    enr_cond_fires = cd["hi_vs_lo_pred_heldout_enr"] > 0.2
    # target features DO something (held-out feats != train feats, on held-out regressor)
    target_feats_matter = abs(cd["heldoutfeats_vs_trainfeats_pred_heldout_enr"]) > 0.2 or \
                          abs(cd["heldoutfeats_vs_trainfeats_ident_binders"]) > 0.02
    # transfer POSITIVE = held-out conditioning more held-out-binder-like than BOTH controls
    transfer_positive = (cd["hi_vs_lo_pred_heldout_enr"] > 0.2 and
                         cd["heldoutfeats_vs_trainfeats_pred_heldout_enr"] > 0.1 and
                         (cd["heldoutfeats_vs_trainfeats_ident_binders"] > 0.02 or
                          cd["heldoutfeats_vs_trainfeats_ident_ref"] > 0.02))
    res["verdict"] = {
        "validity_ok": cond["heldout_feats_hi"]["validity"] >= 0.8,
        "enrichment_conditioning_fires": bool(enr_cond_fires),
        "target_features_matter": bool(target_feats_matter),
        "cross_target_transfer": "POSITIVE" if transfer_positive else ("WEAK" if target_feats_matter else "NULL"),
        "note": ("n=1 training target per regime: target-feature gradient is degenerate; a NULL "
                 "(target features ignored -> held-out conditioning == train conditioning) is the "
                 "expected, honest, publishable data-wall result. Transfer requires >=3 training targets/regime."),
    }
    print("EVAL", json.dumps(res, indent=2))
    if args.out: json.dump(res, open(args.out, "w"), indent=2)
    return res

def main():
    ap = argparse.ArgumentParser(); sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build-data")
    b.add_argument("--csv", required=True); b.add_argument("--targets", required=True)
    b.add_argument("--split", required=True, choices=list(SPLITS)); b.add_argument("--out", required=True)
    b.add_argument("--hi-thresh", type=float, default=2.0); b.add_argument("--lo-thresh", type=float, default=0.0)
    b.add_argument("--oversample-hi", type=int, default=8)
    t = sub.add_parser("train")
    t.add_argument("--data", required=True); t.add_argument("--out-ckpt", required=True)
    t.add_argument("--max-steps", type=int, default=3000); t.add_argument("--batch", type=int, default=128)
    t.add_argument("--block", type=int, default=32); t.add_argument("--d-model", type=int, default=256)
    t.add_argument("--n-layer", type=int, default=6); t.add_argument("--n-head", type=int, default=8)
    t.add_argument("--lr", type=float, default=3e-4)
    e = sub.add_parser("eval")
    e.add_argument("--ckpt", required=True); e.add_argument("--data", required=True)
    e.add_argument("--n-sample", type=int, default=400); e.add_argument("--temp", type=float, default=1.0)
    e.add_argument("--out", required=True)
    a = ap.parse_args()
    if a.cmd == "build-data": build_dataset(a.csv, a.targets, a.split, a.out, a.hi_thresh, a.lo_thresh, a.oversample_hi)
    elif a.cmd == "train": train(a)
    elif a.cmd == "eval": eval_model(a)

if __name__ == "__main__":
    main()
