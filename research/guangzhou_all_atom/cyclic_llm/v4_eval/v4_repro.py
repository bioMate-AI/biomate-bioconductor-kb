#!/usr/bin/env python3
"""Reproduce v4 display-side AUCs from the checkpoint on the verbatim split, then run the controls the original evaluation lacked:
 R   reproduction of stored per-target AUC (results/unified_cyclic_llm_v4_eval.json)
 C1  hard-negative AUC: binders vs NON-binder rows whose enrichment bucket is e_hi (the real discrimination problem)
 C2  swapped conditioning (e_lo - e_hi): must give ~1-AUC (sign sanity)
 C3  wrong-target prefix: LLR computed with another target's descriptor (does target conditioning matter?)
 C4  trivial baselines on the same split: length; amino-acid composition logistic; abundance (log2fc itself, upper bound / null)
usage: python3 v4_repro.py CKPT OUT.json [--device cpu]   (run from cyclic_llm/)"""
import sys, os, json, random, argparse
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import torch
import unified_cyclic_llm as U
from train_cyclic_llm_v3 import make_model, TFEAT_DIM
from sklearn.metrics import roc_auc_score
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import cross_val_predict

ap = argparse.ArgumentParser(); ap.add_argument("ckpt"); ap.add_argument("out"); ap.add_argument("--device", default="cpu"); ap.add_argument("--bs", type=int, default=512)
a = ap.parse_args()
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data")
ck = torch.load(a.ckpt, map_location="cpu", weights_only=False); args = ck["args"]; toks = ck["toks"]; stoi = {t: i for i, t in enumerate(toks)}
disp, tfeats = U.load_display(f"{D}/display/display_ngs_multitarget.csv.gz", f"{D}/display/target_proteins.json", args["max_len"])
# vocabulary identity check (rebuild exactly as training did)
cyc = U.load_cycpept(f"{D}/raw/CycPeptMPDB_Peptide_All.csv", args["max_len"])
pv = np.array([r["perm"] for r in cyc if r["perm"] is not None]); med = float(np.median(pv))
for r in cyc: r["pb"] = ("<p_hi>" if (r["perm"] is not None and r["perm"] >= med) else ("<p_lo>" if r["perm"] is not None else "<p_na>"))
for r in disp: r["pb"] = "<p_na>"
toks2, _ = U.build_vocab(cyc + disp)
vocab_same = toks2 == toks
random.Random(0).shuffle(disp)
test = []
for t in U.DISPLAY_TARGETS:
    rs = [r for r in disp if r["target"] == t]; nte = min(args["max_test"], max(200, int(len(rs) * 0.2)))
    bind = [r for r in rs if r["is_binder"]]; non = [r for r in rs if not r["is_binder"]]
    test += bind[:nte // 2] + non[:nte - len(bind[:nte // 2])]
dev = a.device
model = make_model(len(toks), TFEAT_DIM, d_model=args["d_model"], n_layer=args["n_layer"], n_head=args["n_head"], block=args["block"]); model.load_state_dict(ck["model"]); model.to(dev).eval()
pad = stoi[U.PAD]

def llr_batch(recs, tf, eb_a="<e_hi>", eb_b="<e_lo>"):
    out = []
    for i in range(0, len(recs), a.bs):
        chunk = recs[i:i + a.bs]; vals = []
        for eb in (eb_a, eb_b):
            ids = [[stoi[eb], stoi["<p_na>"], stoi[U.BOS]] + [stoi[m] for m in r["monomers"] if m in stoi] + [stoi[U.EOS]] for r in chunk]
            mx = max(len(x) for x in ids); X = torch.full((len(ids), mx), pad, dtype=torch.long)
            for j, s in enumerate(ids): X[j, :len(s)] = torch.tensor(s)
            TF = torch.tensor(np.asarray(tf))[None].repeat(len(ids), 1)
            with torch.no_grad(): lp = torch.log_softmax(model(X.to(dev), TF.to(dev)), -1)
            tl = lp[:, :mx].gather(2, X.to(dev)[:, :, None])[:, :, 0]   # position i (0 = target prefix) predicts token i
            v = []
            for j, r in enumerate(chunk):
                n = len([m for m in r["monomers"] if m in stoi]); v.append(float(tl[j, 3:3 + n].sum()))
            vals.append(np.array(v))
        out.append(vals[0] - vals[1])
    return np.concatenate(out)

res = {"vocab_rebuild_identical_to_checkpoint": bool(vocab_same), "ckpt": os.path.basename(a.ckpt)}
stored = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "results", "unified_cyclic_llm_v4_eval.json")))["B_multitarget_binding_AUC"]
AAS = list("ACDEFGHIKLMNPQRSTVWY")
for t in U.DISPLAY_TARGETS:
    te = [r for r in test if r["target"] == t]; y = np.array([int(r["is_binder"]) for r in te])
    if y.sum() < 10 or y.sum() == len(y): continue
    llr = llr_batch(te, tfeats[t]); d = {"n_test": len(te), "binders": int(y.sum())}
    d["R_AUC_reproduced"] = round(float(roc_auc_score(y, llr)), 3); d["R_AUC_stored"] = stored.get(t, {}).get("AUC")
    hn = np.array([(not r["is_binder"]) and r["enr_b"] == "<e_hi>" for r in te]); sel = (y == 1) | hn
    d["n_hard_negatives_in_test(e_hi,not binder)"] = int(hn.sum())
    d["C1_AUC_vs_hard_negatives"] = round(float(roc_auc_score(y[sel], llr[sel])), 3) if hn.sum() >= 10 else None
    d["C2_AUC_swapped_conditioning"] = round(float(roc_auc_score(y, llr_batch(te, tfeats[t], "<e_lo>", "<e_hi>"))), 3)
    other = [x for x in U.DISPLAY_TARGETS if x != t and x in tfeats]
    d["C3_AUC_wrong_target_prefix_mean"] = round(float(np.mean([roc_auc_score(y, llr_batch(te, tfeats[o])) for o in other])), 3)
    d["C4_length_AUC"] = round(float(roc_auc_score(y, [-len(r["monomers"]) for r in te])), 3)
    X = np.array([[r["monomers"].count(c) / len(r["monomers"]) for c in AAS] + [len(r["monomers"])] for r in te])
    p = cross_val_predict(LogisticRegression(max_iter=2000), X, y, cv=5, method="decision_function")
    d["C4_composition_logistic_AUC_cv"] = round(float(roc_auc_score(y, p)), 3)
    d["C4_abundance_log2fc_AUC"] = round(float(roc_auc_score(y, [r["enr"] for r in te])), 3)
    d["C4_abundance_log2fc_AUC_vs_hard_negatives"] = round(float(roc_auc_score(y[sel], [r["enr"] for r in np.array(te, dtype=object)[sel]])), 3) if hn.sum() >= 10 else None
    res[t] = d; print(t, json.dumps(d), flush=True)
json.dump(res, open(a.out, "w"), indent=1)
