#!/usr/bin/env python3
"""T2 provenance-aware acquisition for the retrospective closed loop (docs/20261030_TECHNIQUE_T2_ACQUISITION.md; pre-registration df9f89e00).
Read-only dependence on loop_retro (run_loop, run_loop_par, run_loop_prior). One task = (arm, regime, seed). Everything here follows the L5 loop exactly
(N_INIT 100, 10 rounds x 50, 5-member bootstrap HistGradientBoosting ensemble, rng = default_rng(seed)) so that `greedy` and `random` reproduce L5's `fp`/`random`."""
import os, sys, json, math, random, collections
import numpy as np
os.environ.setdefault("FP_CHIRAL", "1"); os.environ.setdefault("LABEL_COL", "PAMPA")
HERE = os.path.dirname(os.path.abspath(__file__))
LOOP = os.path.abspath(os.path.join(HERE, "..", "..", "loop_retro")); sys.path.insert(0, LOOP)
import run_loop as R, run_loop_par as P, run_loop_prior as K          # read-only imports

ARMS = ("random", "greedy", "ucb", "rule_phys", "nn_greedy", "fuse", "div", "prov")
C_UCB, N0, NN_K = 1.0, 100.0, 5                                         # fixed by the pre-registration (1.6)
BATCH, ROUNDS, N_INIT = R.BATCH, R.ROUNDS, R.N_INIT
BIG = 10 ** 9


# ----------------------------------------------------------------------------------------------------------------------------- data
def prepare(csv_path, cache=None):
    """Load CycPeptMPDB exactly as L5 (chirality-aware fingerprints, PAMPA label, within-source standardisation) and build everything the arms need."""
    if cache and os.path.exists(cache):
        import pickle
        return pickle.load(open(cache, "rb"))
    assert os.environ.get("FP_CHIRAL") == "1" and os.environ.get("LABEL_COL") == "PAMPA", "L5 settings required"
    from rdkit import Chem
    from rdkit.Chem import Crippen, rdMolDescriptors
    recs = R.load(csv_path)
    srcs = [r["source"] for r in recs]; scaf = [r["scaf"] for r in recs]; flat = [r["flat"] for r in recs]
    y = K.source_normalize(np.array([r["y"] for r in recs]), srcs); thr = float(np.quantile(y, 0.9))
    cnt = collections.Counter(srcs); grp = np.array([s if cnt[s] >= 20 else "__other__" for s in srcs]); thr_g = np.zeros(len(y))
    for g in set(grp.tolist()):
        m = grp == g; thr_g[m] = float(np.quantile(y[m], 0.9))
    M = [Chem.MolFromSmiles(r["smiles"]) for r in recs]
    hbd = np.array([rdMolDescriptors.CalcNumHBD(m) for m in M], float); tpsa = np.array([rdMolDescriptors.CalcTPSA(m) for m in M], float)
    logp = np.array([Crippen.MolLogP(m) for m in M], float)
    gz = lambda v: K.source_normalize(v, srcs)
    Kphys = (gz(-tpsa) + gz(-hbd) + gz(logp)) / 3.0                       # identical to run_l7a.build (L7f): textbook directions, no label-mined parameter
    X = np.stack([r["x"] for r in recs]).astype(np.float32)
    D = prepare_derived(dict(srcs=srcs, scaf=scaf, flat=flat, y=y, yraw=np.array([r["y"] for r in recs], float), thr=thr, thr_g=thr_g, Kphys=Kphys, X=X, smiles=[r["smiles"] for r in recs]))
    if cache:
        import pickle; pickle.dump(D, open(cache, "wb"))
    return D


def prepare_derived(D):
    """Binary fingerprints for similarity and integer codes for sources / flat structures (also used by the synthetic test fixtures)."""
    D = dict(D)
    D["B"] = (D["X"] > 0).astype(np.float32); D["Bn"] = D["B"].sum(1)
    sl = sorted(set(D["srcs"])); D["src_names"] = sl; sm = {s: i for i, s in enumerate(sl)}; D["src_code"] = np.array([sm[s] for s in D["srcs"]])
    fm = {}; D["flat_code"] = np.array([fm.setdefault(f, len(fm)) for f in D["flat"]])
    return D


def tanimoto_to(D, idx_all, j):
    """Binary Tanimoto (fingerprint bits) between every row of D['B'][idx_all] and compound j. Matches RDKit's TanimotoSimilarity on the same bit sets."""
    BU = D["B"][idx_all]; inter = BU @ D["B"][j]; union = D["Bn"][idx_all] + D["Bn"][j] - inter
    return inter / np.maximum(union, 1.0)


# ------------------------------------------------------------------------------------------------------------------------------ setup
def setup_L(seed, srcs, n_init, frac=0.25, min_n=20):
    """COPY of run_l7a.setup_L (L7f); test_acq.py asserts equality with the original."""
    cnt = collections.Counter(srcs); giants = {s for s, _ in cnt.most_common(2)}; cand = sorted(s for s, c in cnt.items() if c >= min_n and s not in giants)
    rng = random.Random(500000 + seed); rng.shuffle(cand); held, tot = [], 0
    for s in cand:
        if tot >= frac * len(srcs): break
        held.append(s); tot += cnt[s]
    hs = set(held); train = [i for i in range(len(srcs)) if srcs[i] not in hs]; test = [i for i in range(len(srcs)) if srcs[i] in hs]
    ids = list(train); random.Random(seed).shuffle(ids); return ids[:n_init], ids[n_init:], test, sorted(held)


def make_eval_slice(pool, seed, n_eval):
    """COPY of run_l7a.make_eval_slice."""
    rng = random.Random(100000 + seed); E = sorted(rng.sample(list(pool), n_eval)); es = set(E)
    return E, [i for i in pool if i not in es]


def causal_z(D, idx, k=5):
    """CAUSAL within-source standardisation (amendment A2): training targets for the revealed peptides `idx`, computed ONLY from the raw labels of the revealed peptides.
    Per source s with n_s revealed labels: mean/variance shrunk to the global revealed mean/variance with prior weight k (=5): mu_s=(n_s*m_s+k*mu_g)/(n_s+k), var_s=(n_s*v_s+k*v_g)/(n_s+k);
    a source with no revealed label uses the global statistics. Unrevealed labels are never read."""
    idx = np.asarray(idx); yr = D["yraw"][idx]; sc = D["src_code"][idx]
    mu_g, v_g = float(yr.mean()), float(max(yr.var(), 1e-12)); out = np.empty(len(idx))
    for s in np.unique(sc):
        m = sc == s; n = int(m.sum()); ms, vs = float(yr[m].mean()), float(yr[m].var())
        mu = (n * ms + k * mu_g) / (n + k); var = (n * vs + k * v_g) / (n + k); out[m] = (yr[m] - mu) / np.sqrt(max(var, 1e-12))
    return out


def setup(regime, seed, D, n_init=N_INIT):
    """-> init, pool, test (held-out-lab peptides, regime L only else None).
    A, B, C, L as pre-registered. A2 additions: B2 = LAB-shifted (init from the two largest sources, pool = every peptide of the OTHER sources); C2 = A with a Tanimoto >= 0.8 purge
    (binary fingerprint bits, chirality-aware) between pool and initial set."""
    if regime == "L":
        init, pool, test, _ = setup_L(seed, D["srcs"], n_init); return init, pool, test
    if regime == "B2":
        rng = random.Random(seed); top2 = {s for s, _ in collections.Counter(D["srcs"]).most_common(2)}
        cand = [i for i in range(len(D["srcs"])) if D["srcs"][i] in top2]; rng.shuffle(cand); init = cand[:n_init]
        return init, [i for i in range(len(D["srcs"])) if D["srcs"][i] not in top2], None
    if regime == "C2":
        rng = random.Random(seed); ids = list(range(len(D["srcs"]))); rng.shuffle(ids); init, rest = ids[:n_init], ids[n_init:]
        inter = D["B"][rest] @ D["B"][init].T; union = D["Bn"][rest][:, None] + D["Bn"][init][None, :] - inter; nn = (inter / np.maximum(union, 1.0)).max(1)
        return init, [i for i, v in zip(rest, nn) if v < 0.8], None
    init, pool = P.setup(regime, seed, D["srcs"], D["scaf"], n_init, D["flat"]); return init, pool, None


def leakage_stats(regime, seed, D):
    """Pool-vs-initial-set leakage for one (regime, seed): fraction of pool peptides whose nearest initial peptide has Tanimoto >= 0.9 / >= 0.8, median NN, same flat structure, same scaffold."""
    init, pool, _ = setup(regime, seed, D); pool = np.array(pool); init = np.array(init)
    inter = D["B"][pool] @ D["B"][init].T; union = D["Bn"][pool][:, None] + D["Bn"][init][None, :] - inter; nn = (inter / np.maximum(union, 1.0)).max(1)
    fl = set(D["flat_code"][init].tolist()); sc = {D["scaf"][i] for i in init}
    return dict(regime=regime, seed=seed, n_pool=len(pool), nn_ge_0p9=float((nn >= 0.9).mean()), nn_ge_0p8=float((nn >= 0.8).mean()), median_nn=float(np.median(nn)),
                same_flat=float(np.mean([D["flat_code"][i] in fl for i in pool])), same_scaffold=float(np.mean([D["scaf"][i] in sc for i in pool])))


# ------------------------------------------------------------------------------------------------------------------------ selection
def select_diverse(score, U, D, lam, cap_src, cap_flat, flat_count, batch=BATCH):
    """Diversity-aware sequential batch selection (pre-registration 1.5). `score` is aligned with U. Returns positions into U."""
    n = len(U); avail = np.ones(n, bool); msim = np.zeros(n)
    srcU = D["src_code"][U]; flatU = D["flat_code"][U]; src_cnt = np.zeros(len(D["src_names"]), int)
    fc = np.array([flat_count.get(int(f), 0) for f in flatU], int); BU = D["B"][U]; BUn = D["Bn"][U]; picks = []
    for _ in range(min(batch, n)):
        elig = avail & (src_cnt[srcU] < cap_src) & (fc < cap_flat)
        if not elig.any(): elig = avail                                    # caps relaxed only when nothing eligible remains
        val = np.where(elig, score - lam * msim, -np.inf)
        j = int(np.argmax(val)); picks.append(j); avail[j] = False
        src_cnt[srcU[j]] += 1; fc[flatU == flatU[j]] += 1
        inter = BU @ BU[j]; sim = inter / np.maximum(BUn + BUn[j] - inter, 1.0); msim = np.maximum(msim, sim)
    return picks


def zs(v): return K.zs(v)


def run_arm(arm, D, init, pool, seed, cfg, y=None, thr=None, thr_g=None, ymode="trans"):
    """One closed-loop run. Returns dict(rounds, rounds_g, picks). rng consumption order matches L5 for random/greedy/ucb/fuse."""
    override = y is not None
    assert ymode in ("trans", "causal") and (ymode == "trans" or not override), "causal mode uses raw labels; label overrides (planted/shuffle) are transductive-mode only"
    y = D["y"] if y is None else y; thr = D["thr"] if thr is None else thr; X = D["X"]
    rng = np.random.default_rng(seed); labeled = list(init); unl = list(pool); per, per_g, picks = [], [], []; flat_count = collections.Counter()
    lam, cap_src, cap_flat = cfg["lam"], cfg["cap_src"], cfg["cap_flat"]
    for _ in range(ROUNDS):
        L = np.array(labeled); U = np.array(unl)
        yL = y[L] if ymode == "trans" else causal_z(D, L)               # training targets: transductive (L5 / label override) or causal (A2: revealed raw labels only)
        if arm == "random": score = rng.random(len(U))
        elif arm == "rule_phys": score = D["Kphys"][U] + 1e-6 * rng.random(len(U))
        elif arm == "nn_greedy":
            inter = D["B"][U] @ D["B"][L].T; union = D["Bn"][U][:, None] + D["Bn"][L][None, :] - inter; S = inter / np.maximum(union, 1.0)
            top = np.argsort(-S, axis=1, kind="stable")[:, :NN_K]; w = np.take_along_axis(S, top, 1); lab = yL[top]
            score = (w * lab).sum(1) / np.maximum(w.sum(1), 1e-9) + 1e-9 * rng.random(len(U))
        else:
            ms = R.fit_ens(X[L], yL, rng); Pm = np.stack([m.predict(X[U]) for m in ms]); mu = Pm.mean(0); sd = Pm.std(0)
            w = N0 / (N0 + len(labeled))
            if arm == "greedy": score = mu
            elif arm == "ucb": score = mu + C_UCB * sd
            elif arm == "fuse": score = (1 - w) * zs(mu) + w * zs(D["Kphys"][U])
            elif arm == "div": score = zs(mu)
            elif arm == "prov": score = (1 - w) * zs(mu + C_UCB * sd) + w * zs(D["Kphys"][U])
            else: raise ValueError(arm)
        if arm in ("div", "prov"): sel = select_diverse(score, U, D, lam, cap_src, cap_flat, flat_count)
        else: sel = [int(j) for j in np.argsort(-score, kind="stable")[:BATCH]]
        pick = [unl[j] for j in sel]; s = set(pick); unl = [i for i in unl if i not in s]; labeled += pick
        for i in pick: flat_count[int(D["flat_code"][i])] += 1
        per.append(int(sum(y[i] >= thr for i in pick)))
        if thr_g is not None: per_g.append(int(sum(y[i] >= thr_g[i] for i in pick)))
        picks.extend(int(i) for i in pick)
    return dict(rounds=per, rounds_g=per_g, picks=picks, labeled=[int(i) for i in labeled])


# --------------------------------------------------------------------------------------------------------------------------- metrics
def entropy(counts):
    t = float(sum(counts)); return float(-sum((c / t) * math.log(c / t) for c in counts if c > 0)) if t > 0 else 0.0


def provenance(picks, D):
    sc = collections.Counter(D["src_code"][i] for i in picks); fc = collections.Counter(D["flat_code"][i] for i in picks); n = len(picks)
    names = D["src_names"]; top = ("2020_Townsend", "2021_Kelly")
    tk = sum(c for s, c in sc.items() if names[s] in top)
    return dict(src_entropy=entropy(sc.values()), top_src_share=max(sc.values()) / n, townsend_kelly_share=tk / n, n_sources=len(sc),
                flat_entropy=entropy(fc.values()), n_flat=len(fc), max_flat=max(fc.values()))


def transfer_metric(D, labeled, E, seed, ymode="trans"):
    """Regime L descriptive metric: final ensemble on all revealed labels scored on E (held-out labs, never revealed). E labels are standardised with each held-out lab's OWN statistics
    (transductive convention shared by every arm; within-source Spearman is invariant to it, the pooled Spearman is not)."""
    from scipy.stats import spearmanr
    rng = np.random.default_rng(seed + 777); L = np.array(labeled); yL = D["y"][L] if ymode == "trans" else causal_z(D, L); ms = R.fit_ens(D["X"][L], yL, rng)
    s = np.mean([m.predict(D["X"][E]) for m in ms], 0); yE = D["y"][E]; pooled = float(spearmanr(s, yE)[0])
    per = []
    for g in sorted(set(D["src_code"][E].tolist())):
        ix = np.where(D["src_code"][E] == g)[0]
        if len(ix) >= 15 and np.std(yE[ix]) > 0 and np.std(s[ix]) > 0: per.append(float(spearmanr(s[ix], yE[ix])[0]))
    return dict(transfer_pooled=pooled, transfer_per_source=(float(np.mean(per)) if per else None), transfer_n_sources=len(per))


def run_task(arm, regime, seed, D, cfg, y=None, thr=None, thr_g=None, n_eval=800, with_transfer=True, ymode="trans"):
    init, pool, test = setup(regime, seed, D)
    r = run_arm(arm, D, init, pool, seed, cfg, y=y, thr=thr, thr_g=thr_g, ymode=ymode)
    out = dict(arm=arm, regime=regime, seed=seed, ymode=ymode, n_pool=len(pool), hits=int(sum(r["rounds"])), rounds=r["rounds"], picks=r["picks"])
    if r["rounds_g"]: out["hits_g"] = int(sum(r["rounds_g"])); out["rounds_g"] = r["rounds_g"]
    out.update(provenance(r["picks"], D))
    if regime == "L" and with_transfer:
        E, _ = make_eval_slice(test, seed, n_eval); out.update(transfer_metric(D, r["labeled"], np.array(E), seed, ymode))
    return out
