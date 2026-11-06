"""v3.1 — MULTI-TARGET cross-target generalization (the fix for v3's n=1 NULL).

v3 trained on ONE target per regime, so the target-feature prefix was a CONSTANT across all
training examples -> zero gradient to learn "target changes -> binder changes" -> the model
ignored the prefix (NULL, by construction). v3.1 removes that degeneracy: it trains on >=2
targets with a PER-RECORD target prefix (each row carries its own target's feature vector), then
holds out a third target (leave-one-target-out). Now the prefix VARIES during training, so there
is a real gradient to learn target-conditioning — this is the minimum viable cross-target test.

Data: the 3 mRNA-display RaPID targets in display_ngs_multitarget (the only same-display-PLATFORM
trio we have): PADI4, hPCSK9, FIKK13. HONEST CONFOUND: cyclization co-varies with target
(PADI4/FIKK13 = thioether; hPCSK9 = photo-crosslink), so a POSITIVE could be chemistry, not
target identity; a NULL here is the stronger (data-wall) result. A clean same-chemistry >=3-target
test needs >=3 thioether targets (we have 2) — flagged as the next data need.

Reuses v3's helpers unchanged (target_feature, make_model, encode, sample, scoring) so the
committed v3 NULL result is not touched.
"""
from __future__ import annotations
import argparse, gzip, json, random, time
from pathlib import Path
import train_cyclic_llm_v3 as v3
from train_cyclic_llm_v3 import (AA, TOKS, STOI, PAD, BOS, EOS, target_feature, TFEAT_DIM,
                                 make_model, encode, sample, _valid, _ident_to, _comp_feat, _bucket)

RAPID = ["PADI4", "hPCSK9", "FIKK13"]
CYC = {"PADI4": "thioether", "FIKK13": "thioether", "hPCSK9": "photo_crosslink"}
# known held-out binder refs where we have one from the literature; else "" (eval falls back to
# the held-out target's own binder sequences from the data — never fabricated).
REF = {"FIKK13": "ESCRYRQVLQL", "PADI4": "", "hPCSK9": ""}


def build_dataset(csv_gz, targets_json, heldout, out_jsonl,
                  hi_thresh=2.0, lo_thresh=0.0, oversample_hi=8):
    assert heldout in RAPID, heldout
    train_targets = [t for t in RAPID if t != heldout]
    targets = json.load(open(targets_json))
    keep = set(RAPID)
    agg = {}  # (target,seq) -> {enr, binder}
    with gzip.open(csv_gz, "rt") as f:
        header = f.readline().rstrip("\n").split(",")
        ix = {c: i for i, c in enumerate(header)}
        for line in f:
            p = line.rstrip("\n").split(",")
            tgt = p[ix["target"]].split(" ")[0]
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
        side = "heldout" if tgt == heldout else "train"
        recs[side].append({"target": tgt, "seq": seq, "enr": v["enr"],
                           "enr_b": _bucket(v["enr"], lo_thresh, hi_thresh),
                           "is_binder": bool(v["binder"])})
    # oversample hi tail per TRAIN target (keeps each target's rare binders represented)
    tr = recs["train"]
    his = [r for r in tr if r["enr_b"] == "hi"]
    tr_out = tr + his * (oversample_hi - 1) if oversample_hi > 1 else tr
    tfeats = {t: target_feature(targets[t]["seq"]).tolist() for t in keep}
    Path(out_jsonl).parent.mkdir(parents=True, exist_ok=True)
    blob = {"heldout_target": heldout, "train_targets": train_targets,
            "ref_binder": REF.get(heldout, ""), "target_feats": tfeats, "cyc": CYC,
            "hi_thresh": hi_thresh, "lo_thresh": lo_thresh, "oversample_hi": oversample_hi,
            "train": tr_out, "heldout": recs["heldout"]}
    json.dump(blob, open(out_jsonl, "w"))
    from collections import Counter
    meta = {"heldout": heldout, "train_targets": train_targets,
            "train_cyc": [CYC[t] for t in train_targets], "heldout_cyc": CYC[heldout],
            "n_train_unique": len(tr), "n_train_oversampled": len(tr_out),
            "n_train_by_target": dict(Counter(r["target"] for r in tr)),
            "n_train_hi": len(his), "n_heldout": len(recs["heldout"]),
            "n_heldout_binder": sum(r["is_binder"] for r in recs["heldout"]),
            "same_chem_train": len(set(CYC[t] for t in train_targets)) == 1,
            "confounded": CYC[heldout] not in set(CYC[t] for t in train_targets)}
    print("DATA", json.dumps(meta))
    return meta


def train(args):
    import torch, numpy as np
    blob = json.load(open(args.data))
    tr = blob["train"]
    tfeats = {t: np.array(v, np.float32) for t, v in blob["target_feats"].items()}
    random.Random(0).shuffle(tr)
    json.dump({"train_seqs": sorted({r["seq"] for r in tr}),
               "meta": {k: blob[k] for k in ("heldout_target", "train_targets", "ref_binder",
                                             "hi_thresh", "lo_thresh", "target_feats", "cyc")}},
              open(args.out_ckpt + ".meta.json", "w"))
    dev = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
    block = args.block
    model = make_model(len(TOKS), TFEAT_DIM, d_model=args.d_model, n_layer=args.n_layer,
                       n_head=args.n_head, block=block).to(dev)
    n_tgt = len({r["target"] for r in tr})
    print(f"MODEL params={sum(p.numel() for p in model.parameters())/1e6:.1f}M dev={dev} "
          f"n_tr={len(tr)} train_targets={blob['train_targets']} ({n_tgt} distinct prefixes) "
          f"heldout={blob['heldout_target']}")
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=0.1, betas=(0.9, 0.95))
    pad = STOI[PAD]
    tf_t = {t: torch.tensor(v, device=dev) for t, v in tfeats.items()}

    def batch():
        picks = [tr[random.randrange(len(tr))] for _ in range(args.batch)]
        ids = [encode(r, block) for r in picks]
        mx = max(len(x) for x in ids)
        X = torch.full((len(ids), mx), pad, dtype=torch.long)
        for i, s in enumerate(ids):
            X[i, :len(s)] = torch.tensor(s)
        TF = torch.stack([tf_t[r["target"]] for r in picks])   # PER-RECORD prefix (varies!)
        return X.to(dev), TF

    model.train(); t0 = time.time()
    for step in range(1, args.max_steps + 1):
        X, TF = batch()
        logits = model(X, TF)
        loss = torch.nn.functional.cross_entropy(
            logits[:, :-1].reshape(-1, logits.size(-1)), X.reshape(-1), ignore_index=pad)
        opt.zero_grad(); loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step()
        if step % max(1, args.max_steps // 20) == 0 or step == 1:
            print(f"step {step}/{args.max_steps} loss {loss.item():.4f} "
                  f"({(time.time()-t0)/step:.3f}s/it)", flush=True)
    torch.save({"model": model.state_dict(), "args": vars(args)}, args.out_ckpt)
    print("SAVED", args.out_ckpt)


def eval_model(args):
    import torch, numpy as np
    from sklearn.ensemble import RandomForestRegressor
    ck = torch.load(args.ckpt, map_location="cpu", weights_only=False); a = ck["args"]
    meta = json.load(open(args.ckpt + ".meta.json"))["meta"]
    blob = json.load(open(args.data))
    train_seqs = set(json.load(open(args.ckpt + ".meta.json"))["train_seqs"])
    heldout = blob["heldout"]
    tfeats = meta["target_feats"]
    held_t = meta["heldout_target"]; train_ts = meta["train_targets"]
    ref = meta["ref_binder"]
    # "train conditioning" baseline = MEAN of the train-target feature vectors
    train_mean = np.mean([np.array(tfeats[t], np.float32) for t in train_ts], axis=0)
    dev = "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
    model = make_model(len(TOKS), TFEAT_DIM, d_model=a["d_model"], n_layer=a["n_layer"],
                       n_head=a["n_head"], block=a["block"]).to(dev)
    model.load_state_dict(ck["model"]); model.eval()

    ho = [r for r in heldout if _valid(r["seq"])]
    rf = None
    if len(ho) >= 50:
        Xh = np.array([_comp_feat(r["seq"]) for r in ho]); yh = np.array([r["enr"] for r in ho])
        rf = RandomForestRegressor(n_estimators=300, n_jobs=-1, random_state=0).fit(Xh, yh)
    ho_binders = [r["seq"] for r in ho if r["is_binder"]]
    N = args.n_sample

    def gen(feat_vec, b):
        return sample(model, list(map(float, feat_vec)), b, N, a["block"], dev, temp=args.temp)

    def stats(seqs):
        valid = [s for s in seqs if _valid(s)]
        vr = len(valid) / max(1, len(seqs))
        predH = float(rf.predict(np.array([_comp_feat(s) for s in valid])).mean()) if (rf is not None and valid) else None
        identref = float(np.mean([_ident_to(s, ref) for s in valid])) if (valid and ref) else 0.0
        identbind = float(np.mean([max((_ident_to(s, b) for b in ho_binders), default=0.0) for s in valid])) if (valid and ho_binders) else 0.0
        novel = len(set(valid) - train_seqs) / max(1, len(set(valid)))
        return {"validity": round(vr, 3),
                "pred_heldout_enrichment": round(predH, 3) if predH is not None else None,
                "identity_to_ref_binder": round(identref, 3),
                "mean_max_identity_to_heldout_binders": round(identbind, 3),
                "novelty_frac": round(novel, 3)}

    cond = {
        "heldout_feats_hi": stats(gen(np.array(tfeats[held_t], np.float32), "hi")),
        "heldout_feats_lo": stats(gen(np.array(tfeats[held_t], np.float32), "lo")),
        "trainmean_feats_hi": stats(gen(train_mean, "hi")),
    }

    def d(x, y, key):
        return round((cond[x][key] or 0) - (cond[y][key] or 0), 3)

    cd = {
        "hi_vs_lo_pred_heldout_enr": d("heldout_feats_hi", "heldout_feats_lo", "pred_heldout_enrichment"),
        "heldoutfeats_vs_trainmean_pred_heldout_enr": d("heldout_feats_hi", "trainmean_feats_hi", "pred_heldout_enrichment"),
        "heldoutfeats_vs_trainmean_ident_binders": d("heldout_feats_hi", "trainmean_feats_hi", "mean_max_identity_to_heldout_binders"),
    }
    target_feats_matter = abs(cd["heldoutfeats_vs_trainmean_pred_heldout_enr"]) > 0.2 or \
                          abs(cd["heldoutfeats_vs_trainmean_ident_binders"]) > 0.02
    transfer_positive = (cd["hi_vs_lo_pred_heldout_enr"] > 0.2 and
                         cd["heldoutfeats_vs_trainmean_pred_heldout_enr"] > 0.1 and
                         cd["heldoutfeats_vs_trainmean_ident_binders"] > 0.02)
    res = {
        "version": "v3.1_multitarget", "heldout_target": held_t, "train_targets": train_ts,
        "train_cyc": [CYC[t] for t in train_ts], "heldout_cyc": CYC[held_t],
        "same_chem_train": len(set(CYC[t] for t in train_ts)) == 1,
        "confounded_chem": CYC[held_t] not in set(CYC[t] for t in train_ts),
        "n_sample": N, "n_heldout_rows": len(ho), "n_heldout_binders": len(ho_binders),
        "conditionings": cond, "cross_target_deltas": cd,
        "verdict": {
            "validity_ok": cond["heldout_feats_hi"]["validity"] >= 0.8,
            "enrichment_conditioning_fires": bool(cd["hi_vs_lo_pred_heldout_enr"] > 0.2),
            "target_features_matter": bool(target_feats_matter),
            "cross_target_transfer": "POSITIVE" if transfer_positive else ("WEAK" if target_feats_matter else "NULL"),
            "note": ("v3.1 trains on 2 targets (varying prefix -> real gradient, unlike v3's n=1). "
                     "If still NULL, the data wall is deeper than target count. If POSITIVE/WEAK, note the "
                     "cyclization confound (train vs heldout chemistry) before claiming target transfer."),
        },
    }
    print("EVAL", json.dumps(res, indent=2))
    if args.out:
        json.dump(res, open(args.out, "w"), indent=2)
    return res


def main():
    ap = argparse.ArgumentParser(); sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build-data")
    b.add_argument("--csv", required=True); b.add_argument("--targets", required=True)
    b.add_argument("--heldout", required=True, choices=RAPID); b.add_argument("--out", required=True)
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
    if a.cmd == "build-data": build_dataset(a.csv, a.targets, a.heldout, a.out, a.hi_thresh, a.lo_thresh, a.oversample_hi)
    elif a.cmd == "train": train(a)
    elif a.cmd == "eval": eval_model(a)


if __name__ == "__main__":
    main()
