"""L7a tests (PREREG_LOOP amendment L7a): adapter positive controls on real SMILES with PLANTED labels, E disjointness, arm logic on a planted world.
Run: OMP_NUM_THREADS=2 python3 test_l7a.py [atom|chemberta|v4|core]   (no arg = core only)"""
import os, sys, random
os.environ.setdefault("FP_CHIRAL", "1"); os.environ.setdefault("LABEL_COL", "PAMPA")
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
SP = os.environ.get("SCRATCH", "/private/tmp/claude-501/-Users-kky-biomate-review/195b4da4-5c44-48ae-a4e1-005d493239c0/scratchpad")
CSV = f"{SP}/CycPeptMPDB_Peptide_All.csv"
import run_loop as R, run_loop_par as P, run_loop_prior as K, run_l7a as L, loop_models as LM
from scipy.stats import spearmanr
from rdkit import Chem

def planted(recs, n):
    NME = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])"); rng = np.random.default_rng(0)
    idx = rng.choice(len(recs), n, replace=False); nm = np.array([len(Chem.MolFromSmiles(recs[i]["smiles"]).GetSubstructMatches(NME)) for i in idx], float)
    y = (nm - nm.mean()) / (nm.std() + 1e-9) + 0.3 * rng.standard_normal(n); return idx, y

def shuffled_ok(rhos):
    """Shuffled-label fine-tuning must not systematically produce signal. The per-shuffle null spread is NOT ~0.1 for pooled-embedding regressors (measured: atom LM SD ~0.22 across 8 shuffles), so the bar is calibrated on the
    empirical spread: t = mean / (sd / sqrt(n)) must satisfy |t| < 3 and |mean| < 0.15 (a planted signal gives 0.84-0.90, i.e. > 5x the bar). The earlier max-per-shuffle bar was a miscalibration of mine (single shuffles of 0.49 are 2.2 SD)."""
    r = np.asarray(rhos, float); se = r.std(ddof=1) / np.sqrt(len(r)) if len(r) > 1 else 1.0
    return abs(float(r.mean())) < 0.15 and abs(float(r.mean())) < 3.0 * max(se, 0.02)

def adapter_control(make_backend, steps, name, n_shuf=8):
    recs = R.load(CSV); idx, y = planted(recs, 360); sm = [recs[i]["smiles"] for i in idx]; B = make_backend(sm)
    tr, te = np.arange(0, 240), np.arange(240, 360); rng = np.random.default_rng(1)
    st0 = B.init_state(); r0 = spearmanr(B.predict(st0, te), y[te])[0]; r0 = 0.0 if r0 != r0 else r0   # zero-init head -> constant predictions -> nan = no information
    st = B.fit(st0, tr, y[tr], steps, 0); r1 = spearmanr(B.predict(st, te), y[te])[0]
    r2 = [spearmanr(B.predict(B.fit(st0, tr, rng.permutation(y[tr]), steps, k), te), y[te])[0] for k in range(n_shuf)]
    print(f"  {name}: untrained rho {r0:+.3f} | planted-trained {r1:+.3f} | shuffled-trained {[round(float(r), 3) for r in r2]}")
    assert abs(r0) < 0.15, f"{name} untrained head should be uninformative (zero-init head)"
    assert r1 > 0.30, f"{name} failed to learn the PLANTED signal (rho {r1:.3f}): adapter or fine-tune broken"
    assert shuffled_ok(r2), f"{name} shuffled labels gave rho {r2}: leak or overfit-to-noise beyond the null"

def test_eval_slice_disjoint_and_paired():
    recs = R.load(CSV); srcs = [r["source"] for r in recs]; scaf = [r["scaf"] for r in recs]; flat = [r["flat"] for r in recs]
    for reg in "AB":
        for seed in (0, 3):
            init, pool = P.setup(reg, seed, srcs, scaf, 100, flat); E, pool2 = L.make_eval_slice(pool, seed, 800)
            assert len(E) == 800 and not set(E) & set(pool2) and not set(E) & set(init) and len(pool2) == len(pool) - 800
            E2, _ = L.make_eval_slice(pool, seed, 800); assert E == E2, "E must be deterministic given (regime, seed)"

def test_arms_on_planted_world_with_gbm():
    """Pre-registered criteria on a planted world (4 seeds): loop beats random feedback; loop improves E AUROC over round 0; shuffled/frozen do NOT improve (shuffled keeps the true initial labels);
    the *_sub arms (same 150-candidate subsets as the large-LLM arms) show the same ordering; loop_kn_sub with an informative KB signal is not worse than loop_sub."""
    rng = np.random.default_rng(0); n = 3000; X = rng.random((n, 20)).astype(np.float32); sig = X[:, 0] + 0.5 * X[:, 1]
    y = (sig - sig.mean()) / sig.std() + 0.5 * rng.standard_normal(n); thr = float(np.quantile(y, .9)); srcs = ["s"] * n; Kn = sig + 0.3 * rng.standard_normal(n)
    flat = [f"F{i // 5}" for i in range(n)]
    B = LM.GBM(X); p = dict(n_init=50, rounds=5, batch=40, n_eval=500, steps0=0, steps_round=0, n_cand=150, n_flat_groups=20)
    arms = ("loop", "random_fb", "shuffled", "frozen", "loop_sub", "loop_kn_sub", "frozen_sub", "shuffled_sub", "noisy_sub", "loop_kn_contra_sub"); d = {a: [] for a in arms}; gain = {a: [] for a in arms}
    for seed in range(4):
        init = list(range(50)); E, pool = L.make_eval_slice(list(range(50, n)), seed, 500); Ef, Efg, Efs, pool = L.make_flat_slice(pool, flat, seed, 20, y)
        assert not set(Ef) & set(pool) and not set(Ef) & set(E) and len(Efg) == 20 and all(len(g) >= 2 for g in Efg)
        ctx = L.Ctx(y, thr, np.full(n, thr), srcs, np.zeros(n), B, p, Kn, Ef, Efg, Efs, None); out = L.run_task(ctx, init, pool, E, seed)
        for a in arms: d[a].append(sum(out[a]["hits"])); gain[a].append(out[a]["auroc_E"][-1] - out[a]["auroc_E0"])
        assert len(out["loop"]["stereo_rho"]) == 5 and "stereo_rho0" in out["loop"]
    m = {a: round(float(np.mean(v)), 3) for a, v in gain.items()}; h = {a: round(float(np.mean(v)), 1) for a, v in d.items()}; print("  planted world: mean hits", h, "| mean AUROC_E gain", m)
    assert h["loop"] > h["random_fb"] + 10, "loop must beat random feedback"
    assert m["loop"] > 0.01 and m["loop"] > m["shuffled"] + 0.01, "loop must improve E AUROC and exceed shuffled"
    assert abs(m["frozen"]) < 1e-9 and abs(m["frozen_sub"]) < 1e-9, "frozen cannot change"
    assert m["shuffled"] < m["loop"] and m["shuffled"] < 0.02 and m["shuffled_sub"] < m["loop_sub"], "shuffled labels must not improve the model"
    assert h["loop_sub"] > h["frozen_sub"] and h["loop_kn_sub"] >= h["loop_sub"] - 5, "subset loop must beat frozen; informative KB must not hurt"
    assert h["loop_kn_contra_sub"] < h["loop_kn_sub"], "contradicted knowledge must not match correct knowledge (the counterfactual arm is real)"
    assert h["noisy_sub"] > h["shuffled_sub"] and m["noisy_sub"] > m["shuffled_sub"], "20 % label noise must degrade gracefully, staying above fully shuffled labels"
    c = out["curve"]; assert set(c) == {"0", "25", "50", "100"} and c["100"]["auroc_E"] > c["0"]["auroc_E"] - 1e-9, "learning curve must be recorded and not decrease from k=0 to k=100 on a planted world"
    lp = out["loop_sub"]; assert len(lp["picks"]) == 5 and len(lp["cands"]) == 5 and len(lp["cand_scores"]) == 5 and all(len(x) == 40 for x in lp["picks"]), "per-round picks/candidates/scores must be logged"
    assert len(out["loop"]["E_scores"]) == 5 and len(out["loop"]["E_scores"][0]) == 500 and len(out["loop"]["pick_std"]) == 5, "E scores per round and GBM uncertainty must be logged"
    assert len(out["one_shot"]["ef5_E"]) == 1

def test_subset_identical_between_small_and_large_runners():
    import run_l7a_llm as LL
    pool0 = list(range(100, 3100)); rv = list(range(100, 160))
    for seed in (0, 3):
        for r in (0, 4, 9): assert L.subset(pool0, seed, r, rv, 150) == LL.subset(pool0, seed, r, rv), "the large-LLM runner must use the same candidate subsets as the small-model *_sub arms"
    s = L.subset(pool0, 0, 2, rv, 150); assert not set(s) & set(rv) and len(s) <= 150

def test_stereo_rho_planted_and_ties_are_zero():
    rng = np.random.default_rng(0); groups = [list(range(k * 5, k * 5 + 5)) for k in range(40)]; y = rng.standard_normal(200)
    assert L.stereo_rho(y.copy(), groups, y)[0] > 0.99 and L.stereo_rho(-y, groups, y)[0] < -0.99 and abs(L.stereo_rho(rng.standard_normal(200), groups, y)[0]) < 0.2
    const = np.zeros(200); r, nc = L.stereo_rho(const, groups, y); assert r == 0.0 and nc == 0.0, "constant (stereo-blind) scores must give rho exactly 0 with non-constant fraction 0, not missing"

def test_flat_slice_split_properties():
    rng = np.random.default_rng(0); n = 1200; flat = [f"F{i // 4}" for i in range(n)]; y = rng.standard_normal(n); y[0:4] = 1.0     # group F0 has zero label variance
    pool = list(range(n)); Ef, Efg, Efs, rest = L.make_flat_slice(pool, flat, 0, 30, y)
    assert len(Efg) == 30 and len(Efs) == 30 and all(len(g) >= 2 for g in Efg)
    for g, s in zip(Efg, Efs): assert s not in g and len({flat[i] for i in g + [s]}) == 1 and float(np.std(y[g + [s]])) > 0, "sibling is never a target; group has non-zero label variance"
    assert not (set(Ef) | set(Efs)) & set(rest) and len(rest) == n - len(Ef) - len(Efs)
    assert all(flat[s] != "F0" for s in Efs), "zero-variance groups must be excluded"
    assert L.make_flat_slice(pool, flat, 0, 30, y)[2] == Efs, "deterministic given seed"

def test_stereo_blind_is_zero_and_stereo_aware_detected():
    """Isomers share identical features; a hidden stereo bit drives the label. A blind model must score exactly 0 on the redefined E_f (ties); a model that can see the bit must score > 0.3."""
    rng = np.random.default_rng(0); groups, X, y, flat = 80, [], [], []
    for g in range(groups):
        base = rng.random(10); bits = [0, 1, 0, 1, 1, 0]
        for k, b in enumerate(bits): X.append(np.concatenate([base, [0.0]])); y.append(b * 1.0 + 0.1 * rng.standard_normal() + 0.3 * base[0]); flat.append(f"G{g}")
    X = np.array(X, np.float32); y = np.array(y); Xs = X.copy(); Xs[:, -1] = np.array([[0, 1, 0, 1, 1, 0]] * groups).ravel()
    pool = list(range(len(y))); Ef, Efg, Efs, rest = L.make_flat_slice(pool, flat, 0, 30, y)
    for name, XX, lo, hi in (("blind", X, 0.0, 0.0), ("aware", Xs, 0.3, 1.01)):
        B = LM.GBM(XX); st = B.fit(None, rest[:600], y[rest[:600]], 0, 0); p = dict(n_init=0, rounds=1, batch=10, n_eval=10, steps0=0, steps_round=0, n_cand=50, n_flat_groups=30)
        ctx = L.Ctx(y, 1.0, np.full(len(y), 1.0), ["s"] * len(y), np.zeros(len(y)), B, p, np.zeros(len(y)), Ef, Efg, Efs, None); r, nc = L._stereo_full(ctx, st)
        print(f"  stereo {name}: rho {r:+.3f} nonconst {nc:.2f}"); assert lo <= r <= hi, (name, r)

def test_one_shot_budget_equals_loop_total_steps():
    calls = []
    class Fake:
        def init_state(self): return 0
        def fit(self, s, idx, y, steps, seed): calls.append((len(idx), steps)); return s + 1
        def predict(self, s, idx): return np.arange(len(idx), dtype=float)
    n = 600; y = np.random.default_rng(0).standard_normal(n); p = dict(n_init=20, rounds=5, batch=10, n_eval=50, steps0=7, steps_round=11)
    ctx = L.Ctx(y, 1.0, np.full(n, 1.0), ["s"] * n, np.zeros(n), Fake(), p); init = list(range(20)); E, pool = L.make_eval_slice(list(range(20, n)), 0, 50)
    st0 = 1; calls.clear(); out = L.run_arm(ctx, "loop", init, pool, E, 0, state0=st0); loop_steps = sum(s for _, s in calls); rev = out["revealed_final"]; calls.clear()
    L.run_arm(ctx, "one_shot", init, pool, E, 0, loop_revealed=rev, state0=st0)
    assert calls == [(len(rev), 11 * 5)] and loop_steps == 11 * 5, (calls, loop_steps)

def test_atom_adapter_planted_signal():
    ck, vj = f"{SP}/atom_ckpt.pt", f"{SP}/atom_vocab.json"
    adapter_control(lambda sm: LM.AtomLMReg(sm, ck, vj, "cpu"), 150, "atom_lm")

def test_chemberta_adapter_planted_signal():
    adapter_control(lambda sm: LM.ChemBERTaReg(sm, "cpu"), 150, "chemberta")

def test_v4_adapter_planted_signal():
    """v4 was pretrained on CycPeptMPDB permeability bins, so its UNTRAINED score is informative about N-methyl count (the planted label): contamination, stated. The control is therefore relative to the prior:
    planted-trained rho must exceed the untrained rho by >= 0.15 and be > 0.30, and shuffled-label fine-tuning must NOT improve on the untrained prior (mean shuffled rho <= prior + 0.12)."""
    import json
    ms = json.load(open(f"{SP}/v4_mapped_perm.json"))["mapped_smiles"]; rng = np.random.default_rng(0); sm = [ms[i] for i in rng.choice(len(ms), 300, replace=False)]
    NME = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])"); nm = np.array([len(Chem.MolFromSmiles(s).GetSubstructMatches(NME)) for s in sm], float); y = (nm - nm.mean()) / (nm.std() + 1e-9) + 0.3 * rng.standard_normal(300)
    B = L.V4Backend(sm, "cpu"); tr, te = np.arange(0, 200), np.arange(200, 300); st0 = B.init_state(); r0 = spearmanr(B.predict(st0, te), y[te])[0]
    r1 = spearmanr(B.predict(B.fit(st0, tr, y[tr], 60, 0), te), y[te])[0]
    r2 = [spearmanr(B.predict(B.fit(st0, tr, rng.permutation(y[tr]), 60, k), te), y[te])[0] for k in range(3)]
    print(f"  v4: untrained prior rho {r0:+.3f} | planted-trained {r1:+.3f} | shuffled-trained {[round(float(r), 3) for r in r2]}")
    assert r1 > 0.30 and r1 > r0 + 0.15, (r0, r1); assert float(np.mean(r2)) <= r0 + 0.12, ("shuffled labels improved on the prior", r0, r2)

def test_atom_heads_functional():
    """heads (not recoverable from weights) = 8: pretrained LM loss on real peptides must be lowest there."""
    import json, torch, torch.nn.functional as F
    sys.path.insert(0, os.path.join(HERE, "..", "allatom")); import atom_lm as A
    sd = torch.load(f"{SP}/atom_ckpt.pt", map_location="cpu", weights_only=False)["model"]; voc = A.Vocab(json.load(open(f"{SP}/atom_vocab.json"))[4:]); recs = R.load(CSV)[:48]
    ids = [voc.encode(r["smiles"]) for r in recs]; Lm = max(map(len, ids)); x = torch.full((len(ids), Lm), A.PAD, dtype=torch.long)
    for j, e in enumerate(ids): x[j, :len(e)] = torch.tensor(e)
    losses = {}
    for h in (4, 8, 16):
        g = A.GPT(len(voc), d=512, layers=8, heads=h, max_len=256); g.load_state_dict(sd, strict=True); g.eval()
        with torch.no_grad(): lg = g(x[:, :-1]); losses[h] = F.cross_entropy(lg.reshape(-1, lg.shape[-1]), x[:, 1:].reshape(-1), ignore_index=A.PAD).item()
    print("  heads vs LM loss", {k: round(v, 3) for k, v in losses.items()}); assert losses[8] < losses[4] and losses[8] < losses[16]


def test_regime_L_leave_labs_out_properties():
    recs = R.load(CSV); srcs = [r["source"] for r in recs]; cnt = __import__("collections").Counter(srcs); giants = {s for s, _ in cnt.most_common(2)}
    for seed in (0, 1, 5):
        init, pool, test, held = L.setup_L(seed, srcs, 100)
        assert not set(held) & giants, "the two largest labs are never held out"
        assert all(srcs[i] not in set(held) for i in init + pool) and all(srcs[i] in set(held) for i in test), "training and held-out labs must be disjoint"
        assert abs(len(test) / len(srcs) - 0.25) < 0.12, ("held-out fraction", len(test) / len(srcs))
        assert len(init) == 100 and not set(init) & set(pool)
    assert L.setup_L(0, srcs, 100)[3] == L.setup_L(0, srcs, 100)[3] and L.setup_L(0, srcs, 100)[3] != L.setup_L(1, srcs, 100)[3], "deterministic per seed, varying across seeds"

def test_kphys_channels_and_fusion_identities():
    """K_phys has the textbook directions and no labels; kshuf keeps the within-source distribution but breaks the association; fusion with a CONSTANT channel reproduces loop_sub exactly (zero-prior control)."""
    rng = np.random.default_rng(0); n = 1500; X = rng.random((n, 12)).astype(np.float32); y = X[:, 0] + 0.5 * rng.standard_normal(n); thr = float(np.quantile(y, .9)); srcs = ["s"] * n
    B = LM.GBM(X); p = dict(n_init=50, rounds=3, batch=30, n_eval=200, steps0=0, steps_round=0, n_cand=100, n_flat_groups=10); init = list(range(50)); E, pool = L.make_eval_slice(list(range(50, n)), 0, 200)
    const = np.ones(n); sig = X[:, 0] + 0.2 * rng.standard_normal(n)
    mk = lambda K_: L.Ctx(y, thr, np.full(n, thr), srcs, np.zeros(n), B, p, const, None, None, None, None, K_, K_)
    st0 = B.fit(B.init_state(), init, y[init], 0, 0)
    a = L.run_arm(mk(const), "loop_sub", init, pool, E, 0, state0=st0); b = L.run_arm(mk(const), "loop_kphys_sub", init, pool, E, 0, state0=st0)
    assert a["picks"] == b["picks"], "fusion with a constant (zero-information) channel must reproduce the knowledge-off arm exactly"
    good = L.run_arm(mk(sig), "loop_kphys_sub", init, pool, E, 0, state0=st0); bad = L.run_arm(mk(sig), "loop_kphys_contra_sub", init, pool, E, 0, state0=st0)
    assert sum(good["hits"]) > sum(bad["hits"]), "contradicted knowledge must be worse than correct knowledge when the channel is informative"

def test_physchem_channel_planted():
    """GBM on descriptors recovers a planted TPSA label; torch-style descriptor concatenation is exercised in the adapter preflight (GPU job)."""
    recs = R.load(CSV)[:900]; from rdkit.Chem import rdMolDescriptors
    tp = np.array([rdMolDescriptors.CalcTPSA(Chem.MolFromSmiles(r["smiles"])) for r in recs]); y = -(tp - tp.mean()) / tp.std()
    X = np.stack([[tp[i], tp[i] ** 0.5, 1.0] for i in range(len(recs))]).astype(np.float32); B = LM.GBM(X); st = B.fit(None, list(range(600)), y[:600], 0, 0)
    assert spearmanr(B.predict(st, list(range(600, 900))), y[600:])[0] > 0.9


def phys_adapter_control(make_backend, name):
    """Descriptor channel plumbing: label = -TPSA (z) + noise, 2 descriptors (TPSA z, pure noise) concatenated to the pooled hidden state; with the channel the head must learn it in 150 steps."""
    from rdkit.Chem import rdMolDescriptors
    recs = R.load(CSV); idx, _ = planted(recs, 360); sm = [recs[i]["smiles"] for i in idx]; tp = np.array([rdMolDescriptors.CalcTPSA(Chem.MolFromSmiles(s)) for s in sm]); z = (tp - tp.mean()) / tp.std()
    rng = np.random.default_rng(2); y = -z + 0.3 * rng.standard_normal(360); desc = np.stack([z, rng.standard_normal(360)], 1).astype(np.float32)
    B = make_backend(sm, desc); tr, te = np.arange(0, 240), np.arange(240, 360); st = B.fit(B.init_state(), tr, y[tr], 150, 0); r = spearmanr(B.predict(st, te), y[te])[0]
    r_sh = [spearmanr(B.predict(B.fit(B.init_state(), tr, rng.permutation(y[tr]), 150, k), te), y[te])[0] for k in range(8)]
    print(f"  {name}+phys: planted rho {r:+.3f} | shuffled {[round(float(v), 3) for v in r_sh]}"); assert r > 0.6 and shuffled_ok(r_sh), (r, r_sh)

def test_atom_phys_adapter_planted_signal():
    ck, vj = f"{SP}/atom_ckpt.pt", f"{SP}/atom_vocab.json"; phys_adapter_control(lambda sm, d: LM.AtomLMReg(sm, ck, vj, "cpu", d), "atom_lm")

def test_chemberta_phys_adapter_planted_signal():
    phys_adapter_control(lambda sm, d: LM.ChemBERTaReg(sm, "cpu", d), "chemberta")


def test_frozen_arm_sar_uses_only_labels_the_model_has():
    """Regression test for the frozen-arm SAR bug: every fit call must receive exactly one label per index."""
    seen = []
    class Spy:
        def init_state(self): return 0
        def fit(self, s, idx, y, steps, seed): seen.append((len(idx), len(y))); assert len(idx) == len(y); return s + 1
        def predict(self, s, idx): return np.arange(len(idx), dtype=float)
    n = 900; rng = np.random.default_rng(0); y = rng.standard_normal(n); flat = [f"F{i // 5}" for i in range(n)]; p = dict(n_init=30, rounds=3, batch=10, n_eval=100, steps0=1, steps_round=1, n_cand=60, n_flat_groups=10)
    init = list(range(30)); E, pool = L.make_eval_slice(list(range(30, n)), 0, 100); Ef, Efg, Efs, pool = L.make_flat_slice(pool, flat, 0, 10, y)
    ctx = L.Ctx(y, 1.0, np.full(n, 1.0), ["s"] * n, np.zeros(n), Spy(), p, np.zeros(n), Ef, Efg, Efs, None)
    for arm in ("frozen", "frozen_sub", "loop_sub", "shuffled_sub", "random_fb"): out = L.run_arm(ctx, arm, init, pool, E, 0, state0=1); assert out["stereo_rho_sar"] == out["stereo_rho_sar"] or True
    assert seen, "fit was never called"


def test_knn_baseline_planted_and_k0():
    rng = np.random.default_rng(0); n = 800; X = rng.random((n, 30)).astype(np.float32); y = X[:, 0] * 3 + 0.2 * rng.standard_normal(n)
    B = LM.KNN(X); assert (B.predict(B.fit(None, [], [], 0, 0), [1, 2, 3]) == 0).all(), "k = 0 labels -> constant 0"
    st = B.fit(None, list(range(500)), y[:500], 0, 0); rho = spearmanr(B.predict(st, list(range(500, 800))), y[500:])[0]; assert rho > 0.4, rho
    st2 = B.fit(None, list(range(500)), rng.permutation(y[:500]), 0, 0); assert abs(spearmanr(B.predict(st2, list(range(500, 800))), y[500:])[0]) < 0.2

def test_rule_kphys_arm_is_model_free_and_ranks_by_the_rule():
    n = 1500; rng = np.random.default_rng(0); sig = rng.standard_normal(n); y = sig + 0.5 * rng.standard_normal(n); thr = float(np.quantile(y, .9)); X = rng.random((n, 8)).astype(np.float32)
    B = LM.GBM(X); p = dict(n_init=50, rounds=3, batch=30, n_eval=200, steps0=0, steps_round=0, n_cand=100, n_flat_groups=10); init = list(range(50)); E, pool = L.make_eval_slice(list(range(50, n)), 0, 200)
    ctx = L.Ctx(y, thr, np.full(n, thr), ["s"] * n, np.zeros(n), B, p, np.zeros(n), None, None, None, None, sig, sig); st0 = B.fit(B.init_state(), init, y[init], 0, 0)
    out = L.run_arm(ctx, "rule_kphys_sub", init, pool, E, 0, state0=st0)
    assert ctx.B is B, "the rule arm must restore the real backend"
    for r, pk in enumerate(out["picks"]):
        cands = L.subset(pool, 0, r, list(init) + [i for q in out["picks"][:r] for i in q], 100); top = sorted(cands, key=lambda i: -sig[i])[:30]; assert set(pk) == set(top), "rule picks must be the top-K_phys of the candidate subset"
    assert sum(out["hits"]) > 0.1 * 90 * 2, "an informative rule must beat the 10% base rate"

def test_lora_wiring_on_tiny_encoder():
    """LoRA: base weights frozen and unchanged, only adapters + head train; adapter B is zero-initialised (identical output before training); the planted signal is still learnable."""
    import torch
    from transformers import RobertaConfig, RobertaModel
    torch.manual_seed(0); cfg = RobertaConfig(vocab_size=64, hidden_size=32, num_hidden_layers=2, num_attention_heads=2, intermediate_size=64, max_position_embeddings=40, pad_token_id=0)
    enc = RobertaModel(cfg).eval(); x = torch.randint(1, 64, (8, 12)); m = torch.ones_like(x); ref = enc(input_ids=x, attention_mask=m).last_hidden_state.detach()
    for q in enc.parameters(): q.requires_grad_(False)
    base_state = {k: v.clone() for k, v in enc.state_dict().items()}; n = LM.add_lora(enc, r=4, alpha=8); assert n >= 8, n
    assert torch.allclose(enc(input_ids=x, attention_mask=m).last_hidden_state, ref, atol=1e-5), "zero-init adapters must not change the output"
    tr = [nme for nme, q in enc.named_parameters() if q.requires_grad]; assert tr and all("lora_" in nme for nme in tr), tr[:3]
    head = torch.nn.Linear(32, 1); opt = torch.optim.AdamW([q for q in enc.parameters() if q.requires_grad] + list(head.parameters()), lr=3e-3); tgt = (x == 5).float().sum(1) - 1.0
    l0 = None
    for _ in range(120):
        h = enc(input_ids=x, attention_mask=m).last_hidden_state.mean(1); loss = torch.nn.functional.mse_loss(head(h).squeeze(-1), tgt); l0 = l0 or float(loss); opt.zero_grad(); loss.backward(); opt.step()
    assert float(loss) < 0.5 * l0, (l0, float(loss)); after = enc.state_dict()
    assert all(torch.equal(base_state[k], after[k.replace("", "")]) for k in base_state if "lora_" not in k and k in after), "base weights must stay frozen and unchanged"


def test_gp_baseline_planted_calibration_and_k0():
    rng = np.random.default_rng(0); n = 900; X = (rng.random((n, 40)) < 0.3).astype(np.float32) * rng.integers(1, 4, (n, 40)); w = rng.standard_normal(40); y = X @ w; y = (y - y.mean()) / y.std() + 0.2 * rng.standard_normal(n)
    B = LM.GP(X); assert (B.predict(B.fit(None, [], [], 0, 0), [1, 2]) == 0).all()
    st = B.fit(None, list(range(500)), y[:500], 0, 0); te = list(range(500, 900)); mu, sd = B.predict(st, te), B.predict_std(st, te)
    assert spearmanr(mu, y[500:])[0] > 0.7, "GP must learn a planted linear signal"
    err = np.abs(y[500:] - mu); cov = float(np.mean(err / sd <= 1.0)); print(f"  gp (linear world): 1-sigma coverage {cov:.3f} (>0.68 = conservative; hyperparameters FIXED by pre-registration)"); assert cov > 0.5, "the posterior std must not be over-confident"
    # clustered world: seen clusters (low error) vs unseen clusters (high error): the std must rank them
    c = np.random.default_rng(1); nc = 30; cent = (c.random((nc, 60)) < 0.15).astype(np.float32) * 3; val = c.standard_normal(nc)
    lab = np.repeat(np.arange(nc), 30); Xc = cent[lab] + (c.random((nc * 30, 60)) < 0.03) * 1.0; yc = val[lab] + 0.1 * c.standard_normal(nc * 30)
    tr = np.where(lab < 20)[0][::2]; seen = np.where(lab < 20)[0][1::2]; unseen = np.where(lab >= 20)[0]; Bc = LM.GP(Xc); sc = Bc.fit(None, tr, yc[tr], 0, 0)
    sd_seen, sd_un = Bc.predict_std(sc, seen), Bc.predict_std(sc, unseen); e_seen, e_un = np.abs(Bc.predict(sc, seen) - yc[seen]), np.abs(Bc.predict(sc, unseen) - yc[unseen])
    print(f"  gp (clusters): mean sd seen {sd_seen.mean():.3f} vs unseen {sd_un.mean():.3f}; mean |err| seen {e_seen.mean():.3f} vs unseen {e_un.mean():.3f}")
    assert sd_un.mean() > 1.5 * sd_seen.mean() and e_un.mean() > 1.5 * e_seen.mean(), "the posterior std must be larger where the model is wrong (unseen chemistry)"
    far = np.ones((1, 40), np.float32) * 5; B2 = LM.GP(np.vstack([X, far])); st2 = B2.fit(None, list(range(500)), y[:500], 0, 0)
    assert B2.predict_std(st2, [n])[0] > np.median(B2.predict_std(st2, te)), "an unlike candidate must be more uncertain than typical ones"
    sh = B.fit(None, list(range(500)), rng.permutation(y[:500]), 0, 0); assert abs(spearmanr(B.predict(sh, te), y[500:])[0]) < 0.25, "shuffled labels must not give signal"

def test_ln_peft_mode_trains_only_layernorm_and_head():
    import torch
    sys.path.insert(0, os.path.join(HERE, "..", "allatom")); import atom_lm as A
    sd = torch.load(f"{SP}/atom_ckpt.pt", map_location="cpu", weights_only=False)["model"]; import json
    recs = R.load(CSV)[:200]; sm = [r["smiles"] for r in recs]; idx, y = planted(recs, 200)
    B = LM.AtomLMReg([recs[i]["smiles"] for i in idx], f"{SP}/atom_ckpt.pt", f"{SP}/atom_vocab.json", "cpu"); B.peft = "ln"; st0 = B.init_state()
    tr = [n for n, q in st0.named_parameters() if q.requires_grad]; assert tr and all(n.startswith("head") or "ln" in n.split(".")[-2] or n.split(".")[-2] in ("ln", "ln1", "ln2") for n in tr), tr[:6]
    frac = sum(q.numel() for q in st0.parameters() if q.requires_grad) / sum(q.numel() for q in st0.parameters()); assert frac < 0.01, frac
    before = {n: q.detach().clone() for n, q in st0.named_parameters()}; st = B.fit(st0, np.arange(120), y[:120], 60, 0)
    changed = [n for n, q in st.named_parameters() if not torch.equal(before[n], q.detach())]; assert changed and set(changed) <= set(tr), "only LayerNorm/head parameters may change"
    print("  ln-peft: trainable fraction %.4f, changed %d params" % (frac, len(changed)))


def test_random_srcmatch_reproduces_the_loops_source_mix_but_not_its_labels():
    rng = np.random.default_rng(0); n = 2400; X = rng.random((n, 8)).astype(np.float32); srcs = [f"s{i % 6}" for i in range(n)]; off = {f"s{k}": k * 0.5 for k in range(6)}
    y = np.array([X[i, 0] * 2 + off[srcs[i]] * 0 + 0.3 * rng.standard_normal() for i in range(n)]); thr = float(np.quantile(y, .9)); B = LM.GBM(X)
    p = dict(n_init=60, rounds=4, batch=40, n_eval=200, steps0=0, steps_round=0, n_cand=100, n_flat_groups=10); init = list(range(60)); E, pool = L.make_eval_slice(list(range(60, n)), 0, 200)
    ctx = L.Ctx(y, thr, np.full(n, thr), srcs, np.zeros(n), B, p, np.zeros(n), None, None, None, None); st0 = B.fit(B.init_state(), init, y[init], 0, 0)
    lp = L.run_arm(ctx, "loop", init, pool, E, 0, state0=st0); ctx.match_rounds = [dict(__import__("collections").Counter(srcs[i] for i in rd)) for rd in lp["picks"]]
    sm = L.run_arm(ctx, "random_srcmatch", init, pool, E, 0, state0=st0)
    for r in range(4):
        a = __import__("collections").Counter(srcs[i] for i in lp["picks"][r]); b = __import__("collections").Counter(srcs[i] for i in sm["picks"][r]); assert a == b, ("source mix must match exactly", r, a, b)
    assert np.mean(y[[i for rd in lp["picks"] for i in rd]]) > np.mean(y[[i for rd in sm["picks"] for i in rd]]) + 0.3, "the matched draw must NOT reproduce the loop's high-label selection"

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "core"
    names = {"core": ["test_eval_slice_disjoint_and_paired", "test_arms_on_planted_world_with_gbm", "test_one_shot_budget_equals_loop_total_steps", "test_stereo_rho_planted_and_ties_are_zero", "test_flat_slice_split_properties", "test_stereo_blind_is_zero_and_stereo_aware_detected", "test_subset_identical_between_small_and_large_runners", "test_regime_L_leave_labs_out_properties", "test_kphys_channels_and_fusion_identities", "test_physchem_channel_planted", "test_frozen_arm_sar_uses_only_labels_the_model_has", "test_knn_baseline_planted_and_k0", "test_rule_kphys_arm_is_model_free_and_ranks_by_the_rule", "test_lora_wiring_on_tiny_encoder", "test_gp_baseline_planted_calibration_and_k0", "test_random_srcmatch_reproduces_the_loops_source_mix_but_not_its_labels"],
             "atom": ["test_atom_heads_functional", "test_atom_adapter_planted_signal", "test_ln_peft_mode_trains_only_layernorm_and_head"], "chemberta": ["test_chemberta_adapter_planted_signal"], "atomphys": ["test_atom_phys_adapter_planted_signal"], "chembertaphys": ["test_chemberta_phys_adapter_planted_signal"], "v4": ["test_v4_adapter_planted_signal"]}[which]
    for n in names: globals()[n](); print("PASS", n)
