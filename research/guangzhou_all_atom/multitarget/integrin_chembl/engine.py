"""Models, nulls and split construction for the integrin benchmark (see README section B for the pre-registration)."""
import os, json, numpy as np, pandas as pd
from scipy.linalg import cho_factor, cho_solve
CACHE = os.environ.get("INTEGRIN_CACHE", "/private/tmp/claude-501/-Users-kky-biomate-review/195b4da4-5c44-48ae-a4e1-005d493239c0/scratchpad") + "/feat"
TARGETS = ["avb3", "avb5", "avb6", "avb8", "avb1", "a5b1", "aIIbb3", "a8b1"]; TI = {t: i for i, t in enumerate(TARGETS)}
OFFSET_K = 5.0
_G = {}
def G():
    if not _G:
        _G["comp"] = pd.read_csv(CACHE + "/comp.csv"); _G["ci_of"] = dict(zip(_G["comp"].cmpd_key, _G["comp"].ci))
        for k, f in dict(Klin="K_lin", Kmm="K_mm", T="tanimoto", C="counts2048", D="desc").items(): _G[k] = np.load(f"{CACHE}/{f}.npy", mmap_mode="r")
        _G["X"] = None
    return _G
def gbm_X(ci):
    g = G(); return np.hstack([np.asarray(g["D"][ci], dtype=np.float32), np.log1p(np.asarray(g["C"][ci][:, :1024], dtype=np.float32))])

# ---------------- document offsets ----------------
def doc_offsets(df):
    """df: columns doc, t, y. u_d = n/(n+K) * mean(y - target_mean). Returns (target_mean dict, u series per row)."""
    mu = df.groupby("t").y.mean(); r = df.y - df.t.map(mu); g = r.groupby(df.doc); u = (g.sum() / (g.count() + OFFSET_K))
    return mu.to_dict(), df.doc.map(u).values

# ---------------- kernel ridge with nested grouped lambda ----------------
def _krr(K, tr, y, te, lam):
    A = K[np.ix_(tr, tr)] + lam * np.eye(len(tr)); m = y.mean(); c = cho_factor(A, lower=True, check_finite=False)
    return m + K[np.ix_(te, tr)] @ cho_solve(c, y - m, check_finite=False)
def krr_fit_predict(K, ci_tr, y_tr, doc_tr, ci_te, lams, ck_tr=None, nfold=5, seed=0):
    ci_tr = np.asarray(ci_tr); y_tr = np.asarray(y_tr, float); n = len(ci_tr)
    if n < 8: return np.full(len(ci_te), y_tr.mean() if n else np.nan), None
    if len(lams) > 1:
        docs = np.unique(doc_tr); rng = np.random.RandomState(seed); rng.shuffle(docs); fold = {d: i % nfold for i, d in enumerate(docs)}; f = np.array([fold[d] for d in doc_tr])
        err = np.zeros(len(lams)); cnt = 0
        for k in range(min(nfold, len(docs))):
            va = np.where(f == k)[0]; trm = f != k; vac = set(ci_tr[va]); trm &= ~np.isin(ci_tr, list(vac)); tr = np.where(trm)[0]
            if len(va) == 0 or len(tr) < 8: continue
            for j, lam in enumerate(lams): err[j] += ((_krr(K, ci_tr[tr], y_tr[tr], ci_tr[va], lam) - y_tr[va]) ** 2).sum()
            cnt += len(va)
        lam = lams[int(np.argmin(err))] if cnt else lams[len(lams) // 2]
    else: lam = lams[0]
    return _krr(K, ci_tr, y_tr, np.asarray(ci_te), lam), lam

LAM_RIDGE = [0.3, 1, 3, 10, 30]; LAM_KRR = [0.03, 0.1, 0.3, 1]
# ---------------- main per-fold function ----------------
def run_fold(spec, models=("M1", "M2", "M3", "M4", "M5", "M6")):
    """spec: dict(train=DataFrame[doc,ck,t,y], train_pairs=DataFrame[doc,ck,tA,tB,delta], test=DataFrame[doc,ck,t,y,(group)],
    test_pairs=DataFrame[doc,ck,tA,tB,delta,(group)], use_doc_null=bool). Returns (T1 DataFrame, T2 DataFrame)."""
    from threadpoolctl import threadpool_limits
    with threadpool_limits(1):
        return _run_fold(spec, models)
def _run_fold(spec, models):
    g = G(); tr = spec["train"].copy(); te = spec["test"].copy(); trp = spec["train_pairs"].copy(); tep = spec["test_pairs"].copy()
    tr["ci"] = tr.ck.map(g["ci_of"]); te["ci"] = te.ck.map(g["ci_of"]); trp["ci"] = trp.ck.map(g["ci_of"]); tep["ci"] = tep.ck.map(g["ci_of"])
    mu, u = doc_offsets(tr); tr["u"] = u; tr["yadj"] = tr.y - tr.u
    out = te.copy(); P = {}   # P[model] -> dict (ci,t)->pred
    cells = sorted({(c, t) for c, t in zip(te.ci, te.t)}); cells_by_t = {t: [c for c, tt in cells if tt == t] for t in TARGETS}
    def per_target(K, lams):
        res = {}
        for t in TARGETS:
            s = tr[tr.t == t]
            if not len(cells_by_t[t]): continue
            p, _ = krr_fit_predict(K, s.ci.values, s.yadj.values, s.doc.values, cells_by_t[t], lams) if len(s) else (np.full(len(cells_by_t[t]), np.nan), None)
            for c, v in zip(cells_by_t[t], p): res[(c, t)] = v
        return res
    if "M1" in models: P["M1"] = per_target(g["Klin"], LAM_RIDGE)
    if "M2" in models: P["M2"] = per_target(g["Kmm"], LAM_KRR)
    if "M3" in models:
        from sklearn.ensemble import HistGradientBoostingRegressor
        oh = lambda t: np.eye(len(TARGETS), dtype=np.float32)[[TI[x] for x in t]]
        Xtr = np.hstack([gbm_X(tr.ci.values), oh(tr.t)]); m = HistGradientBoostingRegressor(max_iter=200, learning_rate=0.05, max_leaf_nodes=15, l2_regularization=1.0, random_state=0).fit(Xtr, tr.yadj.values)
        cc = np.array(cells); pr = m.predict(np.hstack([gbm_X(cc[:, 0].astype(int)), oh(cc[:, 1])])); P["M3"] = {(int(a), b): v for (a, b), v in zip(cells, pr)}
    if "M4" in models:
        import torch; torch.set_num_threads(1); torch.manual_seed(0)
        Xtr = torch.tensor(np.log1p(np.asarray(g["C"][tr.ci.values], dtype=np.float32))); ti = torch.tensor([TI[x] for x in tr.t]); y = torch.tensor(tr.yadj.values, dtype=torch.float32)
        ymean = float(y.mean()); net = torch.nn.Sequential(torch.nn.Linear(2048, 512), torch.nn.ReLU(), torch.nn.Dropout(0.2), torch.nn.Linear(512, 128), torch.nn.ReLU(), torch.nn.Linear(128, len(TARGETS)))
        opt = torch.optim.Adam(net.parameters(), lr=1e-3, weight_decay=1e-4); n = len(y)
        for ep in range(60):
            net.train(); perm = torch.randperm(n)
            for i in range(0, n, 128):
                b = perm[i:i + 128]; opt.zero_grad(); pred = net(Xtr[b]).gather(1, ti[b][:, None])[:, 0] + ymean; torch.nn.functional.mse_loss(pred, y[b]).backward(); opt.step()
        net.eval(); cc = np.array(cells)
        with torch.no_grad(): o = net(torch.tensor(np.log1p(np.asarray(g["C"][cc[:, 0].astype(int)], dtype=np.float32)))).numpy() + ymean
        P["M4"] = {(int(a), b): float(o[i, TI[b]]) for i, (a, b) in enumerate(cells)}
    for mname, d in P.items(): out[mname] = [d.get((c, t), np.nan) for c, t in zip(te.ci, te.t)]
    # ---- T1 nulls ----
    out["N1"] = te.t.map(mu).values; mua, _ = doc_offsets(tr.assign(y=tr.yadj)); out["N2"] = te.t.map(mua).values
    if spec.get("use_doc_null"):
        dm = tr.groupby(["doc", "t"]).y.mean().to_dict(); out["N3"] = [dm.get((d, t), mu.get(t, np.nan)) for d, t in zip(te.doc, te.t)]
    # promiscuity (oracle: other uncensored targets of the same doc+compound in the TEST data)
    key = te.groupby(["doc", "ck"]); prom = np.full(len(te), np.nan); promb = np.full(len(te), np.nan)
    for (d, c), idx in key.indices.items():
        sub = te.iloc[idx]
        for j, row in zip(idx, sub.itertuples()):
            oth = sub[sub.t != row.t]
            if len(oth): prom[j] = oth.y.mean(); promb[j] = oth.y.mean() + mu.get(row.t, np.nan) - np.mean([mu.get(x, np.nan) for x in oth.t])
    out["N4"] = np.where(np.isnan(prom), out.N1, prom); out["N4b"] = np.where(np.isnan(promb), out.N1, promb)
    T = g["T"]; nn = np.full(len(te), np.nan)
    for t in TARGETS:
        s = tr[tr.t == t]; m = (te.t == t).values
        if m.any() and len(s):
            sim = np.asarray(T[np.ix_(te.ci.values[m], s.ci.values)]); best = sim.max(1, keepdims=True); w = (sim >= best - 1e-9); nn[m] = (w * s.y.values[None, :]).sum(1) / w.sum(1)
    out["N5"] = np.where(np.isnan(nn), out.N1, nn)
    # ---- T2 ----
    o2 = tep.copy()
    for mname in P: o2[mname + "d"] = [P[mname].get((c, a), np.nan) - P[mname].get((c, b), np.nan) for c, a, b in zip(tep.ci, tep.tA, tep.tB)]
    pm = trp.groupby(["tA", "tB"]).delta.mean().to_dict(); o2["Z"] = 0.0; o2["N1p"] = [pm.get((a, b), 0.0) for a, b in zip(tep.tA, tep.tB)]
    nn2 = np.zeros(len(tep))
    for (a, b), idx in tep.groupby(["tA", "tB"]).indices.items():
        s = trp[(trp.tA == a) & (trp.tB == b)]
        if len(s):
            sim = np.asarray(T[np.ix_(tep.ci.values[idx], s.ci.values)]); w = (sim >= sim.max(1, keepdims=True) - 1e-9); nn2[idx] = (w * s.delta.values[None, :]).sum(1) / w.sum(1)
    o2["N5"] = nn2
    if "M5" in models:
        pv = np.array(o2.N1p)
        for (a, b), idx in tep.groupby(["tA", "tB"]).indices.items():
            s = trp[(trp.tA == a) & (trp.tB == b)]
            if len(s) >= 25:
                p, _ = krr_fit_predict(g["Klin"], s.ci.values, s.delta.values, s.doc.values, tep.ci.values[idx], LAM_RIDGE); pv[idx] = p
        o2["M5"] = pv
    if "M6" in models and len(trp):
        from sklearn.ensemble import HistGradientBoostingRegressor
        oh = lambda t: np.eye(len(TARGETS), dtype=np.float32)[[TI[x] for x in t]]
        def Xp(ci, a, b, flip=False): 
            A, B = (b, a) if flip else (a, b); return np.hstack([gbm_X(np.asarray(ci)), oh(A), oh(B)])
        Xt = np.vstack([Xp(trp.ci, trp.tA, trp.tB), Xp(trp.ci, trp.tA, trp.tB, True)]); yt = np.concatenate([trp.delta.values, -trp.delta.values])
        m = HistGradientBoostingRegressor(max_iter=200, learning_rate=0.05, max_leaf_nodes=15, l2_regularization=1.0, random_state=0).fit(Xt, yt)
        o2["M6"] = m.predict(Xp(tep.ci, tep.tA, tep.tB)) if len(tep) else []
    return out, o2
