"""HELM/monomer cyclic-peptide LM — the ncAA-native representation upgrade (toward the best cyclic LLM).

v2/v3/selector tokenize over the 20 canonical AAs (chars) — they cannot represent the N-methyl / D-amino /
ncAA / modified monomers that real macrocyclic drugs are made of. This LM tokenizes over a MONOMER
vocabulary built from CycPeptMPDB's monomer sequences (meL, dP, Sar, Nle, Ser(tBu), Me_Bmt(E), ...), so it
generates arbitrary-chemistry cyclic peptides natively. Property-conditioned on permeability (CycPeptMPDB's
measured logPapp), head-to-tail cyclic by construction (CycPeptMPDB macrocycles).

Eval (honest): validity (valid monomer tokens), novelty vs train, ncAA FRACTION of generated monomers
(proves it's not collapsing to canonical AAs), and the permeability-conditioning effect (hi vs lo, scored
by a held-out composition regressor on the measured logPapp). Single-file, local MPS.
"""
from __future__ import annotations
import argparse, ast, csv, json, math, random, time
from pathlib import Path

CANON = set("ACDEFGHIKLMNPQRSTVWY")
PAD, BOS, EOS = "<pad>", "<bos>", "<eos>"
PBUCK = ["<p_lo>", "<p_hi>"]


def parse_monomers(s):
    s = (s or "").strip()
    if not s: return None
    try:
        lst = ast.literal_eval(s) if s.startswith("[") else s.split(".")
    except Exception:
        return None
    lst = [str(m).strip() for m in lst if str(m).strip()]
    return lst or None


def load(csv_path, perm_col="Permeability", max_len=20):
    rows = []
    with open(csv_path) as f:
        r = csv.DictReader(f)
        for row in r:
            monos = parse_monomers(row.get("Sequence", ""))
            if not monos or not (3 <= len(monos) <= max_len):
                continue
            try:
                perm = float(row.get(perm_col, ""))
            except (ValueError, TypeError):
                perm = None
            rows.append({"monomers": monos, "perm": perm})
    return rows


def build_vocab(rows):
    vocab = set()
    for r in rows:
        vocab.update(r["monomers"])
    toks = [PAD, BOS, EOS] + PBUCK + sorted(vocab)
    return toks, {t: i for i, t in enumerate(toks)}


def make_model(vocab, d_model=256, n_layer=6, n_head=8, block=48, dropout=0.1):
    import torch, torch.nn as nn
    class Block(nn.Module):
        def __init__(s):
            super().__init__()
            s.ln1 = nn.LayerNorm(d_model); s.ln2 = nn.LayerNorm(d_model)
            s.attn = nn.MultiheadAttention(d_model, n_head, dropout=dropout, batch_first=True)
            s.mlp = nn.Sequential(nn.Linear(d_model, 4*d_model), nn.GELU(), nn.Linear(4*d_model, d_model), nn.Dropout(dropout))
        def forward(s, x, m):
            a, _ = s.attn(s.ln1(x), s.ln1(x), s.ln1(x), attn_mask=m, need_weights=False)
            x = x + a; return x + s.mlp(s.ln2(x))
    class GPT(nn.Module):
        def __init__(s):
            super().__init__()
            s.tok = nn.Embedding(vocab, d_model); s.pos = nn.Embedding(block, d_model)
            s.blocks = nn.ModuleList([Block() for _ in range(n_layer)])
            s.lnf = nn.LayerNorm(d_model); s.head = nn.Linear(d_model, vocab, bias=False); s.block = block
        def forward(s, idx):
            import torch
            b, t = idx.shape
            h = s.tok(idx) + s.pos(torch.arange(t, device=idx.device))[None]
            m = torch.triu(torch.full((t, t), float("-inf"), device=idx.device), 1)
            for blk in s.blocks: h = blk(h, m)
            return s.head(s.lnf(h))
    return GPT()


def encode(rec, stoi, pbucket, block):
    toks = [pbucket, BOS] + rec["monomers"] + [EOS]
    return [stoi[t] for t in toks if t in stoi][:block]


def ncaa_frac(monos):
    return sum(1 for m in monos if m not in CANON) / max(1, len(monos))


def train(args):
    import torch, numpy as np
    from sklearn.ensemble import RandomForestRegressor
    rows = load(args.csv, max_len=args.max_len)
    perm_rows = [r for r in rows if r["perm"] is not None]
    print(f"CycPeptMPDB: {len(rows)} macrocycles, {len(perm_rows)} with measured permeability")
    toks, stoi = build_vocab(rows)
    ncaa_vocab = [t for t in toks if t not in CANON and t not in (PAD, BOS, EOS, *PBUCK)]
    print(f"MONOMER vocab: {len(toks)} tokens ({len(ncaa_vocab)} ncAA/modified) — vs 20 canonical AAs in v2")
    # permeability buckets on the measured subset (median split)
    perms = np.array([r["perm"] for r in perm_rows]); med = float(np.median(perms))
    for r in perm_rows: r["pb"] = "<p_hi>" if r["perm"] >= med else "<p_lo>"
    random.Random(0).shuffle(perm_rows)
    n_val = max(200, int(len(perm_rows) * 0.15)); val, tr = perm_rows[:n_val], perm_rows[n_val:]
    # held-out permeability regressor on monomer-composition features (for conditioning eval)
    vocab_list = sorted({m for r in perm_rows for m in r["monomers"]})
    vidx = {m: i for i, m in enumerate(vocab_list)}
    def comp(monos):
        v = np.zeros(len(vocab_list) + 2, np.float32)
        for m in monos:
            if m in vidx: v[vidx[m]] += 1
        v[:len(vocab_list)] /= max(1, len(monos)); v[-2] = len(monos); v[-1] = ncaa_frac(monos)
        return v
    rf = RandomForestRegressor(n_estimators=300, n_jobs=-1, random_state=0).fit(
        np.array([comp(r["monomers"]) for r in val]), np.array([r["perm"] for r in val]))

    dev = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
    model = make_model(len(toks), d_model=args.d_model, n_layer=args.n_layer, n_head=args.n_head, block=args.block).to(dev)
    print(f"MODEL params={sum(p.numel() for p in model.parameters())/1e6:.1f}M dev={dev} n_tr={len(tr)}")
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.1, betas=(0.9, 0.95)); pad = stoi[PAD]
    def batch():
        ids = [encode(r, stoi, r["pb"], args.block) for r in (tr[random.randrange(len(tr))] for _ in range(args.batch))]
        mx = max(len(x) for x in ids); X = torch.full((len(ids), mx), pad, dtype=torch.long)
        for i, s in enumerate(ids): X[i, :len(s)] = torch.tensor(s)
        return X.to(dev)
    model.train(); t0 = time.time()
    for step in range(1, args.max_steps + 1):
        X = batch(); logits = model(X[:, :-1])
        loss = torch.nn.functional.cross_entropy(logits.reshape(-1, logits.size(-1)), X[:, 1:].reshape(-1), ignore_index=pad)
        opt.zero_grad(); loss.backward(); torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step()
        if step % max(1, args.max_steps // 10) == 0: print(f"  step {step}/{args.max_steps} loss {loss.item():.3f} ({(time.time()-t0)/step:.3f}s/it)", flush=True)

    # eval: sample hi vs lo permeability-conditioned
    model.eval(); itos = {i: t for t, i in stoi.items()}
    train_set = {tuple(r["monomers"]) for r in tr}
    def sample(pb, n):
        out = []
        for _ in range(n):
            ids = [stoi[pb], stoi[BOS]]
            for _ in range(args.max_len + 1):
                import torch
                with torch.no_grad():
                    lg = model(torch.tensor([ids[-args.block:]], device=dev))[0, -1] / args.temp
                nx = int(torch.multinomial(torch.softmax(lg, -1), 1))
                if nx == stoi[EOS]: break
                ids.append(nx)
            out.append([itos[i] for i in ids[2:]])
        return out
    import numpy as np
    def stats(gens):
        valid = [g for g in gens if 3 <= len(g) <= args.max_len and all(t in stoi and t not in (PAD, BOS, EOS, *PBUCK) for t in g)]
        vr = len(valid) / max(1, len(gens))
        novel = len(set(tuple(g) for g in valid) - train_set) / max(1, len(set(tuple(g) for g in valid)))
        ncaa = float(np.mean([ncaa_frac(g) for g in valid])) if valid else 0.0
        pred = float(rf.predict(np.array([comp(g) for g in valid])).mean()) if valid else None
        return {"validity": round(vr, 3), "novelty": round(novel, 3), "mean_ncAA_frac": round(ncaa, 3),
                "pred_permeability": round(pred, 3) if pred is not None else None}
    hi, lo = stats(sample("<p_hi>", args.n_sample)), stats(sample("<p_lo>", args.n_sample))
    res = {"representation": "HELM/monomer (ncAA-native)", "monomer_vocab": len(toks), "ncaa_monomers": len(ncaa_vocab),
           "n_train": len(tr), "cond_hi": hi, "cond_lo": lo,
           "perm_conditioning_delta": round((hi["pred_permeability"] or 0) - (lo["pred_permeability"] or 0), 3),
           "note": "Monomer-vocabulary LM over CycPeptMPDB — generates N-methyl/D-AA/ncAA macrocycles NATIVELY "
                   "(mean_ncAA_frac shows it's not collapsing to canonical AAs). perm_conditioning_delta>0 => "
                   "high-permeability conditioning yields more permeable (less-negative logPapp) designs. The "
                   "representation upgrade v2's 20-AA char LM could not express."}
    print("HELM_EVAL", json.dumps(res))
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True); json.dump(res, open(args.out, "w"), indent=2)
    if args.ckpt:
        torch.save({"model": model.state_dict(), "toks": toks, "args": vars(args)}, args.ckpt)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default="data/raw/CycPeptMPDB_Peptide_All.csv")
    ap.add_argument("--max-len", type=int, default=20); ap.add_argument("--max-steps", type=int, default=3000)
    ap.add_argument("--batch", type=int, default=128); ap.add_argument("--block", type=int, default=48)
    ap.add_argument("--d-model", type=int, default=256); ap.add_argument("--n-layer", type=int, default=6)
    ap.add_argument("--n-head", type=int, default=8); ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--n-sample", type=int, default=400); ap.add_argument("--temp", type=float, default=1.0)
    ap.add_argument("--out"); ap.add_argument("--ckpt")
    train(ap.parse_args())


if __name__ == "__main__":
    main()
