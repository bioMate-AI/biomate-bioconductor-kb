"""Pilot 5 scoring. Reuses pilot 4's metric/baseline functions (p4eval.spear, ranks_metrics, corr, gp_post) and its reveal protocol (permutation seed = crc32(target) + 7919*seed; hard stratum = bottom tercile of max-Tanimoto to the revealed set)."""
import os, sys, zlib, numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p5common as C
import p5metrics as E
P = C.P
QS = (1, 3, 6); LAMS = (0.3, 1.0, 3.0); N0G = (0.5, 1, 2, 4, 8, 16); GPG = [(s, n) for s in (1.0, 2.25) for n in (0.09, 0.25, 0.64)]
KS_SEL = (3, 5, 10)


def gpname(g): return f"gp_{g[0]}_{g[1]}"


class TC:
    def __init__(s, tk, W):
        v = W["T"][tk]; s.tk, s.idx, s.p, s.fam, s.n = tk, v["idx"], v["p"], v["fam"], len(v["p"])
        X = W["X"][s.idx]; s.S = P.tanimoto(X, X); s.zs = zlib.crc32(tk.encode()); s.gain = s.p - s.p.min()


def reveal(tc, seed, k):
    perm = np.random.default_rng(tc.zs + 7919 * seed).permutation(tc.n); return perm[:k], perm[k:]


def scores(tc, prior_all, sig_p, rev, qry, grid=True):
    """all methods for one (target, reveal). prior_all = prior predictions over all compounds (z units)."""
    k = len(rev); pq = prior_all[tc.idx][qry]; out = {"prior": pq}
    if k == 0: return out
    ps = prior_all[tc.idx][rev]; yS = tc.p[rev]; Sqs = tc.S[np.ix_(qry, rev)]; Sss = tc.S[np.ix_(rev, rev)]
    for q in QS: w = Sqs ** q; out[f"nn_q{q}"] = (w @ yS) / np.maximum(w.sum(1), 1e-9) + 1e-3 * Sqs.max(1)
    for g in GPG: out[gpname(g)] = E.gp_post(Sss, Sqs, yS, sig2=g[0], noise=g[1])[0]
    for q in QS:
        for lam in LAMS: out[f"d_q{q}_l{lam}"] = E.corr(pq, ps, yS, Sqs, q, lam)
    if grid:
        shifted = yS.mean() + sig_p * (pq - ps.mean())
        for g in GPG:
            for n0 in N0G: w0 = n0 / (n0 + k); out[f"h5_{gpname(g)}_n{n0}"] = w0 * shifted + (1 - w0) * out[gpname(g)]
        for q in QS:
            for n0 in N0G: w0 = n0 / (n0 + k); out[f"h5nn_q{q}_n{n0}"] = w0 * shifted + (1 - w0) * out[f"nn_q{q}"]
    return out


def eval_target(tc, prior_all, sig_p, seeds, ks, want=None, full=False, p_override=None):
    p_old, g_old = tc.p, tc.gain
    if p_override is not None: tc.p = p_override; tc.gain = tc.p - tc.p.min()
    rec = []
    for seed in seeds:
        for k in ks:
            if k == 0 and seed > 0: continue
            if tc.n - k < 10: continue
            rev, qry = reveal(tc, seed, k); truth = tc.p[qry]; gain = tc.gain[qry]; sc = scores(tc, prior_all, sig_p, rev, qry)
            hard = None
            if k >= 1:
                ms = tc.S[np.ix_(qry, rev)].max(1); hard = ms <= np.quantile(ms, 1 / 3)
                if hard.sum() < 5: hard = None
            for nm, v in sc.items():
                if want is not None and nm not in want: continue
                v = np.asarray(v, float)
                if full: a = E.ranks_metrics(v, truth, gain); b = E.ranks_metrics(v[hard], truth[hard], gain[hard]) if hard is not None else (np.nan,) * 3
                else: a = (E.spear(v, truth), np.nan, np.nan); b = (E.spear(v[hard], truth[hard]) if hard is not None else np.nan, np.nan, np.nan)
                rec.append((tc.tk, tc.fam, nm, k, seed, a[0], a[1], a[2], b[0], b[1], b[2], len(qry)))
    tc.p, tc.gain = p_old, g_old
    return rec


COLS = ["target", "family", "method", "k", "seed", "sp", "ndcg", "rec", "sp_h", "ndcg_h", "rec_h", "nq"]


def famtab(df, col):
    return df.groupby(["method", "k", "family", "target"])[col].mean().groupby(["method", "k", "family"]).mean()


def select(df, col="sp_h"):
    """nested selection on inner-validation records (training families only): objective = mean over k in KS_SEL of the family-equal mean hard-stratum Spearman.
    NN: best q; GP: best (sig2, noise); d: best (q, lam); H5: best n0 given the selected GP; H5NN: best n0 given the selected NN q."""
    t = famtab(df, col); obj = {}
    for m in t.index.get_level_values(0).unique():
        ks = [k for k in KS_SEL if (m, k) in t.index.droplevel(2)]
        if len(ks) == len(KS_SEL): obj[m] = float(np.mean([t.loc[(m, k)].mean() for k in KS_SEL]))
    nn = max((f"nn_q{q}" for q in QS), key=lambda m: obj[m]); gp = max((gpname(g) for g in GPG), key=lambda m: obj[m])
    d = max((f"d_q{q}_l{lam}" for q in QS for lam in LAMS), key=lambda m: obj[m])
    h5 = max((f"h5_{gp}_n{n0}" for n0 in N0G), key=lambda m: obj[m]); h5nn = max((f"h5nn_{nn[3:]}_n{n0}" for n0 in N0G), key=lambda m: obj[m])
    return dict(nn=nn, gp=gp, d=d, h5=h5, h5nn=h5nn), obj
