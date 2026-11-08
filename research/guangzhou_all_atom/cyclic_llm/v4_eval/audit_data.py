#!/usr/bin/env python3
"""Data/split audit of the v4 unified cyclic LLM (unified_cyclic_llm.py). Replicates the v4 splits verbatim and measures:
 (1) permeability-eval split: monomer-tuple duplicates between LM-train and the held-out set (same peptide measured in several sources);
 (2) what "ncAA fraction" counts (D-/N-methyl variants of canonical residues) and its training-data baseline;
 (3) calibration of the composition regressor used for 'perm_delta' (real hi-vs-lo peptides scored by the same regressor; CV R2);
 (4) display split: (target,seq) overlap, class balance, near-duplicate (3-mer Jaccard) leakage test->train;
 (5) topology: share of CycPeptMPDB rows that are Lariat (not head-to-tail).
usage: python3 audit_data.py OUT.json   (run from cyclic_llm/)"""
import sys, os, json, random, csv, re, collections
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import unified_cyclic_llm as U

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data")
MAXLEN = 16
out = {}

# ------------------------------------------------------------------ (5) topology
rows_all = list(csv.DictReader(open(f"{D}/raw/CycPeptMPDB_Peptide_All.csv", encoding="utf-8-sig", errors="replace")))
shape = collections.Counter(r.get("Molecule_Shape") for r in rows_all)
out["topology"] = {"CycPeptMPDB_rows": len(rows_all), "shape_counts": dict(shape),
                   "frac_lariat": round(shape.get("Lariat", 0) / len(rows_all), 3)}

# ------------------------------------------------------------------ (1)(2)(3) permeability side (verbatim v4 split)
cyc = U.load_cycpept(f"{D}/raw/CycPeptMPDB_Peptide_All.csv", MAXLEN)
pv = np.array([r["perm"] for r in cyc if r["perm"] is not None]); med = float(np.median(pv))
cyc_perm = [r for r in cyc if r["perm"] is not None]; random.Random(1).shuffle(cyc_perm)
nv = max(200, int(len(cyc_perm) * 0.15)); cyc_val, cyc_tr_perm = cyc_perm[:nv], cyc_perm[nv:]
tup = lambda r: tuple(r["monomers"])
tr_set = {tup(r) for r in cyc_tr_perm}
dup_val = sum(1 for r in cyc_val if tup(r) in tr_set)
out["perm_split"] = {"n_cycpept_len3_16": len(cyc), "n_measured": len(cyc_perm), "n_val": len(cyc_val), "n_train_perm": len(cyc_tr_perm),
                     "val_monomer_tuples_also_in_LM_train": dup_val, "frac": round(dup_val / len(cyc_val), 3),
                     "note": "regressor 'rf' (perm_delta oracle) is fit on val only; LM trained on cyc_tr_perm + unlabeled cycpept"}
# stereo/methyl-collapsed identity (dX->X, meX->X): same backbone chemistry up to stereo/N-methyl
def collapse(m):
    m2 = re.sub(r"^(me|d)(?=[A-Z])", "", m); m2 = re.sub(r"^(me|d)(?=[A-Z])", "", m2); return m2
trc = {tuple(collapse(m) for m in r["monomers"]) for r in cyc_tr_perm}
out["perm_split"]["val_collapsed_tuples_also_in_train"] = sum(1 for r in cyc_val if tuple(collapse(m) for m in r["monomers"]) in trc)

# (2) ncAA definition
cnt = collections.Counter(); tot = 0
for r in cyc:
    for m in r["monomers"]:
        tot += 1
        if m in U.CANON_SET: cnt["canonical_L"] += 1
        elif re.fullmatch(r"d[A-Z]", m): cnt["D_of_canonical"] += 1
        elif re.fullmatch(r"me[A-Z]", m): cnt["Nmethyl_of_canonical"] += 1
        elif re.fullmatch(r"(me)?d[A-Z]|dme[A-Z]|d[A-Z]me", m): cnt["D+Nmethyl_of_canonical"] += 1
        else: cnt["other_ncAA"] += 1
out["ncaa_definition"] = {k: round(v / tot, 3) for k, v in cnt.items()}
out["ncaa_definition"]["frac_flagged_ncAA_by_v4_metric_in_training_data"] = round(float(np.mean([U.ncaa_frac(r["monomers"]) for r in cyc])), 3)
hi = [r for r in cyc_perm if r["perm"] >= med]; lo = [r for r in cyc_perm if r["perm"] < med]
out["ncaa_definition"]["real_hi_perm_mean_ncaa_frac"] = round(float(np.mean([U.ncaa_frac(r["monomers"]) for r in hi])), 3)
out["ncaa_definition"]["real_lo_perm_mean_ncaa_frac"] = round(float(np.mean([U.ncaa_frac(r["monomers"]) for r in lo])), 3)

# (3) regressor calibration
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import cross_val_predict, KFold
vlist = sorted({m for r in cyc for m in r["monomers"]}); vidx = {m: i for i, m in enumerate(vlist)}
def comp(ms):
    v = np.zeros(len(vlist) + 2, np.float32)
    for m in ms:
        if m in vidx: v[vidx[m]] += 1
    v[:len(vlist)] /= max(1, len(ms)); v[-2] = len(ms); v[-1] = U.ncaa_frac(ms); return v
Xv = np.array([comp(r["monomers"]) for r in cyc_val]); yv = np.array([r["perm"] for r in cyc_val])
rf = RandomForestRegressor(n_estimators=250, n_jobs=-1, random_state=0)
cv = cross_val_predict(rf, Xv, yv, cv=KFold(5, shuffle=True, random_state=0))
r2 = 1 - ((yv - cv) ** 2).sum() / ((yv - yv.mean()) ** 2).sum()
rf.fit(Xv, yv)
p_hi = rf.predict(np.array([comp(r["monomers"]) for r in hi])).mean(); p_lo = rf.predict(np.array([comp(r["monomers"]) for r in lo])).mean()
real_gap = float(np.mean([r["perm"] for r in hi]) - np.mean([r["perm"] for r in lo]))
out["perm_regressor"] = {"n_fit": len(yv), "cv_R2_within_val": round(float(r2), 3),
                         "regressor_pred_delta_real_hi_minus_lo_train": round(float(p_hi - p_lo), 3),
                         "true_measured_delta_real_hi_minus_lo": round(real_gap, 3),
                         "v4_reported_perm_delta": 0.468,
                         "note": "if the regressor's delta on REAL hi/lo peptides is small, a generated delta of 0.47 is not interpretable as a permeability effect"}

# ------------------------------------------------------------------ (4) display side (verbatim v4 split)
disp, tfeats = U.load_display(f"{D}/display/display_ngs_multitarget.csv.gz", f"{D}/display/target_proteins.json", MAXLEN)
random.Random(0).shuffle(disp)
disp_test, disp_train = [], []
for t in U.DISPLAY_TARGETS:
    rs = [r for r in disp if r["target"] == t]
    nte = min(3000, max(200, int(len(rs) * 0.2)))
    bind = [r for r in rs if r["is_binder"]]; non = [r for r in rs if not r["is_binder"]]
    te = bind[:nte // 2] + non[:nte - len(bind[:nte // 2])]; teset = {id(r) for r in te}
    disp_test += te; disp_train += [r for r in rs if id(r) not in teset]
def kmers(s, k=3): return {s[i:i + k] for i in range(len(s) - k + 1)}
disp_out = {}
for t in U.DISPLAY_TARGETS:
    te = [r for r in disp_test if r["target"] == t]; tr = [r for r in disp_train if r["target"] == t]
    trs = {"".join(r["monomers"]) for r in tr}
    ov = sum(1 for r in te if "".join(r["monomers"]) in trs)
    trb = [kmers("".join(r["monomers"])) for r in tr if r["is_binder"]]
    rng = random.Random(0); samp = rng.sample([r for r in te if r["is_binder"]], min(150, sum(r["is_binder"] for r in te))) if any(r["is_binder"] for r in te) else []
    # max 3-mer Jaccard of each test binder to the TRAIN binders (sampled train binders for speed)
    trb_s = rng.sample(trb, min(4000, len(trb))) if trb else []
    mj = []
    for r in samp:
        k = kmers("".join(r["monomers"]))
        mj.append(max((len(k & k2) / max(1, len(k | k2)) for k2 in trb_s), default=0))
    disp_out[t] = {"n_test": len(te), "test_binder_frac": round(float(np.mean([r["is_binder"] for r in te])), 3),
                   "train_binder_frac": round(float(np.mean([r["is_binder"] for r in tr])), 3) if tr else None,
                   "test_seq_also_in_train": ov, "median_max_3mer_jaccard_test_binder_to_train_binders(sampled)": round(float(np.median(mj)), 3) if mj else None,
                   "frac_test_binders_jaccard_ge_0.5": round(float(np.mean(np.array(mj) >= 0.5)), 3) if mj else None}
out["display_split"] = disp_out
out["display_train_target_features_distinct_vectors"] = len({tuple(np.round(v, 4)) for v in tfeats.values()})
out["note_target_conditioning"] = "target prefix = 24-d composition descriptor of the target protein; only %d distinct values are ever seen in training" % len(tfeats)
json.dump(out, open(sys.argv[1], "w"), indent=1); print(json.dumps(out, indent=1))
