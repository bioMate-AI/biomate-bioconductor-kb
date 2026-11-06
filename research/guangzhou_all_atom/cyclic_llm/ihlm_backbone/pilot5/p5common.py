"""Pilot 5 shared layer (prior-to-lookup handoff, full family cross-validation). Reuses pilot 4's data layer (p4common) unchanged; no torch needed.
Everything here is label-dependent only through the declared training rows (training families of each fold) and the eligibility rule (n_exact >= 30, SD(pAct) >= 0.5)."""
import os, sys, zlib, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); P4 = os.path.abspath(f"{HERE}/../pilot4"); RES = f"{HERE}/results"
sys.path.insert(0, P4)
import p4common as P
K_OUT, N_INNER, N_REP = 10, 3, 20


def world(fp_path=None):
    ex, c, elig, fam = P.load()
    cid = c.compound_id.values; cidx = {x: i for i, x in enumerate(cid)}
    X = np.load(fp_path or f"{P4}/results/fp.npy")
    T = {}
    for tk, g in ex.groupby("target_key"):
        T[tk] = dict(idx=np.array([cidx[x] for x in g.compound_id]), p=g.p.values.astype(np.float64), fam=g.family.iloc[0])
    elig = sorted(elig)
    return dict(T=T, X=X, elig=elig, fam=fam, n_comp=len(cid))


def fam_counts(W):
    return W["fam"].loc[W["elig"]].value_counts()


def _greedy(counts, K, rng, jitter=0.3):
    """balanced greedy assignment of families to K groups by number of eligible targets; sizes jittered (x U(1-j,1+j)) to vary the assignment across repeats."""
    fams = sorted(counts.index, key=lambda f: (-int(counts[f]), str(f))); sz = np.array([counts[f] for f in fams], float)   # deterministic tie order (pilot 4's p4common.folds depends on unstable sort order of tied counts)
    key = sz * rng.uniform(1 - jitter, 1 + jitter, len(fams)); order = np.argsort(-key, kind="stable"); load = [0.0] * K; out = {}
    for i in order:
        k = int(np.argmin(load)); out[fams[i]] = k; load[k] += sz[i]
    return out


def assign_outer(W, r, K=K_OUT):
    return _greedy(fam_counts(W), K, np.random.default_rng(1000 + r))


def assign_inner(W, r, f, fmap, n_inner=N_INNER):
    cnt = fam_counts(W); cnt = cnt[[fa for fa in cnt.index if fmap[fa] != f]]
    return _greedy(cnt, n_inner, np.random.default_rng(5000 + 100 * r + f))


def train_rows(W, hold_fams):
    """training targets = every target (eligible or not) whose family is not held out and with n_exact >= 10; z per target from its exact rows, SD floor 0.5 (identical to pilot 4 train_rows)."""
    idx, z = [], []
    for tk, v in W["T"].items():
        if v["fam"] in hold_fams or len(v["p"]) < 10: continue
        mu, sd = v["p"].mean(), max(v["p"].std(), 0.5); idx.append(v["idx"]); z.append((v["p"] - mu) / sd)
    return np.concatenate(idx), np.concatenate(z)


def sigma_p(W, hold_fams):
    """potency scale of the target-agnostic prior: median SD (log10 units) of the training targets' exact potencies (training families only)."""
    return float(np.median([v["p"].std() for v in W["T"].values() if v["fam"] not in hold_fams and len(v["p"]) >= 10]))


def fit_prior(W, hold_fams):
    from sklearn.ensemble import HistGradientBoostingRegressor
    idx, z = train_rows(W, hold_fams)
    h = HistGradientBoostingRegressor(max_iter=200, learning_rate=0.1, max_leaf_nodes=31, l2_regularization=1.0, early_stopping=False, random_state=0).fit(W["X"][idx], z)
    return h.predict(W["X"])
