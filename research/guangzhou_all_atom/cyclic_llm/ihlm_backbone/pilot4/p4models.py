"""Pilot 4 models: per-fold training of everything that uses other targets (family-disjoint). Hyper-settings are those fixed in the pre-registration (docs/20261031_NEWTARGET_FEWSHOT_PILOT4_PREREG.md)."""
import os, sys, pickle, time, numpy as np, pandas as pd, torch, torch.nn as nn
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.linear_model import Ridge
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p4common as P
HERE = P.HERE; RES = f"{HERE}/results"
torch.set_num_threads(int(os.environ.get("NT", "4")))


def load_world():
    ex, c, elig, fam = P.load()
    d = pd.read_csv(f"{P.RR}/pair_labels.csv.gz"); t = pd.read_csv(f"{P.RR}/targets_v2.csv")
    d = d.merge(t[["target_key", "family"]], on="target_key", how="left")
    cid = c.compound_id.values; cidx = {x: i for i, x in enumerate(cid)}
    fpz = f"{RES}/fp.npy"
    if os.path.exists(fpz): X = np.load(fpz)
    else: X = P.fingerprints(c.iso_smiles.values); np.save(fpz, X)
    z = np.load(f"{RES}/emb_small.npz", allow_pickle=True); assert (z["compound_id"] == cid).all(); Em = z["E"].astype(np.float32)
    fmap, _ = P.folds(elig, fam)
    return dict(ex=ex, d=d, c=c, elig=set(elig), fam=fam, cidx=cidx, X=X, Em=Em, fmap=fmap)


def target_table(W):
    """exact rows per target: idx (compound row), p (pActivity)."""
    T = {}
    for tk, g in W["ex"].groupby("target_key"):
        T[tk] = dict(idx=np.array([W["cidx"][c] for c in g.compound_id]), p=g.p.values.astype(np.float64), fam=g.family.iloc[0])
    return T


def censored_table(W):
    """pure censored rows: '>' (nM greater than bound => pAct < c, type 1) and '<' (pAct > c, type 2), bound c in pAct units."""
    d = W["d"]; r = d[d.relations.astype(str).isin([">", "<"])].copy()
    r["c"] = -np.log10(r.value_nM.astype(float) * 1e-9); r["type"] = (r.relations.astype(str) == "<").astype(int) + 1
    C = {}
    for tk, g in r.groupby("target_key"):
        C[tk] = dict(idx=np.array([W["cidx"][x] for x in g.compound_id]), c=g.c.values.astype(np.float64), type=g.type.values, fam=g.family.iloc[0])
    return C


def train_rows(W, T, f, C=None):
    """training targets for fold f: family not in the fold's family set, n_exact >= 10. z per target from its exact rows (SD floor 0.5)."""
    fams_f = {fa for fa, k in W["fmap"].items() if k == f}
    rows = []; Ct = {}
    for tk, v in T.items():
        if v["fam"] in fams_f or len(v["p"]) < 10: continue
        mu, sd = v["p"].mean(), max(v["p"].std(), 0.5)
        rows.append((tk, v["idx"], (v["p"] - mu) / sd))
        if C is not None and tk in C:
            cz = (C[tk]["c"] - mu) / sd; Ct[tk] = dict(idx=C[tk]["idx"], c=cz, type=C[tk]["type"])
    return rows, Ct


class MLPPrior(nn.Module):
    def __init__(s, d_in=P.NB, h=256):
        super().__init__(); s.net = nn.Sequential(nn.Linear(d_in, h), nn.ReLU(), nn.Dropout(0.1), nn.Linear(h, 1)); s.rho = nn.Parameter(torch.tensor(0.0))
    def forward(s, x): return s.net(x).squeeze(-1)
    def sigma(s): return torch.nn.functional.softplus(s.rho + 0.5413) + 1e-3          # softplus(0.5413) ~ 0.8


def tobit_nll(mu, y, typ, sigma):
    """typ 0 exact, 1 left-censored (pAct < y), 2 right-censored (pAct > y); Gaussian."""
    nd = torch.distributions.Normal(0.0, 1.0); zq = (y - mu) / sigma
    ex = 0.5 * zq ** 2 + torch.log(sigma)
    lc = -torch.log(nd.cdf(zq).clamp_min(1e-6)); rc = -torch.log((1 - nd.cdf(zq)).clamp_min(1e-6))
    return torch.where(typ == 0, ex, torch.where(typ == 1, lc, rc))


def train_mlp_prior(X, rows, Ct, censored, seed=0, epochs=30, bs=256):
    torch.manual_seed(seed); rng = np.random.default_rng(seed)
    idx = np.concatenate([r[1] for r in rows]); y = np.concatenate([r[2] for r in rows]); typ = np.zeros(len(idx), int)
    if censored and Ct:
        ci = np.concatenate([v["idx"] for v in Ct.values()]); cy = np.concatenate([v["c"] for v in Ct.values()]); ct = np.concatenate([v["type"] for v in Ct.values()])
        idx = np.concatenate([idx, ci]); y = np.concatenate([y, cy]); typ = np.concatenate([typ, ct])
    m = MLPPrior(); opt = torch.optim.Adam(m.parameters(), 1e-3); Xt = torch.from_numpy(X)
    yt = torch.from_numpy(y).float(); tt = torch.from_numpy(typ)
    for ep in range(epochs):
        m.train(); perm = rng.permutation(len(idx))
        for b in range(0, len(perm), bs):
            ii = perm[b:b + bs]; mu = m(Xt[idx[ii]]); sg = m.sigma()
            loss = tobit_nll(mu, yt[ii], tt[ii], sg).mean() if censored else ((mu - yt[ii]) ** 2).mean()
            opt.zero_grad(); loss.backward(); opt.step()
    m.eval(); return m


class Meta(nn.Module):
    """episodic target-conditioned predictor (pre-reg 3f): embedding e(x) (2048->512->128), prior head g(x), learned scalars (b, s, tau, d0, sigma)."""
    def __init__(s):
        super().__init__(); s.enc = nn.Sequential(nn.Linear(P.NB, 512), nn.ReLU(), nn.Dropout(0.1), nn.Linear(512, 128)); s.g = nn.Linear(128, 1)
        s.b = nn.Parameter(torch.tensor(1.0)); s.s = nn.Parameter(torch.tensor(1.0)); s.ltau = nn.Parameter(torch.tensor(0.0)); s.d0 = nn.Parameter(torch.tensor(1.0)); s.rho = nn.Parameter(torch.tensor(0.0))
    def embed(s, x): e = s.enc(x); return e, s.g(e).squeeze(-1)
    def sigma(s): return torch.nn.functional.softplus(s.rho + 0.5413) + 1e-3
    def predict(s, eS, gS, yS, eQ, gQ, mS=None):
        """centered prediction for query. eS (B,k,D) gS (B,k) yS (B,k) mask mS (B,k); returns (B,q)."""
        if mS is None: mS = torch.ones_like(yS)
        n = mS.sum(1, keepdim=True).clamp_min(1); yb = (yS * mS).sum(1, keepdim=True) / n; gb = (gS * mS).sum(1, keepdim=True) / n
        r = (yS - yb) - s.b * (gS - gb)
        d2 = torch.cdist(eQ, eS) ** 2 / torch.exp(s.ltau)                       # (B,q,k)
        logit = (-d2).masked_fill(mS[:, None, :] == 0, -1e9)
        null = (-s.d0).expand(logit.shape[0], logit.shape[1], 1)
        a = torch.softmax(torch.cat([logit, null], -1), -1)[..., :-1]
        return s.b * (gQ - gb) + s.s * (a * (r * mS)[:, None, :]).sum(-1)


def train_meta(X, rows, Ct, censored, steps=3000, ckpts=(1000, 3000), seed=0, B=32, KS=(1, 3, 5, 10, 25), NQ=64, NCQ=16):
    torch.manual_seed(seed); rng = np.random.default_rng(seed); m = Meta(); opt = torch.optim.Adam(m.parameters(), 1e-3); Xt = torch.from_numpy(X)
    tt = [r for r in rows if len(r[1]) >= 12]; out = {}
    for step in range(1, steps + 1):
        m.train(); Si = np.zeros((B, 25), int); Sy = np.zeros((B, 25), np.float32); Sm = np.zeros((B, 25), np.float32)
        Qi = np.zeros((B, NQ + NCQ), int); Qy = np.zeros((B, NQ + NCQ), np.float32); Qt = np.zeros((B, NQ + NCQ), int); Qm = np.zeros((B, NQ + NCQ), np.float32)
        for b in range(B):
            tk, idx, z = tt[rng.integers(len(tt))]; k = min(int(rng.choice(KS)), len(idx) - 8); perm = rng.permutation(len(idx)); s_ = perm[:k]; q_ = perm[k:k + NQ]
            Si[b, :k] = idx[s_]; Sy[b, :k] = z[s_]; Sm[b, :k] = 1; Qi[b, :len(q_)] = idx[q_]; Qy[b, :len(q_)] = z[q_]; Qm[b, :len(q_)] = 1
            if censored and tk in Ct:
                cv = Ct[tk]; nc = min(NCQ, len(cv["idx"])); cc = rng.choice(len(cv["idx"]), nc, replace=False); o = NQ
                Qi[b, o:o + nc] = cv["idx"][cc]; Qy[b, o:o + nc] = cv["c"][cc]; Qt[b, o:o + nc] = cv["type"][cc]; Qm[b, o:o + nc] = 1
        Si_t, Qi_t = torch.from_numpy(Si), torch.from_numpy(Qi)
        eS, gS = m.embed(Xt[Si_t.reshape(-1)]); eS = eS.view(B, 25, -1); gS = gS.view(B, 25)
        eQ, gQ = m.embed(Xt[Qi_t.reshape(-1)]); eQ = eQ.view(B, NQ + NCQ, -1); gQ = gQ.view(B, -1)
        Sy_t, Sm_t = torch.from_numpy(Sy), torch.from_numpy(Sm); yb = (Sy_t * Sm_t).sum(1, keepdim=True) / Sm_t.sum(1, keepdim=True).clamp_min(1)
        mu = m.predict(eS, gS, Sy_t, eQ, gQ, Sm_t); y = torch.from_numpy(Qy) - yb; qm = torch.from_numpy(Qm); ty = torch.from_numpy(Qt)
        loss = (tobit_nll(mu, y, ty, m.sigma()) * qm).sum() / qm.sum()
        opt.zero_grad(); loss.backward(); opt.step()
        if step in ckpts: out[step] = {k_: v.detach().clone() for k_, v in m.state_dict().items()}
    return out


def meta_from_state(sd):
    m = Meta(); m.load_state_dict(sd); m.eval(); return m


def main(fold_list):
    t0 = time.time(); W = load_world(); T = target_table(W); C = censored_table(W)
    print("world", len(T), "targets", sum(len(v["p"]) for v in T.values()), "exact rows; censored targets", len(C), flush=True)
    for f in fold_list:
        out = f"{RES}/fold{f}.pkl"
        if os.path.exists(out): print("skip", f); continue
        rows, Ct = train_rows(W, T, f, C); n_tr = sum(len(r[1]) for r in rows); n_c = sum(len(v["idx"]) for v in Ct.values())
        print(f"fold {f}: {len(rows)} training targets, {n_tr} exact rows, {n_c} censored rows", flush=True)
        idx = np.concatenate([r[1] for r in rows]); z = np.concatenate([r[2] for r in rows]); M = {}
        hgb = HistGradientBoostingRegressor(max_iter=200, learning_rate=0.1, max_leaf_nodes=31, l2_regularization=1.0, early_stopping=False, random_state=0).fit(W["X"][idx], z); M["hgb"] = hgb
        mu_e, sd_e = W["Em"][idx].mean(0), W["Em"][idx].std(0) + 1e-6; M["emb_stats"] = (mu_e, sd_e); Es = (W["Em"][idx] - mu_e) / sd_e
        M["ridge"] = {a: Ridge(alpha=a).fit(Es, z) for a in (10, 100, 1000)}
        M["h0"] = train_mlp_prior(W["X"], rows, Ct, censored=False); M["h1"] = train_mlp_prior(W["X"], rows, Ct, censored=True)
        print("  priors done", round(time.time() - t0), "s", flush=True)
        M["f0"] = train_meta(W["X"], rows, Ct, censored=False); print("  f0 done", round(time.time() - t0), "s", flush=True)
        M["f1"] = train_meta(W["X"], rows, Ct, censored=True); print("  f1 done", round(time.time() - t0), "s", flush=True)
        M["sigma_h1"] = float(M["h1"].sigma()); M["sigma_f1"] = [float(meta_from_state(v).sigma()) for v in M["f1"].values()]
        pickle.dump(dict(M=M, n_train_targets=len(rows), n_exact=n_tr, n_cens=n_c), open(out, "wb")); print("saved", out, flush=True)


if __name__ == "__main__":
    main([int(x) for x in sys.argv[1:]] or list(range(6)))
