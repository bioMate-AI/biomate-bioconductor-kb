"""T-LADDER tests (pre-registration docs/20261030_IHLM_LADDER_PREREG.md section 8 + amendment A2).
Run:  OMP_NUM_THREADS=2 python3 test_ladder.py core    torch-free (CPU pre-flight on a bare spot instance: numpy, scipy, sklearn, rdkit only)
      OMP_NUM_THREADS=2 python3 test_ladder.py full    adds the planted-signal rung tests, label-isolation through the IH-LM rungs and the hash-seed determinism run (needs torch)
      python3 test_ladder.py                           core + full
A rung whose planted test fails is an 'adapter/module defect' (prereg section 8): its real-data results must not be interpreted."""
import os, sys, json, subprocess, tempfile, collections, random
os.environ.setdefault("FP_CHIRAL", "1"); os.environ.setdefault("LABEL_COL", "PAMPA")
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "loop_retro")); sys.path.insert(0, os.path.join(HERE, "..", "ihlm"))
REPO_CSV = os.path.join(HERE, "..", "..", "data", "raw", "CycPeptMPDB_Peptide_All.csv")
CSV = next((p for p in (os.path.join(os.environ.get("SCRATCH", "/nonexistent"), "CycPeptMPDB_Peptide_All.csv"), REPO_CSV) if os.path.exists(p)), REPO_CSV)
from scipy.stats import spearmanr
import ladder_core as C
import run_l7a as L, loop_models as LM

_CACHE = {}
SMOKE = dict(C.PARAMS, rounds=2, steps0=10, steps_round=5, n_eval=100, n_init=40, batch=20, n_cand=60, n_flat_groups=10)


def data():
    if "d" not in _CACHE:
        recs, d = L.build(CSV, "gbm", "cpu")
        _CACHE["d"] = (recs, d, dict(y_raw=np.array([r["y"] for r in recs], float), y_t=d["y"], hit=(d["y"] >= d["thr"]), srcs=d["srcs"], Kp=np.asarray(d["Kphys"], float), smiles=[r["smiles"] for r in recs], X=np.stack([r["x"] for r in recs])))
    return _CACHE["d"]


def rho(a, b):
    r = spearmanr(a, b)[0]; return 0.0 if r != r else float(r)


# ------------------------------------------------------------------ core (torch-free)
def test_causal_labels_use_only_the_revealed_set_and_shrink_correctly():
    rng = np.random.default_rng(0); srcs = ["a"] * 200 + ["b"] * 200 + ["c"] * 2 + ["t"] * 200; idx = list(range(602)); y = np.concatenate([rng.normal(3, 2, 200), rng.normal(-5, 2.2, 200), [10.0, 12.0], rng.normal(0, 0.5, 200)])
    z = C.causal_labels(idx, y, srcs, "zc"); assert abs(z[:200].mean()) < 0.1 and abs(z[200:400].mean()) < 0.1 and abs(z[:200].std() - 1) < 0.15 and abs(z[200:400].std() - 1) < 0.15, "zc must standardise comparable large sources to mean ~0 / sd ~1"
    assert z[402:].std() < 0.8, "documented behaviour of the pre-registered formula: a source with a much smaller SD than the global SD is compressed by the shrinkage of its variance toward the global variance (m = 5)"
    assert np.all(np.abs(z[400:402]) < 6) and np.isfinite(z).all(), "tiny source is shrunk toward the global statistics, never exploded"
    y2 = y.copy(); y2[:200] += 2.0; z2 = C.causal_labels(idx, y2, srcs, "zc")
    assert np.abs(z2[:200] - z[:200]).max() < 0.2 and np.abs(z2[200:400] - z[200:400]).max() < 0.2, "a realistic offset (+2 label units, the size of real inter-lab offsets) must leave z-labels almost unchanged; (very large shifts also move the global SD that variances shrink toward: a property of the pre-registered formula, stated as a limitation)"
    g = C.causal_labels(idx, y, srcs, "gc"); assert abs(g.mean()) < 1e-9 and g[:200].mean() > g[200:400].mean() + 5, "gc keeps the source offsets (global centring only)"
    zt = C.causal_labels(idx, y, srcs, "zt", y_transductive=list(range(602))); assert list(zt) == list(range(602)), "zt passes the transductive labels through"
    one = C.causal_labels([5], [2.0], ["a"] * 6, "zc"); assert one.shape == (1,) and np.isfinite(one).all(), "a single revealed label must not break (n=1, sd undefined)"
    sub = C.causal_labels(idx[:100], y[:100], srcs, "zc"); full = C.causal_labels(idx, y, srcs, "zc"); assert not np.allclose(sub, full[:100]), "labels depend on the revealed set (causal, grows with it)"


def test_world_disjointness_anchors_and_determinism():
    recs, d, ctx = data(); cnt = collections.Counter(d["srcs"])
    for reg in "ABL":
        for seed in (0, 1, 2):
            W = C.world(recs, d, reg, seed, 5, C.PARAMS); W2 = C.world(recs, d, reg, seed, 5, C.PARAMS)
            assert W == W2, "world must be deterministic"
            sets = {k: set(W[k]) for k in ("init", "anchors", "pool", "E")}
            assert not sets["anchors"] & sets["E"] and not sets["anchors"] & sets["init"] and not sets["anchors"] & sets["pool"] and not sets["E"] & sets["pool"] and not sets["E"] & sets["init"], (reg, seed, "overlap")
            assert W["rev0"] == W["init"] + W["anchors"] and len(set(W["rev0"])) == len(W["rev0"])
            per = collections.Counter(d["srcs"][i] for i in W["anchors"]); assert per and max(per.values()) <= 5 and all(cnt[s] >= 20 for s in per), "k=5 anchors per source with >= 20 peptides"
            if reg == "L":
                held = set(W["held"]); assert 6 <= len(held) <= 18 and all(d["srcs"][i] in held for i in W["E"]) and all(d["srcs"][i] in held for i in W["anchors"]) and all(d["srcs"][i] not in held for i in W["pool"] + W["init"])
                assert set(per) <= held, "regime L anchors come from held-out labs only"
    W0 = C.world(recs, d, "A", 0, 0, C.PARAMS); assert W0["anchors"] == [] and W0["rev0"] == W0["init"], "k=0 sensitivity: no anchors"


def test_world_identical_under_different_hash_seeds():
    code = "import sys,json;sys.path.insert(0,%r);import ladder_core as C,test_ladder as T;recs,d,ctx=T.data();print(json.dumps({r:C.world(recs,d,r,3,5,C.PARAMS) for r in 'ABL'},sort_keys=True))" % HERE
    outs = [subprocess.run([sys.executable, "-c", code], env=dict(os.environ, PYTHONHASHSEED=h), capture_output=True, text=True) for h in ("1", "2")]
    assert all(o.returncode == 0 for o in outs), [o.stderr[-500:] for o in outs]
    assert outs[0].stdout == outs[1].stdout, "world construction differs across PYTHONHASHSEED"


class _Probe:
    """torch-free learner that records every (idx, label) it is ever shown: nothing else may reach it."""
    def __init__(self, X, log): self.X, self.log = X, log
    def init_state(self): return None
    def fit(self, state, idx, y, steps, seed):
        self.log.append((tuple(int(i) for i in idx), tuple(round(float(v), 9) for v in y))); return LM.GBM(self.X).fit(None, idx, y, steps, seed)
    def predict(self, state, idx): return LM.GBM(self.X).predict(state, idx)


def _run(kind, B, W, ctx, scheme, seed=0, p=SMOKE): return C.run_arm(W, "x", B, kind, scheme, seed, p, ctx)


def _strip(rec): return {k: v for k, v in rec.items() if k != "seconds"}


def test_unrevealed_and_heldout_labels_never_reach_the_learner():
    """prereg section 8 no-leak (a) and (b): corrupt (i) every held-out-lab label that is not a revealed anchor (regime L) and (ii) every pool label that is never picked -> the arm's picks, hits and E metrics are identical,
    and the labels the learner saw are identical. Positive control: corrupting a picked label DOES change what the learner sees."""
    recs, d, ctx = data(); X = ctx["X"]
    for reg, scheme in (("L", "zc"), ("A", "zc"), ("L", "zt")):
        W = C.world(recs, d, reg, 1, 5, SMOKE); log0 = []; r0 = _run("loop", _Probe(X, log0), W, ctx, scheme, 1)
        seen = set(W["rev0"]) | {i for pk in r0["picks"] for i in pk}; bad = np.array([i for i in range(len(recs)) if i not in seen]); assert len(bad) > 1000
        c2 = dict(ctx, y_raw=ctx["y_raw"].copy(), y_t=ctx["y_t"].copy()); c2["y_raw"][bad] = 1e6 + c2["y_raw"][bad][::-1]; c2["y_t"][bad] = -1e6
        log1 = []; r1 = _run("loop", _Probe(X, log1), W, c2, scheme, 1)
        assert log0 == log1 and _strip(r0) == _strip(r1), (reg, scheme, "an unrevealed label influenced the learner or the picks")
        pk = r0["picks"][0][0]; c3 = dict(ctx, y_raw=ctx["y_raw"].copy(), y_t=ctx["y_t"].copy()); c3["y_raw"][pk] += 50.0; c3["y_t"][pk] += 50.0; log2 = []; _run("loop", _Probe(X, log2), W, c3, scheme, 1)
        assert log2 != log0, "positive control failed: corrupting a revealed label must change the learner's training labels"
    Wl = C.world(recs, d, "L", 2, 5, SMOKE); held_nonanchor = [i for i in range(len(recs)) if d["srcs"][i] in set(Wl["held"]) and i not in set(Wl["anchors"])]; assert held_nonanchor and not set(held_nonanchor) & set(Wl["pool"])


def test_frozen_and_rule_arms_do_not_learn_and_random_ignores_the_model():
    recs, d, ctx = data(); X = ctx["X"]; W = C.world(recs, d, "A", 0, 5, SMOKE)
    log = []; rf = _run("frozen", _Probe(X, log), W, ctx, "zc"); assert len(log) == 1, "frozen: only the initial fit"
    assert rf["ef5_E"] == rf["ef5_E0"] and rf["auroc_E"] == rf["auroc_E0"], "frozen arm: E metrics unchanged by construction"
    rr = _run("rule", None, W, ctx, "zc"); K = ctx["Kp"]; top = np.argsort(-K[np.array(L.subset(W["pool"], 0, 0, W["rev0"], SMOKE["n_cand"]))], kind="stable")[:SMOKE["batch"]]
    assert set(rr["picks"][0]) == set(np.array(L.subset(W["pool"], 0, 0, W["rev0"], SMOKE["n_cand"]))[top].tolist()), "rule_kphys picks the K_phys top of the round-0 candidates"
    a = _run("random", LM.GBM(X), W, ctx, "zc", 0); b = _run("random", LM.GBM(X), W, ctx, "zc", 0); assert a["picks"] == b["picks"], "random_fb must be reproducible"


def test_kshuf_is_a_within_source_permutation_and_reproducible():
    recs, d, ctx = data(); K = ctx["Kp"]; s = ctx["srcs"]; k1, k2 = C.kshuf(K, s, 3), C.kshuf(K, s, 3); assert np.array_equal(k1, k2) and not np.array_equal(k1, C.kshuf(K, s, 4))
    by = collections.defaultdict(list)
    for i, v in enumerate(s): by[v].append(i)
    for v, ix in by.items(): assert sorted(k1[ix]) == sorted(K[ix]), "multiset of K within a source must be preserved"
    assert (k1 != K).mean() > 0.9, "most K values must move (otherwise the control is vacuous)"
    code = "import sys;sys.path.insert(0,%r);import test_ladder as T,ladder_core as C,hashlib;recs,d,ctx=T.data();print(hashlib.sha256(C.kshuf(ctx['Kp'],ctx['srcs'],3).tobytes()).hexdigest())" % HERE
    o = [subprocess.run([sys.executable, "-c", code], env=dict(os.environ, PYTHONHASHSEED=h), capture_output=True, text=True).stdout for h in ("1", "2")]; assert o[0] == o[1] and o[0], "kshuf differs across PYTHONHASHSEED"


def test_edit_priors_are_neutral_by_default_and_the_rule_loader_refuses_leaks():
    import symbolic as S
    assert all(v[0] == 0.0 for v in S.EDIT_PRIORS.values()), "default edit priors must be neutral (prereg section 2: R4 effects are data-driven only)"
    fm = S.FastMemory(); assert all(v == 0.0 for v in fm.edit_eff.values()), "a fresh memory carries no edit effect"
    rules = {"train_sources": ["A", "B"], "rules": {"N-Me added (with minus without)": {"status": "rule", "effect_z": 0.2, "mined_from": ["A", "B"]}, "D flip (D minus L)": {"status": "no_consistent_direction", "effect_z": 0.1, "mined_from": ["A"]}}}
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f: json.dump(rules, f); path = f.name
    pr = S.edit_priors_from_rules(path, heldout_sources=["Z"]); assert pr["nme_add"][0] == 0.2 and pr["dflip_D"][0] == 0.0 and pr["nme_remove"][0] == -0.2
    for held in (["A"], ["B", "Z"]):
        try: S.edit_priors_from_rules(path, heldout_sources=held); raise RuntimeError("leak not refused")
        except AssertionError: pass
    real = os.path.join(HERE, "..", "kb_audit", "peptide_sar_rules_v1.json")
    if os.path.exists(real):
        j = json.load(open(real)); ts = list(j.get("train_sources", []))
        if ts:
            try: S.edit_priors_from_rules(real, heldout_sources=[ts[0]]); raise RuntimeError("real rule file: held-out train source accepted")
            except AssertionError: pass
    os.unlink(path)


def test_ladder_arms_listed_and_backends_constructible_without_torch_for_baselines():
    import ast
    src = open(os.path.join(HERE, "run_ladder.py")).read(); tree = ast.parse(src); arms = next(n.value for n in tree.body if isinstance(n, ast.Assign) and getattr(n.targets[0], "id", "") == "ARMS")
    names = [e.value for e in arms.elts]; assert names[:5] == ["R0", "R1", "R2", "R3", "R4"] and {"R1_kshuf", "R4_shuf", "R4_frozen", "gbm_aware", "knn", "gp", "random_fb", "rule_kphys"} <= set(names)


def test_aggregator_on_synthetic_results_detects_planted_gain_and_flags_nulls():
    import aggregate_ladder as AG
    rng = np.random.default_rng(0); rows = []
    for reg in ("A", "B", "L"):
        for seed in range(10):
            base = 100 + 5 * rng.standard_normal(); arms = {}
            gain = {"R0": 0, "R1": 40, "R2": 40, "R3": 40, "R4": 40}                         # planted: only M1 adds (+40 hits); M2-M4 add nothing
            for a, g in gain.items(): arms[a] = dict(hits=[int(round((base + g) / 10 + 0.0 * i)) for i in range(10)], auroc_E=0.6 + g / 400 + 0.01 * rng.standard_normal(), ef5_E=1.0, E_score_final=list(rng.standard_normal(40)))
            for a in ("R1_kshuf", "R4_shuf", "random_fb", "gbm_aware", "knn", "gp", "rule_kphys", "R4_frozen"): arms[a] = dict(hits=[int(round(base / 10))] * 10, auroc_E=0.6 + 0.01 * rng.standard_normal(), ef5_E=1.0, E_score_final=list(rng.standard_normal(40)))
            rows.append(dict(seed=seed, regime=reg, scheme="zc", k_anchor=5, arms=arms, E_src=["a"] * 20 + ["b"] * 20, E_hit=[True, False] * 20))
    res = AG.run(rows, planted={"R1", "R2", "R3", "R4"}); st = {m["contrast"]: m["status"] for m in res["modules"]}
    prim = {(p["contrast"], p["regime"]): p for p in res["primary"]}
    assert prim[("R1-R0", "B")]["positive_holm"] and prim[("R1-R0", "L")]["positive_holm"] and prim[("R1-R0", "B")]["mean"] == 40 or abs(prim[("R1-R0", "B")]["mean"] - 40) < 12
    assert not prim[("R2-R1", "B")]["positive_holm"] and not prim[("R4-R3", "L")]["positive_holm"], "null contrasts must not be positive"
    assert st["R2-R1"] != "adds" and st["R3-R2"] != "adds" and st["R4-R3"] != "adds"
    assert st["R1-R0"] == "adds" or res["modules"][0]["criteria"]["same_sign_under_zt"] is None
    assert all(c["within_margin"] for c in res["controls"] if c["metric"] == "Y" and c["gate"]), "synthetic gate controls equal their baselines"
    assert any((not c["within_margin"]) and not c["gate"] for c in res["controls"]), "the K content contrast (R1 - R1_kshuf = +40) must be reported as outside the margin"
    md = AG.to_markdown(res); assert "Holm" in md and "R1-R0" in md
    assert AG.holm(np.array([0.01, 0.04, 0.03]))[0] == 0.03 and abs(AG.bh(np.array([0.01, 0.04, 0.03]))[1] - 0.04) < 1e-12


# ------------------------------------------------------------------ full (torch): planted worlds and rung wiring
SMALL = dict(backbone_cfg=dict(d=32, layers=1, heads=2, max_len=256, kind="encoder"))


def bk(rung, smiles, srcs, K, seed=0, cfg=None):
    import adapter as AD
    return AD.IHLMBackend(rung, smiles, srcs, K, seed, cfg=dict(SMALL, **(cfg or {})))


def _nme_counts(smiles):
    from rdkit import Chem
    P = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])"); return np.array([len(Chem.MolFromSmiles(s).GetSubstructMatches(P)) for s in smiles], float)


def _z(v): v = np.asarray(v, float); return (v - v.mean()) / (v.std() + 1e-9)


def test_rung_wiring_each_switch_changes_the_model():
    import adapter as AD
    recs, d, ctx = data(); rng = np.random.default_rng(0); idx = rng.choice(len(recs), 90, replace=False); sm = [ctx["smiles"][i] for i in idx]; src = [ctx["srcs"][i] for i in idx]; y = _z(_nme_counts(sm)) + 0.3 * rng.standard_normal(90)
    K = _z(_nme_counts(sm)) + 0.2 * rng.standard_normal(90); tr, te = np.arange(60), np.arange(60, 90); preds = {}; states = {}
    for r in ("R0", "R1", "R2", "R3", "R4"):
        B = bk(r, sm, src, K); st = B.fit(B.init_state(), tr, y[tr], 40, 0); m = st.model; states[r] = st; preds[r] = B.predict(st, te)
        want = {"R0": [], "R1": ["K"], "R2": ["K", "offset"], "R3": ["K", "offset", "retrieval"], "R4": ["K", "offset", "retrieval", "edit"]}[r]
        assert list(m.mem.layers) == want, (r, m.mem.layers); assert m.net_trained and m._pack(sm, [None] * len(sm), False) is None, "neural M3/M4 must be off"
        assert all(float(v.abs().sum()) == 0.0 for k, v in m.net.state_dict().items() if k.startswith("edit_res.2.")), "the zero-initialised output layer of the neural edit residual must stay exactly zero (never trained)"; assert set(m.net.modules_on) <= {"M1", "M2"}, "net built without M3/M4"
        assert ("M1" in m.modules) == (r != "R0") and (m.knowledge is not None) == (r != "R0"), "K is only handed to rungs with M1"
    keys = list(preds)
    for a, b in zip(keys, keys[1:]):
        if (a, b) == ("R3", "R4"): continue
        assert not np.allclose(preds[a], preds[b], atol=1e-6), f"{a} -> {b}: the added module changed nothing (a rung that does nothing)"
    assert sum(states["R4"].model.mem.edit_n.values()) == 0 and np.allclose(preds["R3"], preds["R4"], atol=1e-6), "R4 differs from R3 only through learned edit effects: with no edit pair among the revealed rows it must equal R3 exactly (the planted edit world, test_P_edit, shows it differs when pairs exist)"
    assert states["R1"].model.mem.offsets == {} and states["R0"].model.mem.offsets == {}, "offsets only from M2"
    assert states["R2"].model.mem.offsets, "M2 produced no offsets from 60 rows over several sources"
    before = states["R2"].model.mem.digest(); B = bk("R2", sm, src, K); st = B.fit(B.init_state(), tr, y[tr], 10, 0); st2 = B.fit(st, tr, y[tr], 10, 0)
    assert st2.model.mem.digest() == st.model.mem.digest() and st2.model is not st.model, "refitting with already-written rows writes nothing (rows kept as written) and returns a new state"
    assert B.predict(st, te).tolist() == B.predict(st, te).tolist()


def test_P_K_planted_knowledge_effect_is_recovered_by_R1_and_not_R0():
    recs, d, ctx = data(); out = []
    for seed in (0, 1, 2):
        rng = np.random.default_rng(seed); idx = rng.choice(len(recs), 360, replace=False); sm = [ctx["smiles"][i] for i in idx]; src = ["lab"] * 360; nm = _nme_counts(sm); y = _z(nm) + 0.3 * rng.standard_normal(360)
        K = _z(nm); Ksh = rng.permutation(K); tr, te = np.arange(30), np.arange(60, 360); res = {}
        for name, r, kk in (("R0", "R0", K), ("R1", "R1", K), ("R1_kshuf", "R1", Ksh)):
            B = bk(r, sm, src, kk, seed); st = B.fit(B.init_state(), tr, y[tr], 60, seed); res[name] = rho(B.predict(st, te), y[te])
        out.append(res)
    m = {k: float(np.mean([o[k] for o in out])) for k in out[0]}; print("  P-K rho", {k: round(v, 3) for k, v in m.items()})
    assert m["R1"] > 0.55 and m["R1"] - m["R0"] > 0.15, "R1 must recover the planted K effect and beat R0"
    assert m["R1_kshuf"] < 0.3 and m["R1"] - m["R1_kshuf"] > 0.25, "permuted K must not give the gain (K content matters)"


def test_P_offset_planted_source_offsets_recovered_with_k5_anchors_by_R2_and_not_R1():
    recs, d, ctx = data(); errs, r1s, r2s = [], [], []
    for seed in (0, 1, 2):
        rng = np.random.default_rng(seed); n = 390; idx = rng.choice(len(recs), n, replace=False); sm = [ctx["smiles"][i] for i in idx]; labs = np.array(["s0", "s1", "s2"] * (n // 3)); b_true = {"s0": 1.5, "s1": -1.5, "s2": 0.0}
        nm = _nme_counts(sm); y = _z(nm) + np.array([b_true[s] for s in labs]) + 0.2 * rng.standard_normal(n); K = _z(nm) + 0.1 * rng.standard_normal(n); te = np.arange(150, n)
        anchors = [j for s in b_true for j in np.where(labs == s)[0][:5]]; rev = sorted(set(range(30)) | set(anchors)); rest_te = np.array([j for j in te if j not in set(rev)])
        res = {}
        for r in ("R1", "R2"):
            B = bk(r, sm, list(labs), K, seed); st = B.fit(B.init_state(), np.array(rev), y[rev], 60, seed); res[r] = (st.model.mem.offsets, rho(B.predict(st, rest_te), y[rest_te]))
        assert res["R1"][0] == {}, "R1 has no offset module"
        bh = res["R2"][0]; assert set(bh) == set(b_true), bh
        bt = np.array([b_true[s] for s in sorted(b_true)]); bt = bt - bt.mean(); be = np.array([bh[s] for s in sorted(b_true)]); be = be - be.mean(); errs.append(float(np.abs(be - bt).max() / y.std())); r1s.append(res["R1"][1]); r2s.append(res["R2"][1])
    print("  P-offset max err/SD(y)", [round(e, 3) for e in errs], "rho R1", np.round(r1s, 3), "R2", np.round(r2s, 3))
    assert max(errs) < 0.15, f"offset error {errs} not below 0.15 SD with k=5 anchors"
    assert np.mean(r2s) - np.mean(r1s) > 0.05, "R2 must rank held-out peptides better than R1 when sources carry offsets"


def test_P_retrieval_planted_series_effect_improves_R3_over_R2_on_revealed_series():
    recs, d, ctx = data(); flat = d["flat"]; g = collections.defaultdict(list)
    for i, f in enumerate(flat): g[f].append(i)
    keys = sorted(k for k, v in g.items() if len(v) >= 4); gains, r3s, r2s = [], [], []
    for seed in (0, 1, 2):
        rng = np.random.default_rng(seed); sel = [keys[i] for i in rng.choice(len(keys), 50, replace=False)]; idx, ser = [], []
        for k, key in enumerate(sel):
            m = sorted(g[key])[:6]; idx += m; ser += [k] * len(m)
        idx = np.array(idx); ser = np.array(ser); eff = rng.normal(0, 1.5, len(sel)); y = eff[ser] + 0.15 * rng.standard_normal(len(idx)); sm = [ctx["smiles"][i] for i in idx]; K = rng.standard_normal(len(idx))
        rev = np.array([j for k in range(len(sel)) for j in np.where(ser == k)[0][:2]]); te = np.array([j for j in range(len(idx)) if j not in set(rev)]); res = {}
        for r in ("R2", "R3"):
            B = bk(r, sm, ["lab"] * len(idx), K, seed); st = B.fit(B.init_state(), rev, y[rev], 60, seed); res[r] = rho(B.predict(st, te), y[te])
        r2s.append(res["R2"]); r3s.append(res["R3"]); gains.append(res["R3"] - res["R2"])
    print("  P-retrieval rho R2", np.round(r2s, 3), "R3", np.round(r3s, 3))
    assert np.mean(r3s) > 0.5 and np.mean(gains) > 0.2, "symbolic analog retrieval must recover a planted series effect"


def test_P_edit_planted_nme_add_effect_is_recovered_by_R4_and_R4_beats_R3():
    import symbolic as S
    recs, d, ctx = data(); rng = np.random.default_rng(0); par, chi = [], []
    for i in rng.permutation(len(recs)):
        s = ctx["smiles"][i]
        if len(par) >= 160: break
        if len(s) > 250: continue
        for t, ns in S.propose_edit_smiles(s):
            if t == "nme_add" and S.edit_type(ns, s) == "nme_add": par.append(s); chi.append(ns); break
    n = len(par); assert n >= 120, f"only {n} N-Me-add children could be generated"; delta = 1.0
    yp = rng.standard_normal(n) * 1.0; yc = yp + delta + 0.1 * rng.standard_normal(n); sm = par + chi; y = np.concatenate([yp, yc]); K = rng.standard_normal(2 * n); src = ["lab"] * (2 * n)
    held = np.arange(n + 100, 2 * n); rev = np.array(sorted(set(range(2 * n)) - set(held.tolist()))); res = {}
    for r in ("R3", "R4"):
        B = bk(r, sm, src, K, 0); st = B.fit(B.init_state(), rev, y[rev], 30, 0); mem = st.model.mem
        est = np.array([mem.retrieval(sm[j], None)[0] for j in held]); res[r] = (float(np.mean(np.abs(est - y[held]))), mem.edit_eff["nme_add"], rho(B.predict(st, held), y[held]))
    print("  P-edit (MAE, edit_eff[nme_add], rho)", {k: tuple(round(x, 3) for x in v) for k, v in res.items()})
    assert res["R3"][1] == 0.0, "R3 has no edit layer"
    assert 0.6 < res["R4"][1] < 1.2, f"nme_add effect {res['R4'][1]:.3f} not recovered (planted {delta}, prior shrinkage 20)"
    assert res["R4"][0] < 0.6 * res["R3"][0], "R4 retrieval error must be clearly below R3's on children whose parent was revealed"


def test_ihlm_rungs_only_see_revealed_labels_through_the_runner():
    import ladder_core as C2
    recs, d, ctx = data(); import run_ladder as RL
    W = C2.world(recs, d, "L", 1, 5, SMOKE)
    for arm in ("R0", "R1", "R2", "R3", "R4", "R1_kshuf", "R4_shuf", "R4_frozen"):
        ctx["Kshuf"] = C2.kshuf(ctx["Kp"], ctx["srcs"], 1); B, kind = RL.make_backend(arm, ctx, 1); r0 = _run(kind, B, W, ctx, "zc", 1)
        seen = set(W["rev0"]) | {i for pk in r0["picks"] for i in pk}
        if arm == "R4_shuf": seen |= set(W["pool"])           # by design (L7d) the shuffled control draws its labels from the pool's label vector; everything OUTSIDE the pool (held-out labs) must still be invisible
        bad = np.array([i for i in range(len(recs)) if i not in seen]); assert len(bad) > 500
        c2 = dict(ctx, y_raw=ctx["y_raw"].copy(), y_t=ctx["y_t"].copy()); c2["y_raw"][bad] = 1e6 + c2["y_raw"][bad][::-1]; c2["y_t"][bad] = -1e6
        B2, kind2 = RL.make_backend(arm, c2, 1); r1 = _run(kind2, B2, W, c2, "zc", 1)
        assert _strip(r0) == _strip(r1), f"{arm}: an unrevealed or held-out-lab label changed the result"
        print("  isolation ok", arm, "hits", sum(r0["hits"]), "auroc_E", round(r0["auroc_E"], 3))


def test_runner_smoke_output_is_deterministic_across_hash_seeds_and_aggregator_readable():
    import aggregate_ladder as AG
    outs = []
    for h in ("1", "2"):
        od = tempfile.mkdtemp(); p = subprocess.Popen([sys.executable, os.path.join(HERE, "run_ladder.py"), CSV, od, "--regimes", "L", "--seeds", "0", "--smoke", "--arms", "R0,R1,R3,R4,R1_kshuf,R4_shuf,gbm_aware,knn,random_fb,rule_kphys"],
                             env=dict(os.environ, PYTHONHASHSEED=h, OMP_NUM_THREADS="1"), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True); outs.append((od, p))
    texts = [p.communicate()[0] for _, p in outs]; assert all(p.returncode == 0 for _, p in outs), [t[-800:] for t in texts]
    f = "ladder_L_zc_k5_0.json"; j = [json.load(open(os.path.join(od, f))) for od, _ in outs]
    for a in j[0]["arms"]:
        assert _strip(j[0]["arms"][a]) == _strip(j[1]["arms"][a]), f"arm {a} differs across PYTHONHASHSEED"
    rows = AG.load_dir(outs[0][0]); assert rows and all({"hits", "auroc_E", "ef5_E"} <= set(v) for r in rows for v in r["arms"].values())
    assert AG.total_hits(j[0]["arms"]["R0"]) == sum(j[0]["arms"]["R0"]["hits"]) and len(j[0]["E"]) == len(j[0]["E_hit"]) == len(j[0]["arms"]["R0"]["E_score_final"])


CORE = [v for k, v in sorted(globals().items()) if k.startswith("test_") and k in (
    "test_causal_labels_use_only_the_revealed_set_and_shrink_correctly", "test_world_disjointness_anchors_and_determinism", "test_world_identical_under_different_hash_seeds",
    "test_unrevealed_and_heldout_labels_never_reach_the_learner", "test_frozen_and_rule_arms_do_not_learn_and_random_ignores_the_model", "test_kshuf_is_a_within_source_permutation_and_reproducible",
    "test_edit_priors_are_neutral_by_default_and_the_rule_loader_refuses_leaks", "test_ladder_arms_listed_and_backends_constructible_without_torch_for_baselines", "test_aggregator_on_synthetic_results_detects_planted_gain_and_flags_nulls")]
FULL = [v for k, v in sorted(globals().items()) if k.startswith("test_") and v not in CORE]

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"; run = (CORE if which in ("core", "all") else []) + (FULL if which in ("full", "all") else []); bad = 0
    if which in ("full", "all"):
        try: import torch  # noqa: F401
        except ImportError: print("FAIL import torch: the full suite needs torch (install it before the pre-flight)"); sys.exit(2)
    for t in run:
        try: t(); print("PASS", t.__name__, flush=True)
        except Exception as e:
            bad += 1; import traceback; traceback.print_exc(); print("FAIL", t.__name__, repr(e)[:300], flush=True)
    print("core rc=%d" % (1 if bad else 0) if which == "core" else ("full rc=%d" % (1 if bad else 0))); sys.exit(1 if bad else 0)
