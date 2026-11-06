"""Pilot 2 runner (pre-registered in docs/20261031_EDIT_EFFECT_PILOT_PREREG.md). usage: python3 pilot.py nme|dflip [--no-test]
Stage 1 (dev): hyperparameter selection on development-half pairs only (GroupKFold by parent flat structure).
Stage 2 (test): leave-one-source-out over test-half sources (tiny sources <10 pairs are held out jointly in ONE fit), controls, exploratory all-source LOSO.
The test half is not read until stage 1 has written dev_<edit>.json."""
import os, sys, json, zlib, itertools, warnings
import numpy as np, pandas as pd
warnings.filterwarnings("ignore")
HERE = os.path.dirname(os.path.abspath(__file__)); from scipy.stats import spearmanr
from sklearn.linear_model import Ridge
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.model_selection import GroupKFold
from rdkit import Chem, RDLogger
from rdkit.Chem import AllChem
RDLogger.DisableLog("rdApp.*")
import torch
torch.set_num_threads(int(os.environ.get("NT", "4")))
EDIT = sys.argv[1]; NO_TEST = "--no-test" in sys.argv; B_BOOT = 2000; MIN_PAIRS = 10; MIN_LABELLED = 20

# ------------------------------------------------------------------ data
D = pd.read_csv(os.path.join(HERE, "data", f"pairs_{EDIT}.csv"))
n_lab = pd.Series(json.load(open(os.path.join(HERE, "data", "source_nlab.json"))))
D["small_source"] = D.source.map(n_lab).fillna(0) < MIN_LABELLED
AROM = {int(k): v for k, v in json.load(open(os.path.join(HERE, "data", "parent_arom.json"))).items()}
_z = np.load(os.path.join(HERE, "data", "emb_small.npz"), allow_pickle=True); EM = {"smiles": _z["smiles"], "emb": _z["emb"]}; EMI = {s: i for i, s in enumerate(EM["smiles"])}   # arrays loaded ONCE (npz access re-decompresses on every lookup)
n_excluded = int(D.small_source.sum()); D = D[~D.small_source].reset_index(drop=True)
D["arom"] = D.parent.map(AROM).values

def fp(s):
    m = Chem.MolFromSmiles(s); v = np.zeros(2048, np.float32)
    for i, c in AllChem.GetMorganFingerprint(m, 2, useChirality=True).GetNonzeroElements().items(): v[i % 2048] += c
    return v
_u = sorted(set(D.smi_parent) | set(D.smi_edit)); _f = {s: fp(s) for s in _u}
FP_P = np.stack([_f[s] for s in D.smi_parent]); FP_E = np.stack([_f[s] for s in D.smi_edit]); FP_D = FP_E - FP_P
E_P = np.stack([EM["emb"][EMI[s]] for s in D.smi_parent]); E_E = np.stack([EM["emb"][EMI[s]] for s in D.smi_edit]); E_D = E_E - E_P
X_fp = np.hstack([FP_D, FP_P]); X_emb = np.hstack([E_D, E_P])
keep_fp = np.where(X_fp.std(0) > 0)[0]; X_fp = X_fp[:, keep_fp]
Z_nn = np.hstack([FP_P, FP_D]); Z_nn = Z_nn / (np.linalg.norm(Z_nn, axis=1, keepdims=True) + 1e-9)

# ------------------------------------------------------------------ models
def std_fit(Xtr, Xte):
    mu, sd = Xtr.mean(0), Xtr.std(0) + 1e-6; return (Xtr - mu) / sd, (Xte - mu) / sd

def m_const(tr, te, y, src, hp):
    if hp["avg"] == "pair": c = y[tr].mean()
    else: c = pd.Series(y[tr]).groupby(src[tr]).mean().mean()
    return np.full(len(te), c)

def m_nn(tr, te, y, src, hp):
    S = Z_nn[te] @ Z_nn[tr].T; k = hp["k"]; idx = np.argpartition(-S, min(k, S.shape[1] - 1), axis=1)[:, :k]; return y[tr][idx].mean(1)

def m_gbm_fp(tr, te, y, src, hp):
    g = HistGradientBoostingRegressor(max_depth=hp["depth"], max_iter=150, learning_rate=0.05, random_state=0).fit(X_fp[tr], y[tr]); return g.predict(X_fp[te])

def m_ridge_emb(tr, te, y, src, hp):
    a, b = std_fit(X_emb[tr], X_emb[te]); return Ridge(alpha=hp["alpha"]).fit(a, y[tr]).predict(b)

def m_gbm_emb(tr, te, y, src, hp):
    g = HistGradientBoostingRegressor(max_depth=hp["depth"], max_iter=150, learning_rate=0.05, random_state=0).fit(X_emb[tr], y[tr]); return g.predict(X_emb[te])

def m_mlp(tr, te, y, src, hp):
    a, b = std_fit(X_emb[tr], X_emb[te]); a = torch.tensor(a, dtype=torch.float32); b = torch.tensor(b, dtype=torch.float32); t = torch.tensor(y[tr], dtype=torch.float32)
    mu, sd = t.mean(), t.std() + 1e-6; t = (t - mu) / sd; outs = []
    for seed in range(3):
        torch.manual_seed(seed); net = torch.nn.Sequential(torch.nn.Linear(a.shape[1], hp["hidden"]), torch.nn.ReLU(), torch.nn.Dropout(0.1), torch.nn.Linear(hp["hidden"], 1))
        opt = torch.optim.AdamW(net.parameters(), lr=1e-3, weight_decay=hp["wd"]); n = len(a)
        for ep in range(40):
            net.train(); perm = torch.randperm(n)
            for i in range(0, n, 128):
                j = perm[i:i + 128]; opt.zero_grad(); loss = torch.nn.functional.mse_loss(net(a[j]).squeeze(1), t[j]); loss.backward(); opt.step()
        net.eval()
        with torch.no_grad(): outs.append(net(b).squeeze(1).numpy())
    return np.mean(outs, 0) * float(sd) + float(mu)

GRID = {"const": (m_const, [dict(avg="pair"), dict(avg="source")]), "pair_nn": (m_nn, [dict(k=k) for k in (5, 20, 50)]),
        "gbm_fp": (m_gbm_fp, [dict(depth=d) for d in (3, 5)]), "ridge_emb": (m_ridge_emb, [dict(alpha=a) for a in (1, 10, 100, 1000)]),
        "gbm_emb": (m_gbm_emb, [dict(depth=d) for d in (3, 5)]), "ours_mlp": (m_mlp, [dict(hidden=h, wd=w) for h in (32, 128) for w in (1e-3, 1e-2)])}

def rho(a, b):
    if np.std(a) < 1e-12 or len(a) < 3: return 0.0
    r = spearmanr(a, b)[0]; return 0.0 if r != r else float(r)

# ------------------------------------------------------------------ stage 1: development selection (test half untouched)
y_all = D.dz.values; src = D.source.values
dev = np.where(D.half.values == 0)[0]
SEL = {}
dev_path = os.path.join(HERE, "data", f"dev_{EDIT}.json")
if os.path.exists(dev_path): SEL = json.load(open(dev_path))
else:
    groups = D.flat_parent.values[dev]; gkf = GroupKFold(5); rep = {}
    for name, (fn, hps) in GRID.items():
        best = None
        for hp in hps:
            pr = np.zeros(len(dev))
            for a, b in gkf.split(dev, groups=groups): pr[b] = fn(dev[a], dev[b], y_all, src, hp)
            score = -float(np.sqrt(np.mean((pr - y_all[dev]) ** 2))) if name == "const" else rho(pr, y_all[dev])
            rep.setdefault(name, []).append((hp, score))
            if best is None or score > best[1]: best = (hp, score)
        SEL[name] = dict(hp=best[0], dev_score=best[1], metric="neg_rmse" if name == "const" else "spearman")
    SEL["_grid"] = {k: [(h, s) for h, s in v] for k, v in rep.items()}
    # baseline = best of the non-ours simple models by dev Spearman (const excluded: Spearman undefined; it is the RMSE reference)
    SEL["_best_baseline"] = max(["pair_nn", "gbm_fp", "ridge_emb", "gbm_emb"], key=lambda k: SEL[k]["dev_score"])
    json.dump(SEL, open(dev_path, "w"), indent=1, default=str)
print("dev selection:", {k: (v["hp"], round(v["dev_score"], 3)) for k, v in SEL.items() if not k.startswith("_")}, "best baseline:", SEL["_best_baseline"], flush=True)
if NO_TEST: sys.exit(0)

# ------------------------------------------------------------------ stage 2: leave-one-source-out (test half = gate; all sources = exploratory)
def loso(y, sources_eval, hp_sel, models):
    """returns dict model -> predictions (nan where not evaluated); tiny sources (<MIN_PAIRS pairs) held out jointly in one fit."""
    cnt = pd.Series(src).value_counts(); big = [s for s in sources_eval if cnt[s] >= MIN_PAIRS]; tiny = [s for s in sources_eval if cnt[s] < MIN_PAIRS]
    groups = [[s] for s in big] + ([tiny] if tiny else []); out = {m: np.full(len(y), np.nan) for m in models}; dropped = {}
    for g in groups:
        te = np.where(np.isin(src, g))[0]; flats = set(D.flat_parent.values[te]) | set(D.flat_edit.values[te])
        ok = (~np.isin(src, g)) & (~D.flat_parent.isin(flats).values) & (~D.flat_edit.isin(flats).values)
        dropped[",".join(g)] = int(((~np.isin(src, g)) & ~ok).sum()); tr = np.where(ok)[0]
        for m in models: out[m][te] = GRID[m][0](tr, te, y, src, hp_sel[m]["hp"])
    return out, dropped

def cluster_boot(pred, y, srcs, f, seed_tag):
    """f(pred_subset, y_subset) -> statistic dict; resample SOURCES with replacement."""
    ids = sorted(set(srcs)); rng = np.random.default_rng(zlib.crc32(("|".join(ids) + seed_tag).encode())); idx = {s: np.where(srcs == s)[0] for s in ids}; res = []
    for _ in range(B_BOOT):
        pick = rng.choice(len(ids), len(ids)); sel = np.concatenate([idx[ids[i]] for i in pick]); res.append(f(sel))
    return np.array(res)

def ci(v): return [round(float(np.percentile(v, 2.5)), 4), round(float(np.percentile(v, 97.5)), 4)]

def evaluate(y, pred_by_model, sources_eval, tag):
    m = np.isin(src, sources_eval); ys = y[m]; ss = src[m]; P = {k: v[m] for k, v in pred_by_model.items()}; base = SEL["_best_baseline"]
    qual = [s for s in sources_eval if (src == s).sum() >= MIN_PAIRS]; rep = dict(n_pairs=int(m.sum()), n_sources=len(sources_eval), qualifying_sources=qual, n_qualifying=len(qual))
    rep["point"] = {k: dict(spearman=0.0 if k == "const" else round(rho(P[k], ys), 4), rmse=round(float(np.sqrt(np.mean((P[k] - ys) ** 2))), 4), sign_acc=round(float(np.mean(np.sign(P[k]) == np.sign(ys))), 4)) for k in P}
    def stat(sel):
        o = rho(P["ours_mlp"][sel], ys[sel]); b = rho(P[base][sel], ys[sel])
        return [o, b, o - b, float(np.mean((P["ours_mlp"][sel] - ys[sel]) ** 2) - np.mean((P["const"][sel] - ys[sel]) ** 2))]
    bs = cluster_boot(None, ys, ss, lambda sel: stat(sel), tag)
    rep["baseline_name"] = base; rep["ours_spearman_ci"] = ci(bs[:, 0]); rep["baseline_spearman_ci"] = ci(bs[:, 1]); rep["diff_spearman_ci"] = ci(bs[:, 2]); rep["mse_ours_minus_const_ci"] = ci(bs[:, 3])
    rep["diff_spearman_point"] = round(rep["point"]["ours_mlp"]["spearman"] - rep["point"][base]["spearman"], 4)
    rep["per_source_spearman(n>=30)"] = {s: {k: round(rho(P[k][ss == s], ys[ss == s]), 3) for k in ("ours_mlp", base)} | {"n": int((ss == s).sum())} for s in sources_eval if (src == s).sum() >= 30}
    c1 = rep["diff_spearman_point"] >= 0.05 and rep["diff_spearman_ci"][0] > 0; c2 = rep["mse_ours_minus_const_ci"][1] < 0
    rep["criteria"] = dict(c1_spearman_margin_and_ci=bool(c1), c2_rmse_beats_constant=bool(c2), c4_at_least_5_qualifying=len(qual) >= 5)
    return rep

models = list(GRID.keys()); test_sources = sorted(set(src[D.half.values == 1])); out = dict(edit=EDIT, n_pairs_after_label_scale_restriction=int(len(D)), n_pairs_excluded_small_sources=n_excluded, selection=SEL)
pred, dropped = loso(y_all, test_sources, SEL, models); out["leak_dropped_training_pairs"] = dropped
out["test_half_primary"] = evaluate(y_all, pred, test_sources, "primary")
# secondary target: raw log-Papp difference (same models, hyperparameters unchanged)
pred_raw, _ = loso(D.dy_raw.values, test_sources, SEL, models); out["test_half_raw_target"] = evaluate(D.dy_raw.values, pred_raw, test_sources, "raw")
# controls (identical folds, hyperparameters fixed from the real-data selection)
rng = np.random.default_rng(zlib.crc32(EDIT.encode())); med = float(np.median(D.arom.values[D.half.values == 0]))
y_pl = np.where(D.arom.values > med, 1.0, -1.0) + rng.normal(0, 0.3, len(D)); y_nu = rng.normal(0, 1.0, len(D)); y_sh = y_all.copy()
for s in set(src): ii = np.where(src == s)[0]; y_sh[ii] = rng.permutation(y_all[ii])
out["controls"] = {}
for nm, yy in (("planted_context", y_pl), ("null_edit", y_nu), ("shuffled_within_source", y_sh)):
    pr, _ = loso(yy, test_sources, SEL, models); out["controls"][nm] = evaluate(yy, pr, test_sources, nm)
# exploratory: all sources
all_sources = sorted(set(src)); pr_all, _ = loso(y_all, all_sources, SEL, models); out["exploratory_all_source_loso"] = evaluate(y_all, pr_all, all_sources, "all")
json.dump(out, open(os.path.join(HERE, "data", f"results_{EDIT}.json"), "w"), indent=1, default=str)
print(json.dumps({k: out[k] for k in ("test_half_primary",)}, indent=1, default=str)[:3000])
