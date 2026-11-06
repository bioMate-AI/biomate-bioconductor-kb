"""Unified cyclic-peptide LLM (v4) — the synthesis: ncAA-native + multi-target + multi-property, ONE model.

Folds the two levers into a single model:
  - MONOMER vocabulary (ncAA/N-methyl/D-AA native, from CycPeptMPDB) — the 20 canonical AAs are a subset,
    so display sequences (canonical-AA strings) tokenize in the same space.
  - Conditioning = {target-feature prefix (v3.1), binding-enrichment bucket, permeability bucket}, each with
    a NULL token where a dataset lacks that label.
  - Trained on the UNION: CycPeptMPDB (ncAA monomers + measured permeability; no target/binding) +
    display pool (target + binding-enrichment; canonical-AA). One shared encoder learns chemistry from both.

Two heads of evidence from ONE model:
  (A) ncAA generation + permeability control (CycPeptMPDB side): sample p_hi vs p_lo (null target, e=na) ->
      ncAA fraction + permeability delta via a held-out composition regressor.
  (B) multi-target binding selection (display side): per target, LLR = logP(seq|target, e_hi) -
      logP(seq|target, e_lo) -> held-out-sequence AUC(is_binder).

Reuses v3's target-prefix model. Local MPS.
"""
from __future__ import annotations
import argparse, ast, csv, gzip, json, random, time
from pathlib import Path
import numpy as np
import train_cyclic_llm_v3 as v3
from train_cyclic_llm_v3 import target_feature, TFEAT_DIM, make_model

CANON = list("ACDEFGHIKLMNPQRSTVWY")
CANON_SET = set(CANON)
PAD, BOS, EOS = "<pad>", "<bos>", "<eos>"
EBUCK = ["<e_lo>", "<e_mid>", "<e_hi>", "<e_na>"]   # binding-enrichment bucket (na = unlabeled)
PBUCK = ["<p_lo>", "<p_hi>", "<p_na>"]              # permeability bucket (na = unlabeled)
HI, LO = 2.0, 0.0
DISPLAY_TARGETS = ["PADI4", "hPCSK9", "FIKK13", "Abeta42", "hIAPP"]


def parse_monomers(s):
    s = (s or "").strip()
    if not s: return None
    try: lst = ast.literal_eval(s) if s.startswith("[") else s.split(".")
    except Exception: return None
    lst = [str(m).strip() for m in lst if str(m).strip()]
    return lst or None


def load_cycpept(path, max_len):
    rows = []
    with open(path) as f:
        for row in csv.DictReader(f):
            m = parse_monomers(row.get("Sequence", ""))
            if not m or not (3 <= len(m) <= max_len): continue
            try: perm = float(row.get("Permeability", ""))
            except (ValueError, TypeError): perm = None
            rows.append({"monomers": m, "perm": perm, "target": None, "enr_b": "<e_na>", "is_binder": False})
    return rows


def load_display(csv_gz, targets_json, max_len):
    tproteins = json.load(open(targets_json))
    agg = {}
    with gzip.open(csv_gz, "rt") as f:
        hdr = f.readline().rstrip("\n").split(","); ix = {c: i for i, c in enumerate(hdr)}
        for line in f:
            p = line.rstrip("\n").split(",")
            tgt = p[ix["target"]].split(" ")[0]
            if tgt not in DISPLAY_TARGETS or tgt not in tproteins: continue
            seq = p[ix["sequence"]].strip().upper()
            if not seq or any(c not in CANON_SET for c in seq) or not (6 <= len(seq) <= max_len): continue
            try: enr = float(p[ix["enrichment_log2fc"]])
            except ValueError: continue
            binder = p[ix["is_binder"]] in ("1", "True", "true")
            k = (tgt, seq); cur = agg.get(k)
            if cur is None or enr > cur[0]: agg[k] = [enr, binder or (cur[1] if cur else False)]
    tfeats = {t: target_feature(tproteins[t]["seq"]).astype("float32") for t in DISPLAY_TARGETS if t in tproteins}
    rows = []
    for (t, s), (e, b) in agg.items():
        eb = "<e_hi>" if e >= HI else ("<e_lo>" if e <= LO else "<e_mid>")
        rows.append({"monomers": list(s), "perm": None, "target": t, "enr_b": eb, "is_binder": b, "enr": e})
    return rows, tfeats


def build_vocab(rows):
    mon = set()
    for r in rows: mon.update(r["monomers"])
    mon.update(CANON)
    toks = [PAD, BOS, EOS] + EBUCK + PBUCK + sorted(mon)
    return toks, {t: i for i, t in enumerate(toks)}


def encode(rec, stoi, block):
    toks = [rec["enr_b"], rec["pb"], BOS] + rec["monomers"] + [EOS]
    return [stoi[t] for t in toks if t in stoi][:block]


def ncaa_frac(ms): return sum(1 for m in ms if m not in CANON_SET) / max(1, len(ms))


def run(args):
    import torch
    from sklearn.ensemble import RandomForestRegressor
    from sklearn.metrics import roc_auc_score
    cyc = load_cycpept(args.cycpept, args.max_len)
    disp, tfeats = load_display(args.display, args.targets, args.max_len)
    # permeability buckets on cycpept measured subset (median)
    pv = np.array([r["perm"] for r in cyc if r["perm"] is not None]); med = float(np.median(pv))
    for r in cyc: r["pb"] = ("<p_hi>" if (r["perm"] is not None and r["perm"] >= med) else ("<p_lo>" if r["perm"] is not None else "<p_na>"))
    for r in disp: r["pb"] = "<p_na>"
    rows = cyc + disp
    toks, stoi = build_vocab(rows)
    nnc = len([t for t in toks if t not in CANON_SET and t not in (PAD, BOS, EOS, *EBUCK, *PBUCK)])
    print(f"UNION: {len(cyc)} CycPeptMPDB (+perm) + {len(disp)} display (+target/binding); vocab={len(toks)} ({nnc} ncAA monomers)")
    ZERO = np.zeros(TFEAT_DIM, np.float32)   # null-target prefix for CycPeptMPDB
    # held-out splits: per display target by sequence (for binding eval) + cycpept perm val (for perm eval)
    random.Random(0).shuffle(disp)
    disp_test, disp_train = [], []
    for t in DISPLAY_TARGETS:
        rs = [r for r in disp if r["target"] == t]
        nte = min(args.max_test, max(200, int(len(rs) * 0.2)))
        bind = [r for r in rs if r["is_binder"]]; non = [r for r in rs if not r["is_binder"]]
        te = bind[:nte//2] + non[:nte - len(bind[:nte//2])]; teset = {id(r) for r in te}
        disp_test += te; disp_train += [r for r in rs if id(r) not in teset]
    cyc_perm = [r for r in cyc if r["perm"] is not None]; random.Random(1).shuffle(cyc_perm)
    nv = max(200, int(len(cyc_perm) * 0.15)); cyc_val, cyc_tr_perm = cyc_perm[:nv], cyc_perm[nv:]
    cyc_train = cyc_tr_perm + [r for r in cyc if r["perm"] is None]
    his = [r for r in disp_train if r["enr_b"] == "<e_hi>"]
    disp_full = disp_train + his * (args.oversample_hi - 1)
    # BALANCE the two datasets: display (~560k canonical) drowns CycPeptMPDB (~36k ncAA) ~16:1, which
    # collapses ncAA generation. Oversample CycPeptMPDB to ~match the display count so the model learns
    # BOTH chemistries (ncAA generation + multi-target binding).
    kcyc = max(1, round(len(disp_full) / max(1, len(cyc_train))))
    train = cyc_train * kcyc + disp_full
    print(f"balance: CycPeptMPDB x{kcyc} ({len(cyc_train)}->{len(cyc_train)*kcyc}) vs display {len(disp_full)}")
    random.Random(2).shuffle(train)
    # perm regressor on cycpept val (monomer composition)
    vlist = sorted({m for r in cyc for m in r["monomers"]}); vidx = {m: i for i, m in enumerate(vlist)}
    def comp(ms):
        v = np.zeros(len(vlist) + 2, np.float32)
        for m in ms:
            if m in vidx: v[vidx[m]] += 1
        v[:len(vlist)] /= max(1, len(ms)); v[-2] = len(ms); v[-1] = ncaa_frac(ms); return v
    rf = RandomForestRegressor(n_estimators=250, n_jobs=-1, random_state=0).fit(
        np.array([comp(r["monomers"]) for r in cyc_val]), np.array([r["perm"] for r in cyc_val]))

    dev = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
    block = args.block
    model = make_model(len(toks), TFEAT_DIM, d_model=args.d_model, n_layer=args.n_layer, n_head=args.n_head, block=block).to(dev)
    print(f"UNIFIED v4 params={sum(p.numel() for p in model.parameters())/1e6:.1f}M dev={dev} n_train={len(train)}")
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.1, betas=(0.9, 0.95)); pad = stoi[PAD]
    tf_t = {t: torch.tensor(np.asarray(v), device=dev) for t, v in tfeats.items()}
    zero_t = torch.tensor(ZERO, device=dev)
    def tf_of(r): return tf_t[r["target"]] if r["target"] in tf_t else zero_t
    def batch():
        picks = [train[random.randrange(len(train))] for _ in range(args.batch)]
        ids = [encode(r, stoi, block) for r in picks]; mx = max(len(x) for x in ids)
        X = torch.full((len(ids), mx), pad, dtype=torch.long)
        for i, s in enumerate(ids): X[i, :len(s)] = torch.tensor(s)
        TF = torch.stack([tf_of(r) for r in picks])
        return X.to(dev), TF
    model.train(); t0 = time.time()
    for step in range(1, args.max_steps + 1):
        X, TF = batch(); logits = model(X, TF)
        loss = torch.nn.functional.cross_entropy(logits[:, :-1].reshape(-1, logits.size(-1)), X.reshape(-1), ignore_index=pad)
        opt.zero_grad(); loss.backward(); torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step()
        if step % max(1, args.max_steps // 10) == 0: print(f"  step {step}/{args.max_steps} loss {loss.item():.3f} ({(time.time()-t0)/step:.3f}s/it)", flush=True)
    model.eval(); itos = {i: t for t, i in stoi.items()}

    def loglik(monos, enr_b, pb, tfeat):
        ids = [stoi[enr_b], stoi[pb], stoi[BOS]] + [stoi[m] for m in monos if m in stoi] + [stoi[EOS]]
        x = torch.tensor([ids], device=dev); tf = torch.tensor(np.asarray(tfeat), device=dev)[None]
        with torch.no_grad(): logp = torch.log_softmax(model(x, tf)[0], -1)
        tgt = x[0]; tok = logp[torch.arange(len(tgt)), tgt]
        return float(tok[3:3 + len(monos)].sum())      # monomers only (after e,p,BOS), exclude EOS

    # (A) ncAA + permeability (CycPeptMPDB side: null target, e=na, vary p)
    def sample(pb):
        out = []
        for _ in range(args.n_sample):
            ids = [stoi["<e_na>"], stoi[pb], stoi[BOS]]
            for _ in range(args.max_len + 1):
                with torch.no_grad():
                    lg = model(torch.tensor([ids[-block:]], device=dev), zero_t[None])[0, -1] / args.temp
                nx = int(torch.multinomial(torch.softmax(lg, -1), 1))
                if nx == stoi[EOS]: break
                ids.append(nx)
            out.append([itos[i] for i in ids[3:]])
        return out
    def pstats(g):
        val = [s for s in g if 3 <= len(s) <= args.max_len and all(t in stoi and t not in (PAD, BOS, EOS, *EBUCK, *PBUCK) for t in s)]
        return {"validity": round(len(val)/max(1, len(g)), 3), "mean_ncAA_frac": round(float(np.mean([ncaa_frac(s) for s in val])) if val else 0, 3),
                "pred_perm": round(float(rf.predict(np.array([comp(s) for s in val])).mean()), 3) if val else None}
    hi, lo = pstats(sample("<p_hi>")), pstats(sample("<p_lo>"))

    # (B) multi-target binding selection (display side: vary e_hi vs e_lo, p=na, target prefix)
    per_target = {}
    for t in DISPLAY_TARGETS:
        if t not in tfeats: continue
        te = [r for r in disp_test if r["target"] == t]; y = np.array([1 if r["is_binder"] else 0 for r in te])
        if y.sum() < 10 or y.sum() == len(y): continue
        llr = np.array([loglik(r["monomers"], "<e_hi>", "<p_na>", tfeats[t]) - loglik(r["monomers"], "<e_lo>", "<p_na>", tfeats[t]) for r in te])
        per_target[t] = {"AUC": round(float(roc_auc_score(y, llr)), 3), "binders": int(y.sum()), "n_test": len(te)}

    res = {"model": "unified_cyclic_llm_v4 (ncAA-native + multi-target + multi-property, ONE model)",
           "vocab": len(toks), "ncaa_monomers": nnc, "n_train": len(train),
           "A_ncaa_permeability": {"cond_p_hi": hi, "cond_p_lo": lo,
                                   "perm_delta": round((hi["pred_perm"] or 0) - (lo["pred_perm"] or 0), 3)},
           "B_multitarget_binding_AUC": per_target,
           "note": "ONE model does ncAA-native permeability-controlled generation (A) AND multi-target "
                   "binding selection (B). Union training (CycPeptMPDB ncAA+perm | display target+binding). "
                   "This is the synthesis of the two best-LLM levers."}
    print("UNIFIED_V4", json.dumps(res))
    if args.out: Path(args.out).parent.mkdir(parents=True, exist_ok=True); json.dump(res, open(args.out, "w"), indent=2)
    if args.ckpt: torch.save({"model": model.state_dict(), "toks": toks, "args": vars(args)}, args.ckpt)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cycpept", default="../data/raw/CycPeptMPDB_Peptide_All.csv")
    ap.add_argument("--display", default="../data/display/display_ngs_multitarget.csv.gz")
    ap.add_argument("--targets", default="../data/display/target_proteins.json")
    ap.add_argument("--max-len", type=int, default=16); ap.add_argument("--max-steps", type=int, default=3000)
    ap.add_argument("--batch", type=int, default=128); ap.add_argument("--block", type=int, default=40)
    ap.add_argument("--d-model", type=int, default=256); ap.add_argument("--n-layer", type=int, default=6)
    ap.add_argument("--n-head", type=int, default=8); ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--oversample-hi", type=int, default=8); ap.add_argument("--n-sample", type=int, default=300)
    ap.add_argument("--temp", type=float, default=1.0); ap.add_argument("--max-test", type=int, default=3000)
    ap.add_argument("--out"); ap.add_argument("--ckpt")
    run(ap.parse_args())


if __name__ == "__main__":
    main()
