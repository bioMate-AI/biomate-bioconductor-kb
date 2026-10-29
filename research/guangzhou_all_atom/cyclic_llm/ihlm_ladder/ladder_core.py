"""T-LADDER core (torch-free): world construction, causal labels, the arm loop, the K-shuffle control. Imported by run_ladder.py (adds the torch backends) and by test_ladder.py core tests
(so the CPU pre-flight needs no torch; lesson of the L7q pre-flight failure). Behaviour is unchanged from the pre-registered run_ladder.py/adapter.py (amendment A2 = file split only)."""
import os, sys, random, collections, time
import numpy as np
os.environ.setdefault("FP_CHIRAL", "1"); os.environ.setdefault("LABEL_COL", "PAMPA")
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "loop_retro"))
import run_loop as R, run_loop_par as P, run_loop_prior as K, run_l7a as L

PARAMS = dict(L.PARAMS)                                    # n_init 100, rounds 10, batch 50, n_eval 800, steps0 100, steps_round 30, n_cand 150, n_flat_groups 60
TOP = L.TOP


def causal_labels(idx, y_seen, srcs, scheme="zc", m=5.0, y_transductive=None):
    """Learner-visible labels computed from the REVEALED set only (pre-registration section 4).
    zc: per-source shrunk z (mu_s, sigma_s shrunk toward the global revealed statistics with weight m); gc: global-centred (source offsets left in); zt: transductive control (labels passed in as is)."""
    idx = np.asarray(idx, dtype=int); y = np.asarray(y_seen, float)
    if scheme == "zt": return np.asarray(y_transductive, float)
    muG = float(y.mean()) if len(y) else 0.0; sdG = float(y.std()) if len(y) > 1 and y.std() > 0 else 1.0
    if scheme == "gc": return y - muG
    out = np.zeros(len(y)); by = {}
    for j, i in enumerate(idx): by.setdefault(srcs[i], []).append(j)
    for s, js in by.items():
        v = y[js]; n = len(v); mu = (n * v.mean() + m * muG) / (n + m); var = (n * (v.var() if n > 1 else 0.0) + m * sdG ** 2) / (n + m)
        out[js] = (v - mu) / (np.sqrt(var) if var > 0 else 1.0)
    return out


def world(recs, d, reg, seed, k_anchor, p):
    """Same slice order as L7 (E, E_f, E_s) so pool and E are those of the L7 task; anchors then moved to the revealed set for EVERY arm (equal information)."""
    srcs, flat = d["srcs"], d["flat"]; cnt = collections.Counter(srcs); anchors = []
    if reg in ("L", "M"):
        init, pool, test, held = L.setup_L(seed, srcs, p["n_init"], max_labs=(9 if reg == "M" else None)); E, rest = L.make_eval_slice(test, seed, p["n_eval"])
        Ef, Efg, Efs, rest = L.make_flat_slice(rest, flat, seed, p["n_flat_groups"], d["y"]); Es, rest = L.make_source_slice(rest, srcs, seed)
        assert all(srcs[i] in set(held) for i in E + Ef + Efs + Es) and all(srcs[i] not in set(held) for i in list(pool) + list(init)), "regime L leakage between training and held-out labs"
        anchor_src = {i: srcs[i] for i in rest}; elig = collections.defaultdict(list)
        for i in rest: elig[srcs[i]].append(i)
        anchor_pool = rest
    else:
        init, pool = P.setup(reg, seed, srcs, d["scaf"], p["n_init"], flat); E, pool = L.make_eval_slice(pool, seed, p["n_eval"])
        Ef, Efg, Efs, pool = L.make_flat_slice(pool, flat, seed, p["n_flat_groups"], d["y"]); Es, pool = L.make_source_slice(pool, srcs, seed); elig = collections.defaultdict(list)
        for i in pool: elig[srcs[i]].append(i)
        held = []
    if k_anchor > 0:
        rng = random.Random(900000 + seed)
        for s in sorted(elig):
            if cnt[s] < 20: continue
            if reg in ("L", "M") and s not in set(held): continue
            anchors += rng.sample(sorted(elig[s]), min(k_anchor, len(elig[s])))
    aset = set(anchors); excl = [set(E), set(Ef), set(Efs), set(Es)]
    assert not aset & set(init) and all(not aset & x for x in excl), "anchors overlap an evaluation slice or the initial set"
    if reg not in ("L", "M"): pool = [i for i in pool if i not in aset]
    assert all(not x & set(pool) and not x & set(init) for x in excl)
    return dict(init=list(init), anchors=anchors, rev0=list(init) + anchors, pool=list(pool), E=list(E), held=list(held))


def run_arm(W, arm, B, kind, scheme, seed, p, ctx):
    y_raw, y_t, hit, srcs, K = ctx["y_raw"], ctx["y_t"], ctx["hit"], ctx["srcs"], ctx["Kp"]; rng = np.random.default_rng(seed); t0 = time.time()
    revealed = list(W["rev0"]); yseen = [float(y_raw[i]) for i in revealed]; E = np.array(W["E"]); pool0 = W["pool"]; picked = list(revealed)
    zl = lambda: causal_labels(revealed, yseen, srcs, scheme, y_transductive=[y_t[i] for i in revealed])
    state0 = None if kind == "rule" else B.fit(B.init_state(), revealed, zl(), p["steps0"], seed)
    pred = (lambda st, idx: K[np.asarray(idx, int)]) if kind == "rule" else (lambda st, idx: B.predict(st, idx))
    s0 = np.asarray(pred(state0, E), float); ef0, au0 = L.ef5_auroc(s0, hit[E]); rec = dict(hits=[], src=[], picks=[], ef5_E0=ef0, auroc_E0=au0, n_revealed0=len(revealed)); state = state0
    for r in range(p["rounds"]):
        U = np.array(L.subset(pool0, seed, r, picked, p["n_cand"]), dtype=int)
        if kind == "random": pick = [int(i) for i in rng.choice(U, p["batch"], replace=False)]
        else:
            s = pred(state0 if kind == "frozen" else state, U); pick = [int(i) for i in U[np.argsort(-s, kind="stable")[:p["batch"]]]]
        rec["picks"].append(pick); rec["hits"].append(int(sum(hit[i] for i in pick))); c = collections.Counter(srcs[i] for i in pick)
        rec["src"].append({TOP[0]: c.get(TOP[0], 0), TOP[1]: c.get(TOP[1], 0), "other": len(pick) - c.get(TOP[0], 0) - c.get(TOP[1], 0)}); picked += pick
        if kind in ("frozen", "rule"): continue
        new = y_raw[pick].copy()
        if kind == "shuffled": new = rng.choice(y_raw[np.array(pool0)], len(pick), replace=False)          # global draw: no item/batch association (L7d)
        revealed += pick; yseen += [float(v) for v in new]; state = B.fit(state, revealed, zl(), p["steps_round"], seed * 1000 + r)
    sF = np.asarray(pred(state if kind not in ("frozen", "rule") else state0, E), float); ef, au = L.ef5_auroc(sF, hit[E]); rec.update(E_score0=[round(float(v), 5) for v in s0], E_score_final=[round(float(v), 5) for v in sF], ef5_E=ef, auroc_E=au, seconds=round(time.time() - t0, 1), n_revealed=len(revealed))
    return rec


def kshuf(Kp, srcs, seed):
    out = Kp.copy(); rr = np.random.default_rng(seed + 7); by = collections.defaultdict(list)
    for i, s in enumerate(srcs): by[s].append(i)
    for s in sorted(by): ix = np.array(sorted(by[s])); out[ix] = Kp[ix[rr.permutation(len(ix))]]          # sorted iteration: reproducible across PYTHONHASHSEED
    return out


def parse_seeds(s):
    if "-" in s: a, b = s.split("-"); return list(range(int(a), int(b) + 1))
    return [int(x) for x in s.split(",")]
