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
os.environ.setdefault("OMP_NUM_THREADS", "2")
import torch
torch.set_num_threads(2)
import multiprocessing as mp
EDIT = sys.argv[1]; NO_TEST = False; B_BOOT = 2000; MIN_PAIRS = 10; MIN_LABELLED = 20

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
keep_fp = np.argsort(-X_fp.std(0))[:512]; X_fp = X_fp[:, keep_fp]     # label-free: 512 highest-variance columns (implementation detail, stated in the results)
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
    g = HistGradientBoostingRegressor(max_depth=hp["depth"], max_iter=100, learning_rate=0.05, random_state=0).fit(X_fp[tr], y[tr]); return g.predict(X_fp[te])

def m_ridge_emb(tr, te, y, src, hp):
    a, b = std_fit(X_emb[tr], X_emb[te]); return Ridge(alpha=hp["alpha"]).fit(a, y[tr]).predict(b)

def m_gbm_emb(tr, te, y, src, hp):
    g = HistGradientBoostingRegressor(max_depth=hp["depth"], max_iter=100, learning_rate=0.05, random_state=0).fit(X_emb[tr], y[tr]); return g.predict(X_emb[te])

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


# ------------------------------------------------------------------ amendment A1 analyses (docs/20261031_EDIT_EFFECT_PILOT_PREREG.md, section "AMENDMENT A1")
NPROC = int(os.environ.get("NPROC", "4")); y_all = D.dz.values; src = D.source.values; cnt = pd.Series(src).value_counts(); QUAL = sorted([s for s in cnt.index if cnt[s] >= MIN_PAIRS]); TINY = sorted([s for s in cnt.index if cnt[s] < MIN_PAIRS])
FLATP = D.flat_parent.values; FLATE = D.flat_edit.values; BASES = ["pair_nn", "gbm_fp", "ridge_emb", "gbm_emb"]

def select(tr, y):
    """hyperparameter selection by GroupKFold(5) on parent flat structure inside the training set `tr` only."""
    groups = FLATP[tr]; gkf = GroupKFold(5); sel = {}
    for name, (fn, hps) in GRID.items():
        best = None
        for hp in hps:
            pr = np.zeros(len(tr))
            for a, b in gkf.split(tr, groups=groups): pr[b] = fn(tr[a], tr[b], y, src, hp)
            sc = -float(np.sqrt(np.mean((pr - y[tr]) ** 2))) if name == "const" else rho(pr, y[tr])
            if best is None or sc > best[1]: best = (hp, sc)
        sel[name] = dict(hp=best[0], dev_score=best[1])
    sel["_best_baseline"] = max(BASES, key=lambda k: sel[k]["dev_score"]); return sel

def leak_free(te_idx, extra_excl_sources=()):
    fl = set(FLATP[te_idx]) | set(FLATE[te_idx]); ok = ~np.isin(src, list(extra_excl_sources)) & ~pd.Series(FLATP).isin(fl).values & ~pd.Series(FLATE).isin(fl).values
    return np.where(ok)[0]

def fit_predict_all(tr, te, y, sel):
    return {m: GRID[m][0](tr, te, y, src, sel[m]["hp"]) for m in GRID}

def task_B(s):
    te = np.where(src == s)[0]; tr = leak_free(te, [s]); sel = select(tr, y_all); P = fit_predict_all(tr, te, y_all, sel)
    ctl = {}; rng = np.random.default_rng(zlib.crc32(("ctl" + EDIT).encode())); med = float(np.median(D.arom.values))
    return dict(source=s, te=te.tolist(), tr_n=int(len(tr)), sel={k: v for k, v in sel.items()}, P={k: v.tolist() for k, v in P.items()})

def targets_controls():
    rng = np.random.default_rng(zlib.crc32(EDIT.encode())); med = float(np.median(D.arom.values))
    y_pl = np.where(D.arom.values > med, 1.0, -1.0) + rng.normal(0, 0.3, len(D)); y_nu = rng.normal(0, 1.0, len(D)); y_sh = y_all.copy()
    for s in set(src): ii = np.where(src == s)[0]; y_sh[ii] = rng.permutation(y_all[ii])
    return dict(planted_context=y_pl, null_edit=y_nu, shuffled_within_source=y_sh)
CTL = targets_controls()

def task_B_ctl(args):
    s, sel, nm = args; te = np.where(src == s)[0]; tr = leak_free(te, [s]); P = fit_predict_all(tr, te, CTL[nm], sel); return dict(source=s, name=nm, te=te.tolist(), P={k: v.tolist() for k, v in P.items()})

def task_C(args):
    k, test_side = args; te = np.where(np.isin(src, test_side))[0]; tr = np.where(~np.isin(src, test_side))[0]
    fl = set(FLATP[te]) | set(FLATE[te]); tr = tr[~pd.Series(FLATP[tr]).isin(fl).values & ~pd.Series(FLATE[tr]).isin(fl).values]
    sel = select(tr, y_all); P = fit_predict_all(tr, te, y_all, sel); b = sel["_best_baseline"]; yt = y_all[te]
    o = rho(P["ours_mlp"], yt); bb = rho(P[b], yt); mo = float(np.mean((P["ours_mlp"] - yt) ** 2)); mc = float(np.mean((P["const"] - yt) ** 2))
    return dict(split=k, test_side=list(test_side), n_test=int(len(te)), baseline=b, ours=round(o, 4), base=round(bb, 4), diff=round(o - bb, 4), rmse_skill_vs_const=round(1 - mo / mc, 4), passes=bool(o - bb >= 0.05 and mo < mc))

def assemble(results):
    n = len(y_all); P = {m: np.full(n, np.nan) for m in list(GRID) + ["baseline"]}
    for r in results:
        te = np.array(r["te"])
        for m in GRID: P[m][te] = r["P"][m]
        if "sel" in r: P["baseline"][te] = np.array(r["P"][r["sel"]["_best_baseline"]])
        else: P["baseline"][te] = np.array(r["P"][BASE_FALLBACK])
    return P

def summarise(y, P, sources_eval, tag):
    m = np.isin(src, sources_eval); ys = y[m]; ss = src[m]; Q = {k: v[m] for k, v in P.items()}
    rep = dict(n_pairs=int(m.sum()), sources=list(sources_eval), n_sources=len(sources_eval))
    rep["point"] = {k: dict(spearman=0.0 if k == "const" else round(rho(Q[k], ys), 4), rmse=round(float(np.sqrt(np.mean((Q[k] - ys) ** 2))), 4), sign_acc=round(float(np.mean(np.sign(Q[k]) == np.sign(ys))), 4)) for k in Q}
    def stat(sel): return [rho(Q["ours_mlp"][sel], ys[sel]), rho(Q["baseline"][sel], ys[sel]), float(np.mean((Q["ours_mlp"][sel] - ys[sel]) ** 2) - np.mean((Q["const"][sel] - ys[sel]) ** 2))]
    bs = cluster_boot(None, ys, ss, lambda sel: stat(sel), tag); d = bs[:, 0] - bs[:, 1]
    rep["diff_spearman_point"] = round(rep["point"]["ours_mlp"]["spearman"] - rep["point"]["baseline"]["spearman"], 4); rep["diff_spearman_ci"] = ci(d); rep["ours_spearman_ci"] = ci(bs[:, 0]); rep["baseline_spearman_ci"] = ci(bs[:, 1])
    rep["mse_ours_minus_const_ci"] = ci(bs[:, 2]); rep["boot_sd_diff"] = round(float(np.std(d)), 4); rep["MDE_80pct_power"] = round(2.8 * float(np.std(d)), 4)
    rep["per_source_spearman(n>=30)"] = {s: {k: round(rho(Q[k][ss == s], ys[ss == s]), 3) for k in ("ours_mlp", "baseline")} | {"n": int((ss == s).sum())} for s in sources_eval if (ss == s).sum() >= 30}
    return rep

def cluster_boot(_, y, srcs, f, tag):
    ids = sorted(set(srcs)); rng = np.random.default_rng(zlib.crc32(("|".join(ids) + tag).encode())); idx = {s: np.where(srcs == s)[0] for s in ids}; res = []
    for _i in range(B_BOOT):
        pick = rng.choice(len(ids), len(ids)); sel = np.concatenate([idx[ids[i]] for i in pick]); res.append(f(sel))
    return np.array(res)
def ci(v): return [round(float(np.percentile(v, 2.5)), 4), round(float(np.percentile(v, 97.5)), 4)]

if __name__ == "__main__":
    ctx = mp.get_context("fork"); out = dict(edit=EDIT, n_pairs=int(len(D)), n_excluded_small_label_sources=n_excluded, qualifying_sources=QUAL, tiny_sources=TINY)
    import time; t0 = time.time()
    # (B) leave-one-source-out over qualifying sources: PRIMARY
    with ctx.Pool(NPROC) as pool: RB = pool.map(task_B, QUAL, chunksize=1)
    print("B done", round(time.time() - t0), "s", flush=True)
    PB = assemble(RB); sB = summarise(y_all, PB, QUAL, "B"); sB["baseline_chosen_per_fold"] = {r["source"]: r["sel"]["_best_baseline"] for r in RB}; sB["train_sizes"] = {r["source"]: r["tr_n"] for r in RB}
    cr = sB["criteria"] = dict(c1_spearman_margin_and_ci=bool(sB["diff_spearman_point"] >= 0.05 and sB["diff_spearman_ci"][0] > 0), c2_rmse_beats_constant=bool(sB["mse_ours_minus_const_ci"][1] < 0), c4_at_least_5_qualifying=len(QUAL) >= 5, mde_le_margin=bool(sB["MDE_80pct_power"] <= 0.05))
    out["B_loso_primary"] = sB
    # controls on B with the real-data fold hyperparameters
    out["B_controls"] = {}
    selmap = {r["source"]: r["sel"] for r in RB}
    for nm in CTL:
        with ctx.Pool(NPROC) as pool: RC = pool.map(task_B_ctl, [(s, selmap[s], nm) for s in QUAL], chunksize=1)
        for r in RC: r["sel"] = selmap[r["source"]]
        PC = assemble(RC); out["B_controls"][nm] = summarise(CTL[nm], PC, QUAL, "B_" + nm)
    print("controls done", round(time.time() - t0), "s", flush=True)
    # (C) repeated source halves
    rngC = np.random.default_rng(zlib.crc32(("dflip-halves" if EDIT == "dflip" else "nme-halves").encode())); import itertools
    allsplits = []
    for r_ in range(2, len(QUAL) - 1):
        for comb in itertools.combinations(QUAL, r_): allsplits.append(comb)
    allsplits = sorted(set(allsplits)); R = 10 if EDIT == "nme" else 30
    if len(allsplits) > R: pick = rngC.choice(len(allsplits), R, replace=False); allsplits = [allsplits[i] for i in sorted(pick)]
    with ctx.Pool(NPROC) as pool: RCs = pool.map(task_C, list(enumerate(allsplits)), chunksize=1)
    out["C_repeated_halves"] = dict(n_splits=len(RCs), splits=RCs, frac_pass=round(float(np.mean([r["passes"] for r in RCs])), 4), diff_quantiles={q: round(float(np.percentile([r["diff"] for r in RCs], q)), 4) for q in (5, 25, 50, 75, 95)}, rmse_skill_median=round(float(np.median([r["rmse_skill_vs_const"] for r in RCs])), 4))
    print("C done", round(time.time() - t0), "s", flush=True)
    # (A) originally registered single split, for continuity
    dev = np.where(D.half.values == 0)[0]; selA = select(dev, y_all); test_sources = sorted(set(src[D.half.values == 1])); qA = [s for s in test_sources if cnt[s] >= MIN_PAIRS]
    rA = []
    for s in qA:
        te = np.where(src == s)[0]; tr = leak_free(te, [s]); rA.append(dict(source=s, te=te.tolist(), sel=selA, P={k: v.tolist() for k, v in fit_predict_all(tr, te, y_all, selA).items()}))
    sA = summarise(y_all, assemble(rA), qA, "A"); sA["note"] = "original registered split (dev half tuning); tiny test sources not scored here"; out["A_single_split"] = sA
    # decision (A1.2)
    fracC = out["C_repeated_halves"]["frac_pass"]; c3 = all((not (v["diff_spearman_point"] >= 0.05 and v["diff_spearman_ci"][0] > 0)) if k in ("null_edit", "shuffled_within_source") else True for k, v in out["B_controls"].items())
    pl = out["B_controls"]["planted_context"]["point"]; c3 = bool(c3 and pl["ours_mlp"]["spearman"] >= 0.5 and abs(pl["const"]["spearman"]) < 0.1); cr["c3_controls_ok"] = c3
    out["verdict_A1"] = ("UNDERPOWERED" if (not cr["c4_at_least_5_qualifying"] or not cr["mde_le_margin"]) else ("GO" if (cr["c1_spearman_margin_and_ci"] and cr["c2_rmse_beats_constant"] and c3 and fracC >= 0.5) else "NO-GO"))
    out["verdict_wording"] = ("no gain detectable above MDE=%.3f" % sB["MDE_80pct_power"]) if out["verdict_A1"] != "GO" else "pre-registered GO conditions met (compute go/no-go only; not paper evidence)"
    json.dump(out, open(os.path.join(HERE, "data", f"results2_{EDIT}.json"), "w"), indent=1, default=str)
    print("verdict", out["verdict_A1"], out["verdict_wording"], flush=True)
