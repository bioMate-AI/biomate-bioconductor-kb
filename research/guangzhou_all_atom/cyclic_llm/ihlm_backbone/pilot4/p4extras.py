"""Pilot 4 stage-2 extras (run only after the A1 commit): iterative active-learning replay, controls C1/C2 (planted / shuffled), censor controls C4 + leakage L1, diagnostic S3.
usage: python3 p4extras.py RESDIR   (reads RESDIR/frozen_config.json written at A1)"""
import os, sys, json, math, zlib, time, pickle, numpy as np, pandas as pd, torch
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p4common as P, p4models as M
import __main__ as _mn; _mn.MLPPrior = M.MLPPrior; _mn.Meta = M.Meta        # fold pickles were written by `python p4models.py` (classes pickled under __main__)
import p4eval as E
from scipy.stats import rankdata
RES = sys.argv[1] if len(sys.argv) > 1 else M.RES
CFG = json.load(open(f"{RES}/frozen_config.json")) if os.path.exists(f"{RES}/frozen_config.json") else dict(nn_q=3, d=[3, 1.0], g=[100, 3, 1.0], f_ck=3000)
W = M.load_world(); T = M.target_table(W); C = M.censored_table(W); fmap = W["fmap"]; fam = W["fam"]
test_t = [tk for tk in sorted(W["elig"]) if P.split_half(fam[tk]) == 1]
FMc = {}
def FM(f):
    if f not in FMc: FMc[f] = pickle.load(open(f"{RES}/fold{f}.pkl", "rb"))
    return FMc[f]
NAMES = dict(nn=f"nn_q{CFG['nn_q']}", d=f"d_q{CFG['d'][0]}_l{CFG['d'][1]}", g=f"g_a{CFG['g'][0]}_q{CFG['g'][1]}_l{CFG['g'][2]}", f=f"f0_{CFG['f_ck']}")


def al_target(tk, seeds=5, k0=3, rounds=5, per=5):
    t = E.Target(tk, W, T, FM(fmap[fam[tk]])); n = t.n; ntop = max(3, int(math.ceil(0.1 * n))); top = set(np.argsort(-t.p, kind="stable")[:ntop]); out = []
    for seed in range(seeds):
        rng = np.random.default_rng(zlib.crc32(tk.encode()) + 104729 * seed); perm = rng.permutation(n)
        for method in ("random", "nn", "gp_ucb", "d", "f", "g"):
            rev = list(perm[:k0]); r2 = np.random.default_rng(seed + 17)
            for _ in range(rounds):
                qry = np.array([i for i in range(n) if i not in set(rev)])
                if method == "random": sc = r2.random(len(qry))
                elif method == "gp_ucb":
                    mu, sd = E.gp_post(t.S[np.ix_(rev, rev)], t.S[np.ix_(qry, rev)], t.p[rev]); sc = mu + 1.0 * sd
                else: sc = t.scores(np.array(rev), qry)[NAMES[method]]
                rev += list(qry[np.argsort(-sc, kind="stable")[:per]])
            out.append((tk, fam[tk], method, seed, len(top & set(rev)) / ntop, (k0 + rounds * per) / n))
    return out


def planted(tk, seed=0):
    t = E.Target(tk, W, T, FM(fmap[fam[tk]])); rng = np.random.default_rng(zlib.crc32(tk.encode()) + seed); cs = rng.choice(t.n, 3, replace=False)
    return 5 + 4 * t.S[:, cs].mean(1) + rng.normal(0, 0.3, t.n)


def controls_one(tk, keep):
    rows = []; FMf = FM(fmap[fam[tk]]); t = E.Target(tk, W, T, FMf)
    rng = np.random.default_rng(zlib.crc32(tk.encode())); cs = rng.choice(t.n, 3, replace=False); pl = 5 + 4 * t.S[:, cs].mean(1) + rng.normal(0, 0.3, t.n)
    rows += [("planted",) + r for r in E.eval_target(tk, W, T, FMf, ks=(10,), seeds=list(range(5)), p_override=pl, t=t) if r[2] in keep]
    for rseed in range(10):
        ps = np.random.default_rng(zlib.crc32(tk.encode()) + 31 * rseed + 5).permutation(T[tk]["p"])
        rows += [("shuffled",) + r for r in E.eval_target(tk, W, T, FMf, ks=(3, 5, 10), seeds=[0], p_override=ps, t=t) if r[2] in keep]
    return rows


def controls():
    from joblib import Parallel, delayed
    keep = {NAMES["nn"], "gp", "prior_hgb", NAMES["d"], NAMES["g"], NAMES["f"], "prior_h0", "prior_h1"}
    res = Parallel(n_jobs=int(os.environ.get("JOBS", "4")), prefer="threads")(delayed(controls_one)(tk, keep) for tk in test_t); rows = [r for x in res for r in x]
    return pd.DataFrame(rows, columns=["control", "target", "family", "method", "k", "seed", "sp", "ndcg", "rec", "sp_h", "ndcg_h", "rec_h", "nq"])


def c4_leak(fold=0, epochs=30):
    """planted censoring world: global planted potency with a 'dead' chemotype; lowest 30 % per training target censored. held-out fold targets fully observed."""
    rng = np.random.default_rng(123); X = W["X"]; w = np.zeros(P.NB); w[rng.choice(P.NB, 60, replace=False)] = rng.normal(0, 1, 60); U = rng.choice(P.NB, 40, replace=False)
    base = X @ w; base = (base - base.mean()) / base.std(); dead = (X[:, U].sum(1) > 0).astype(float)
    pl = 6 + 1.5 * base - 3 * dead + rng.normal(0, 0.3, len(base))
    rows0, _ = M.train_rows(W, T, fold, None); Tt = {tk: dict(idx=W_idx, p=None) for tk, W_idx, _ in rows0}
    ex_rows, Ct = [], {}
    for tk, idx, _ in rows0:
        p = pl[idx]; q30 = np.quantile(p, 0.3); keepm = p > q30; mu, sd = p[keepm].mean(), max(p[keepm].std(), 0.5)
        ex_rows.append((tk, idx[keepm], (p[keepm] - mu) / sd)); Ct[tk] = dict(idx=idx[~keepm], c=np.full((~keepm).sum(), (q30 - mu) / sd), type=np.ones((~keepm).sum(), int))
    res = {}
    def fit(name, censored, Ct_use):
        torch.manual_seed(0); return M.train_mlp_prior(X, ex_rows, Ct_use, censored, epochs=epochs)
    h0 = fit("h0", False, Ct); h1 = fit("h1", True, Ct)
    perm_flags = {tk: dict(v, type=np.random.default_rng(5).permutation(v["type"]) * 0 + np.random.default_rng(6).integers(1, 3, len(v["type"]))) for tk, v in Ct.items()}
    h1p = fit("h1p", True, perm_flags)                                         # flags scrambled: '<' vs '>' random while bounds stay
    h0b = fit("h0b", False, perm_flags)
    fams_f = {fa for fa, k in fmap.items() if k == fold}; tg = [tk for tk in sorted(W["elig"]) if fam[tk] in fams_f]
    def ev(m):
        sp, bias = [], []
        for tk in tg:
            idx = T[tk]["idx"]; truth = pl[idx]; pr = m(torch.from_numpy(X[idx])).detach().numpy(); sp.append(E.spear(pr, truth))
            rk = rankdata(pr) / len(pr); low = truth <= np.quantile(truth, 0.1); bias.append(float(rk[low].mean()))
        return float(np.mean(sp)), float(np.mean(bias))
    for nm, m in (("h0", h0), ("h1", h1), ("h1_scrambled_flags", h1p), ("h0_scrambled_ct_arg", h0b)): res[nm] = dict(zip(("spearman", "mean_rank_pct_of_true_bottom_decile"), ev(m)))
    p0 = h0(torch.from_numpy(X[:500])).detach().numpy(); p0b = h0b(torch.from_numpy(X[:500])).detach().numpy()
    res["h0_identical_when_censor_arg_permuted"] = bool(np.array_equal(p0, p0b))
    res["n_targets_eval"] = len(tg); res["n_train_targets"] = len(ex_rows)
    res["pass_gain>=0.03"] = bool(res["h1"]["spearman"] - res["h0"]["spearman"] >= 0.03); res["pass_bias"] = bool(res["h0"]["mean_rank_pct_of_true_bottom_decile"] > res["h1"]["mean_rank_pct_of_true_bottom_decile"])
    res["scrambled_flags_gain_lost"] = bool(res["h1_scrambled_flags"]["spearman"] < res["h1"]["spearman"])
    import inspect; res["train_mlp_prior_signature"] = str(inspect.signature(M.train_mlp_prior)); res["feature_matrix_only"] = "X[idx]" in inspect.getsource(M.train_mlp_prior)
    return res


def s3_diag():
    from sklearn.metrics import roc_auc_score
    rows = []
    for tk in test_t:
        if tk not in C: continue
        cv = C[tk]; neg = cv["idx"][cv["type"] == 1]; v = T[tk]; pos = v["idx"][v["p"] >= 7]
        if len(neg) < 3 or len(pos) < 3: continue
        FMf = FM(fmap[fam[tk]])["M"]; idx = np.concatenate([neg, pos]); y = np.r_[np.zeros(len(neg)), np.ones(len(pos))]; Xt = torch.from_numpy(W["X"][idx])
        with torch.no_grad(): sc = dict(hgb=FMf["hgb"].predict(W["X"][idx]), h0=FMf["h0"](Xt).numpy(), h1=FMf["h1"](Xt).numpy())
        for nm, s_ in sc.items(): rows.append((tk, fam[tk], nm, len(neg), len(pos), float(roc_auc_score(y, s_))))
    return pd.DataFrame(rows, columns=["target", "family", "prior", "n_neg", "n_pos", "auroc"])


if __name__ == "__main__":
    t0 = time.time(); print("config", NAMES, flush=True)
    from joblib import Parallel, delayed
    for f in range(6): FM(f)
    al = [r for x in Parallel(n_jobs=int(os.environ.get("JOBS", "4")), prefer="threads")(delayed(al_target)(tk) for tk in test_t) for r in x]
    pd.DataFrame(al, columns=["target", "family", "method", "seed", "yield", "frac_labelled"]).to_csv(f"{RES}/al_test.csv.gz", index=False); print("AL done", round(time.time() - t0), "s", flush=True)
    controls().to_csv(f"{RES}/controls_test.csv.gz", index=False); print("controls done", round(time.time() - t0), "s", flush=True)
    json.dump(c4_leak(), open(f"{RES}/c4_leak.json", "w"), indent=1); print("c4 done", round(time.time() - t0), "s", flush=True)
    s3_diag().to_csv(f"{RES}/s3_diag.csv.gz", index=False); print("s3 done", round(time.time() - t0), "s", flush=True)
