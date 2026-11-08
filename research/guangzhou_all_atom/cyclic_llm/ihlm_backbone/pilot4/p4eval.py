"""Pilot 4 evaluation: learning curves (k = 0,1,3,5,10,25), nested reveals, family-disjoint fold models, hard stratum = bottom tercile of max-similarity to the revealed set.
usage: python3 p4eval.py dev|test [OUT]   (dev = sha256(family) mod 2 == 0 ; test = 1). Stage discipline: test is run only after the A1 commit."""
import os, sys, time, pickle, zlib, numpy as np, pandas as pd, torch
from scipy.stats import rankdata
from sklearn.ensemble import RandomForestRegressor
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p4common as P, p4models as M
import __main__ as _mn; _mn.MLPPrior = M.MLPPrior; _mn.Meta = M.Meta        # fold pickles were written by `python p4models.py` (classes pickled under __main__)
RES = M.RES; KS = (0, 1, 3, 5, 10, 25); SEEDS = list(range(10)); QS = (1, 3, 6); LAMS = (0.3, 1.0, 3.0); ALPHAS = (10, 100, 1000)


def spear(a, b):
    if np.ptp(a) == 0 or np.ptp(b) == 0: return 0.0
    ra, rb = rankdata(a), rankdata(b); ra -= ra.mean(); rb -= rb.mean(); d = np.sqrt((ra * ra).sum() * (rb * rb).sum()); return float((ra * rb).sum() / d) if d > 0 else 0.0


def ranks_metrics(pred, truth, gain):
    nq = len(truth); order = np.argsort(-pred, kind="stable"); ntop = max(1, int(np.ceil(0.1 * nq)))
    ideal = np.sort(gain)[::-1][:10]; disc = 1.0 / np.log2(np.arange(2, 2 + min(10, nq)))
    ndcg = float((gain[order[:10]] * disc).sum() / max((ideal * disc).sum(), 1e-9))
    tt = set(np.argsort(-truth, kind="stable")[:ntop]); rec = len(tt & set(order[:ntop])) / ntop
    return spear(pred, truth), ndcg, rec


def corr(prior_q, prior_s, y_s, Sqs, q, lam, b=1.0):
    r = (y_s - y_s.mean()) - b * (prior_s - prior_s.mean()); w = Sqs ** q
    return b * prior_q + (w @ r) / (w.sum(1) + lam)


def gp_post(Sss, Sqs, y, sig2=1.5 ** 2, noise=0.5 ** 2, mean0=7.5):
    m = y.mean(); K = sig2 * Sss + noise * np.eye(len(y)); Kq = sig2 * Sqs
    try: mu = m + Kq @ np.linalg.solve(K, y - m); v = sig2 - np.einsum("ij,ji->i", Kq, np.linalg.solve(K, Kq.T))
    except np.linalg.LinAlgError: mu = np.full(Sqs.shape[0], m); v = np.full(Sqs.shape[0], sig2)
    return mu, np.sqrt(np.clip(v, 1e-6, None))


class Target:
    """precomputed per-target quantities for one fold model set."""
    def __init__(s, tk, W, T, FM):
        v = T[tk]; s.tk = tk; s.fam = v["fam"]; s.idx = v["idx"]; s.p = v["p"]; s.n = len(s.p); X = W["X"][s.idx]; s.X = X
        s.S = P.tanimoto(X, X); M_ = FM["M"]
        s.gain = s.p - s.p.min()
        mu_e, sd_e = M_["emb_stats"]; Es = (W["Em"][s.idx] - mu_e) / sd_e; nrm = np.linalg.norm(Es, axis=1, keepdims=True) + 1e-9; s.cos = np.clip((Es / nrm) @ (Es / nrm).T, 0, 1)
        s.Sg = 0.5 * s.S + 0.5 * s.cos
        s.prior = {"hgb": M_["hgb"].predict(X)}
        for a, r in M_["ridge"].items(): s.prior[f"ridge{a}"] = r.predict(Es)
        Xt = torch.from_numpy(X)
        with torch.no_grad():
            s.prior["h0"] = M_["h0"](Xt).numpy(); s.prior["h1"] = M_["h1"](Xt).numpy()
            s.meta = {}
            for nm in ("f0", "f1"):
                for ck, sd in M_[nm].items():
                    m = M.meta_from_state(sd); e, g = m.embed(Xt); s.meta[(nm, ck)] = (m, e, g)

    def scores(s, rev, qry):
        """-> dict method -> score vector over qry; rev = revealed positions (may be empty)."""
        out = {}; k = len(rev); yS = s.p[rev] if k else np.zeros(0)
        Sqs = s.S[np.ix_(qry, rev)] if k else None
        out["prior_hgb"] = s.prior["hgb"][qry]
        for a in ALPHAS: out[f"prior_ridge{a}"] = s.prior[f"ridge{a}"][qry]
        out["prior_h0"] = s.prior["h0"][qry]; out["prior_h1"] = s.prior["h1"][qry]
        for (nm, ck), (m, e, g) in s.meta.items():
            if k == 0: out[f"{nm}_{ck}"] = g.numpy()[qry]
            else:
                with torch.no_grad():
                    mu = m.predict(e[rev][None], g[rev][None], torch.from_numpy(yS - yS.mean()).float()[None] + 0.0, e[qry][None], g[qry][None])[0].numpy()
                out[f"{nm}_{ck}"] = mu
        if k == 0: return out
        for q in QS: w = Sqs ** q; out[f"nn_q{q}"] = (w @ yS) / np.maximum(w.sum(1), 1e-9) + 1e-3 * Sqs.max(1)
        mu, sd = gp_post(s.S[np.ix_(rev, rev)], Sqs, yS); out["gp"] = mu
        if k >= 2: out["rf"] = None                                    # filled by caller (needs seed)
        for q in QS:
            for lam in LAMS: out[f"d_q{q}_l{lam}"] = corr(s.prior["hgb"][qry], s.prior["hgb"][rev], yS, Sqs, q, lam)
        Sg = s.Sg[np.ix_(qry, rev)]
        for a in ALPHAS:
            for q in QS:
                for lam in LAMS: out[f"g_a{a}_q{q}_l{lam}"] = corr(s.prior[f"ridge{a}"][qry], s.prior[f"ridge{a}"][rev], yS, Sg, q, lam)
        out["dh0"] = corr(s.prior["h0"][qry], s.prior["h0"][rev], yS, Sqs, 3, 1.0); out["dh1"] = corr(s.prior["h1"][qry], s.prior["h1"][rev], yS, Sqs, 3, 1.0)
        return out


def eval_target(tk, W, T, FM, ks=KS, seeds=SEEDS, p_override=None, t=None):
    t = t or Target(tk, W, T, FM); p_old, g_old = t.p, t.gain
    if p_override is not None: t.p = p_override; t.gain = t.p - t.p.min()
    rec = []; zs = zlib.crc32(tk.encode())
    for seed in seeds:
        perm = np.random.default_rng(zs + 7919 * seed).permutation(t.n)
        for k in ks:
            if k == 0 and seed > 0: continue
            if t.n - k < 10: continue
            rev = perm[:k]; qry = perm[k:]; truth = t.p[qry]; gain = t.gain[qry]
            sc = t.scores(rev, qry)
            if k >= 2:
                rf = RandomForestRegressor(n_estimators=200, n_jobs=1, random_state=seed).fit(t.X[rev], t.p[rev]); sc["rf"] = rf.predict(t.X[qry])
            hard = None
            if k >= 1:
                ms = t.S[np.ix_(qry, rev)].max(1); hard = ms <= np.quantile(ms, 1 / 3)
                if hard.sum() < 5: hard = None
            for nm, v in sc.items():
                if v is None: continue
                a = ranks_metrics(np.asarray(v, float), truth, gain)
                b = ranks_metrics(np.asarray(v, float)[hard], truth[hard], gain[hard]) if hard is not None else (np.nan,) * 3
                rec.append((tk, t.fam, nm, k, seed, a[0], a[1], a[2], b[0], b[1], b[2], len(qry)))
    t.p, t.gain = p_old, g_old
    return rec


def run(half, out, jobs=int(os.environ.get("JOBS", "4"))):
    from joblib import Parallel, delayed
    W = M.load_world(); T = M.target_table(W); fmap = W["fmap"]; elig = sorted(W["elig"]); fam = W["fam"]
    tg = [tk for tk in elig if P.split_half(fam[tk]) == (0 if half == "dev" else 1)]
    byfold = {}
    for tk in tg: byfold.setdefault(fmap[fam[tk]], []).append(tk)
    print(half, len(tg), "targets in", len(set(fam[tk] for tk in tg)), "families; folds", {f: len(v) for f, v in byfold.items()}, flush=True)
    allrec = []; t0 = time.time()
    for f, tks in sorted(byfold.items()):
        FM = pickle.load(open(f"{RES}/fold{f}.pkl", "rb"))
        res = Parallel(n_jobs=jobs, prefer="threads")(delayed(eval_target)(tk, W, T, FM) for tk in tks)
        for r in res: allrec += r
        print("fold", f, len(tks), "targets done", round(time.time() - t0), "s", flush=True)
    df = pd.DataFrame(allrec, columns=["target", "family", "method", "k", "seed", "sp", "ndcg", "rec", "sp_h", "ndcg_h", "rec_h", "nq"])
    df.to_pickle(out); df.to_csv(out.replace(".pkl", ".csv.gz"), index=False); print("saved", out, len(df))


if __name__ == "__main__":
    half = sys.argv[1]; run(half, sys.argv[2] if len(sys.argv) > 2 else f"{RES}/eval_{half}.pkl")
