"""MVP: property-conditioned cyclic-peptide SMILES generator (our own LLM).

A small GPT-style decoder over SMILES, conditioned on BUCKETED permeability + binding via control
tokens prepended to each sequence. Trained on the UNION of CycPeptMPDB (SMILES + logPapp; binding
unknown) and binding_affinity_v1 cyclic subset (SMILES + pAffinity; permeability unknown) — each
missing property gets an explicit 'unk' control token. This is the innovation-thesis MVP: joint
binding+permeability conditional generation over real data (no existing tool does this).

Self-contained: one file, driven by argv. Stages: build-data -> train -> eval. The eval is the point —
RDKit validity, macrocycle fraction, PROPERTY-CONDITIONING FIDELITY (does high-vs-low control actually
shift the generated property distribution, scored by an independent RF), and novelty.

Deps (installed on the instance): torch, rdkit, numpy, pandas, scikit-learn.
"""
from __future__ import annotations
import argparse, json, math, os, re, sys, time, random
from pathlib import Path

# ----------------------------------------------------------------------------- SMILES tokenizer
# Standard SMILES regex tokenizer (atom-aware) — keeps bracket atoms / two-char elements / ring bonds intact.
_SMI_RE = re.compile(r"(\[[^\]]+\]|Br|Cl|@@|@|%\d{2}|.)")
BOS, EOS, PAD = "<bos>", "<eos>", "<pad>"
# control vocab: permeability p{lo,mid,hi,unk}, binding b{lo,mid,hi,unk}
PERM_TOKS = ["<p_lo>", "<p_mid>", "<p_hi>", "<p_unk>"]
BIND_TOKS = ["<b_lo>", "<b_mid>", "<b_hi>", "<b_unk>"]
SPECIAL = [PAD, BOS, EOS] + PERM_TOKS + BIND_TOKS

def smi_tokens(smi: str):
    return _SMI_RE.findall(smi)

def build_vocab(smiles_list):
    chars = set()
    for s in smiles_list:
        chars.update(smi_tokens(s))
    toks = SPECIAL + sorted(chars)
    stoi = {t: i for i, t in enumerate(toks)}
    return stoi, toks

# ----------------------------------------------------------------------------- data
def _bucket(v, q1, q2):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return "unk"
    return "lo" if v < q1 else ("hi" if v >= q2 else "mid")

def build_dataset(cyc_csv, bind_csv, out_jsonl, max_len=200):
    import pandas as pd, numpy as np
    from rdkit import Chem, RDLogger
    RDLogger.DisableLog("rdApp.*")
    rows = []  # (smiles, perm, pAff)
    # CycPeptMPDB: SMILES + Permeability (logPapp)
    dc = pd.read_csv(cyc_csv)
    scol = "SMILES" if "SMILES" in dc.columns else [c for c in dc.columns if c.lower() == "smiles"][0]
    for _, r in dc.iterrows():
        smi = str(r.get(scol, "")).strip()
        try: perm = float(r.get("Permeability"))
        except (TypeError, ValueError): perm = None
        if perm is not None and not (-11 < perm < -2): perm = None  # drop detection-limit placeholders
        if smi and smi != "nan": rows.append((smi, perm, None))
    # binding_affinity_v1 cyclic subset: smiles + affinity_nM -> pAffinity
    db = pd.read_csv(bind_csv)
    db = db[db.get("cyclic_bool").astype(str).str.lower().isin(["true", "1", "1.0"])] if "cyclic_bool" in db.columns else db
    for _, r in db.iterrows():
        smi = str(r.get("smiles", "")).strip()
        try:
            nm = float(r.get("affinity_nM"))
            paff = 9.0 - math.log10(nm) if nm > 0 else None  # pAffinity = -log10(M)
        except (TypeError, ValueError): paff = None
        if smi and smi != "nan" and paff is not None: rows.append((smi, None, paff))
    # canonicalize + dedup (prefer merging properties across dup SMILES)
    merged = {}
    for smi, perm, paff in rows:
        m = Chem.MolFromSmiles(smi)
        if m is None: continue
        cs = Chem.MolToSmiles(m)
        if len(smi_tokens(cs)) > max_len: continue
        if cs not in merged: merged[cs] = [None, None]
        if perm is not None: merged[cs][0] = perm
        if paff is not None: merged[cs][1] = paff
    recs = [{"smiles": cs, "perm": pv[0], "paff": pv[1]} for cs, pv in merged.items()]
    # bucket quantile thresholds from observed values
    perms = np.array([r["perm"] for r in recs if r["perm"] is not None], float)
    paffs = np.array([r["paff"] for r in recs if r["paff"] is not None], float)
    pq = (float(np.quantile(perms, .33)), float(np.quantile(perms, .67))) if len(perms) else (0, 0)
    bq = (float(np.quantile(paffs, .33)), float(np.quantile(paffs, .67))) if len(paffs) else (0, 0)
    for r in recs:
        r["perm_b"] = _bucket(r["perm"], *pq); r["bind_b"] = _bucket(r["paff"], *bq)
    Path(out_jsonl).parent.mkdir(parents=True, exist_ok=True)
    with open(out_jsonl, "w") as f:
        for r in recs: f.write(json.dumps(r) + "\n")
    meta = {"n": len(recs), "n_perm": int(len(perms)), "n_bind": int(len(paffs)),
            "perm_q": pq, "bind_q": bq}
    print("DATA", json.dumps(meta))
    return meta

# ----------------------------------------------------------------------------- model (nanoGPT-style)
def make_model(vocab, d_model=384, n_layer=6, n_head=6, block=256, dropout=0.1):
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
            s.lnf = nn.LayerNorm(d_model); s.head = nn.Linear(d_model, vocab, bias=False)
            s.block = block
        def forward(s, idx):
            import torch
            b, t = idx.shape
            x = s.tok(idx) + s.pos(torch.arange(t, device=idx.device))[None]
            mask = torch.triu(torch.full((t, t), float("-inf"), device=idx.device), 1)
            for blk in s.blocks: x = blk(x, mask)
            return s.head(s.lnf(x))
    return GPT()

# ----------------------------------------------------------------------------- train
def encode(rec, stoi, block):
    toks = [f"<p_{rec['perm_b']}>", f"<b_{rec['bind_b']}>", BOS] + smi_tokens(rec["smiles"]) + [EOS]
    ids = [stoi[t] for t in toks if t in stoi]
    return ids[:block]

def train(args):
    import torch, numpy as np
    recs = [json.loads(l) for l in open(args.data)]
    random.Random(0).shuffle(recs)
    n_val = max(50, int(0.05 * len(recs)))
    val, tr = recs[:n_val], recs[n_val:]
    train_smiles = set(r["smiles"] for r in tr)
    stoi, toks = build_vocab([r["smiles"] for r in recs])
    block = args.block
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    model = make_model(len(toks), d_model=args.d_model, n_layer=args.n_layer, n_head=args.n_head, block=block).to(dev)
    nparams = sum(p.numel() for p in model.parameters())
    print(f"MODEL params={nparams/1e6:.1f}M vocab={len(toks)} dev={dev}")
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.1, betas=(0.9, 0.95))
    pad = stoi[PAD]
    def batch(split):
        src = tr if split == "train" else val
        ids = [encode(src[random.randrange(len(src))], stoi, block) for _ in range(args.batch)]
        mx = max(len(x) for x in ids)
        X = torch.full((len(ids), mx), pad, dtype=torch.long)
        for i, s in enumerate(ids): X[i, :len(s)] = torch.tensor(s)
        return X.to(dev)
    scaler = None
    model.train()
    t0 = time.time()
    for step in range(1, args.max_steps + 1):
        X = batch("train")
        logits = model(X[:, :-1]); tgt = X[:, 1:]
        loss = torch.nn.functional.cross_entropy(logits.reshape(-1, logits.size(-1)), tgt.reshape(-1), ignore_index=pad)
        opt.zero_grad(); loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step()
        if step % max(1, args.max_steps // 20) == 0 or step == 1:
            print(f"step {step}/{args.max_steps} loss {loss.item():.4f} ({(time.time()-t0)/step:.3f}s/it)", flush=True)
    ckpt = {"model": model.state_dict(), "stoi": stoi, "toks": toks, "args": vars(args),
            "train_smiles_n": len(train_smiles)}
    torch.save(ckpt, args.out_ckpt)
    json.dump(sorted(train_smiles), open(args.out_ckpt + ".trainsmiles.json", "w"))
    print("SAVED", args.out_ckpt)
    return args.out_ckpt

# ----------------------------------------------------------------------------- sampling + eval
def sample(model, stoi, toks, perm_b, bind_b, n, block, dev, temp=1.0, max_new=180):
    import torch
    itos = {i: t for t, i in stoi.items()}
    start = [stoi[f"<p_{perm_b}>"], stoi[f"<b_{bind_b}>"], stoi[BOS]]
    out = []
    for _ in range(n):
        ids = torch.tensor([start], device=dev)
        for _ in range(max_new):
            logits = model(ids[:, -block:])[0, -1] / temp
            p = torch.softmax(logits, -1)
            nxt = int(torch.multinomial(p, 1))
            if nxt == stoi[EOS]: break
            ids = torch.cat([ids, torch.tensor([[nxt]], device=dev)], 1)
        smi = "".join(itos[int(i)] for i in ids[0, 3:])
        out.append(smi)
    return out

def macrocyclic(mol):
    ri = mol.GetRingInfo()
    return any(len(r) >= 10 for r in ri.AtomRings())  # macrocycle = ring >=10 atoms

def eval_model(args):
    import torch, numpy as np
    from rdkit import Chem, RDLogger
    from rdkit.Chem import rdFingerprintGenerator
    from sklearn.ensemble import RandomForestRegressor
    RDLogger.DisableLog("rdApp.*")
    ck = torch.load(args.ckpt, map_location="cpu", weights_only=False)
    stoi, toks = ck["stoi"], ck["toks"]; a = ck["args"]
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    model = make_model(len(toks), d_model=a["d_model"], n_layer=a["n_layer"], n_head=a["n_head"], block=a["block"]).to(dev)
    model.load_state_dict(ck["model"]); model.eval()
    train_smiles = set(json.load(open(args.ckpt + ".trainsmiles.json")))
    # independent RF scorers (ECFP4) trained on the real labels, to score generations
    fpgen = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
    def fp(smi):
        m = Chem.MolFromSmiles(smi)
        return None if m is None else np.asarray(fpgen.GetFingerprint(m), dtype=np.float32)
    recs = [json.loads(l) for l in open(args.data)]
    def train_rf(key):
        X, y = [], []
        for r in recs:
            if r[key] is None: continue
            f = fp(r["smiles"])
            if f is not None: X.append(f); y.append(r[key])
        if len(y) < 50: return None
        rf = RandomForestRegressor(n_estimators=200, n_jobs=-1, random_state=0).fit(np.array(X), np.array(y))
        return rf
    perm_rf = train_rf("perm"); bind_rf = train_rf("paff")
    N = args.n_sample
    res = {"n_sample": N}
    # overall validity/cyclic/novelty on a neutral (mid,mid) condition
    gens = sample(model, stoi, toks, "mid", "mid", N, a["block"], dev, temp=args.temp)
    mols = [Chem.MolFromSmiles(s) for s in gens]
    valid = [(s, m) for s, m in zip(gens, mols) if m is not None]
    res["validity"] = round(len(valid)/len(gens), 3)
    res["macrocyclic_frac"] = round(sum(macrocyclic(m) for _, m in valid)/max(1, len(valid)), 3)
    canon = set(Chem.MolToSmiles(m) for _, m in valid)
    res["novelty_frac"] = round(len(canon - train_smiles)/max(1, len(canon)), 3)
    # CONDITIONING FIDELITY: high vs low control -> does scored property shift?
    def cond_shift(ctrl_perm_hi, ctrl_perm_lo, rf, prop_name):
        if rf is None: return {"note": "no scorer"}
        hi = sample(model, stoi, toks, ctrl_perm_hi[0], ctrl_perm_hi[1], N, a["block"], dev, temp=args.temp)
        lo = sample(model, stoi, toks, ctrl_perm_lo[0], ctrl_perm_lo[1], N, a["block"], dev, temp=args.temp)
        def score(gl):
            fps = [fp(s) for s in gl]; fps = [f for f in fps if f is not None]
            return rf.predict(np.array(fps)) if fps else np.array([])
        sh, sl = score(hi), score(lo)
        return {"mean_hi": round(float(sh.mean()), 3) if len(sh) else None,
                "mean_lo": round(float(sl.mean()), 3) if len(sl) else None,
                "delta_hi_minus_lo": round(float(sh.mean()-sl.mean()), 3) if len(sh) and len(sl) else None,
                "n_hi": len(sh), "n_lo": len(sl)}
    res["perm_conditioning"] = cond_shift(("hi", "unk"), ("lo", "unk"), perm_rf, "perm")
    res["bind_conditioning"] = cond_shift(("unk", "hi"), ("unk", "lo"), bind_rf, "paff")
    res["verdict"] = {
        "validity_ok": res["validity"] >= 0.5,
        "macrocycle_ok": res["macrocyclic_frac"] >= 0.3,
        "perm_conditioning_works": (res["perm_conditioning"].get("delta_hi_minus_lo") or 0) > 0.1,
        "bind_conditioning_works": (res["bind_conditioning"].get("delta_hi_minus_lo") or 0) > 0.1,
    }
    print("EVAL", json.dumps(res, indent=2))
    if args.out: json.dump(res, open(args.out, "w"), indent=2)
    return res

def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build-data"); b.add_argument("--cyc"); b.add_argument("--bind"); b.add_argument("--out", default="data.jsonl")
    t = sub.add_parser("train"); t.add_argument("--data", required=True); t.add_argument("--out-ckpt", default="cyclic_llm.pt")
    t.add_argument("--max-steps", type=int, default=3000); t.add_argument("--batch", type=int, default=64)
    t.add_argument("--block", type=int, default=256); t.add_argument("--d-model", type=int, default=384)
    t.add_argument("--n-layer", type=int, default=6); t.add_argument("--n-head", type=int, default=6); t.add_argument("--lr", type=float, default=3e-4)
    e = sub.add_parser("eval"); e.add_argument("--ckpt", required=True); e.add_argument("--data", required=True)
    e.add_argument("--n-sample", type=int, default=200); e.add_argument("--temp", type=float, default=1.0); e.add_argument("--out", default="eval.json")
    a = ap.parse_args()
    if a.cmd == "build-data": build_dataset(a.cyc, a.bind, a.out)
    elif a.cmd == "train": train(a)
    elif a.cmd == "eval": eval_model(a)

if __name__ == "__main__":
    main()
