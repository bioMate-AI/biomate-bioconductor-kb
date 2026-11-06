"""Pilot 4 identity test (errata 2): the committed fold map (fold_map.json, read by p4common.folds) is the assignment actually used.
 1. sha256 of fold_map.json matches fold_map.sha256.
 2. For all 141 eligible targets exactly one saved fold pickle reproduces the saved prior_hgb k=0 Spearman (|diff|<1e-9) and it is the pickle the file map assigns to the target's family (and has the lowest in-sample fit of the six).
 3. Training counts (n_train_targets, n_exact, n_cens) recomputed under the file map equal those stored in all six pickles; no fold-f held-out eligible target (or same-family target) is in fold-f training.
 4. Numerical identity: for one target per fold, eval_target (all k, seeds 0-2) recomputed with the file map equals the saved evaluation rows (eval_dev/eval_test csv) to 1e-6 (max abs difference reported per metric; sklearn/torch builds differ between the spot instance and this machine).
usage: python3 p4foldidentity.py OUT.json"""
import os, sys, json, hashlib, pickle, numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p4common as P, p4models as M
import __main__ as _mn; _mn.MLPPrior = M.MLPPrior; _mn.Meta = M.Meta
import p4eval as E
from scipy.stats import spearmanr
RES = M.RES


def main(out):
    r = {}
    raw = open(P.FOLD_MAP, "rb").read(); r["sha256_matches"] = hashlib.sha256(raw).hexdigest() == open(os.path.join(P.HERE, "fold_map.sha256")).read().split()[0]; r["sha256"] = hashlib.sha256(raw).hexdigest()
    W = M.load_world(); T = M.target_table(W); fam = W["fam"]; elig = sorted(W["elig"]); fmap = W["fmap"]   # fmap now comes from the file
    FMs = [pickle.load(open(f"{RES}/fold{f}.pkl", "rb")) for f in range(6)]
    ev = pd.concat([pd.read_csv(f"{RES}/eval_dev.csv.gz"), pd.read_csv(f"{RES}/eval_test.csv.gz")]); saved = ev[(ev.method == "prior_hgb") & (ev.k == 0)].groupby("target").sp.first()
    one = agree = lowest = 0
    for tk in elig:
        idx = T[tk]["idx"]; p = T[tk]["p"]; X = W["X"][idx]; fits = [float(spearmanr(FMs[f]["M"]["hgb"].predict(X), p)[0]) for f in range(6)]
        m = [f for f in range(6) if abs(fits[f] - saved[tk]) < 1e-9]; one += len(m) == 1
        if len(m) == 1: agree += m[0] == fmap[fam[tk]]; lowest += fits[m[0]] == min(fits)
    r["pickle_match"] = dict(n_targets=len(elig), exactly_one_pickle=int(one), equals_file_map=int(agree), matching_pickle_has_lowest_fit=int(lowest))
    C = M.censored_table(W); cnt_ok = True; leak = bad = 0; cnts = []
    for f in range(6):
        rws, Ct = M.train_rows(W, T, f, C); a = (len(rws), sum(len(x[1]) for x in rws), sum(len(v["idx"]) for v in Ct.values())); b = (FMs[f]["n_train_targets"], FMs[f]["n_exact"], FMs[f]["n_cens"]); cnt_ok &= a == b; cnts.append(dict(fold=f, recomputed=a, pickle=b))
        trained = {x[0] for x in rws}; hold = {fam[tk] for tk in elig if fmap[fam[tk]] == f}
        leak += sum(1 for tk in elig if fmap[fam[tk]] == f and tk in trained); bad += sum(1 for tk in trained if T[tk]["fam"] in hold)
    r["training_counts_equal_pickles"] = bool(cnt_ok); r["training_counts"] = cnts; r["heldout_targets_in_own_fold_training"] = int(leak); r["training_targets_sharing_family_with_heldout"] = int(bad)
    tg = [min([t for t in elig if fmap[fam[t]] == f], key=lambda t: T[t]["p"].shape[0]) for f in range(6)]; cols = ["sp", "ndcg", "rec", "sp_h", "ndcg_h", "rec_h"]; worst = {c: 0.0 for c in cols}; nrows = 0; keys_missing = 0
    for tk in tg:
        FM = FMs[fmap[fam[tk]]]; new = pd.DataFrame(E.eval_target(tk, W, T, FM, seeds=[0, 1, 2]), columns=["target", "family", "method", "k", "seed"] + cols + ["nq"])
        old = ev[(ev.target == tk) & (ev.seed.isin([0, 1, 2]))].drop_duplicates(["method", "k", "seed"]); mg = new.merge(old, on=["method", "k", "seed"], suffixes=("_n", "_o"), how="left"); keys_missing += int(mg[cols[0] + "_o"].isna().sum()); nrows += len(mg)
        for c in cols:
            d = (mg[c + "_n"] - mg[c + "_o"]).abs(); worst[c] = max(worst[c], float(np.nanmax(d.values)))
    r["numerical_identity"] = dict(targets=tg, rows_compared=nrows, rows_missing_in_saved=keys_missing, max_abs_diff=worst, PASS=bool(keys_missing == 0 and max(worst.values()) < 1e-6))
    r["IDENTITY_PASS"] = bool(r["sha256_matches"] and one == len(elig) and agree == len(elig) and cnt_ok and leak == 0 and bad == 0 and r["numerical_identity"]["PASS"])
    json.dump(r, open(out, "w"), indent=1); print(json.dumps({k: v for k, v in r.items() if k != "training_counts"}, indent=1))


if __name__ == "__main__": main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(RES, "fold_identity.json"))
