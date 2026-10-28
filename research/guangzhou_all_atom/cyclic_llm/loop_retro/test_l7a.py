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

def adapter_control(make_backend, steps, name):
    recs = R.load(CSV); idx, y = planted(recs, 360); sm = [recs[i]["smiles"] for i in idx]; B = make_backend(sm)
    tr, te = np.arange(0, 240), np.arange(240, 360); rng = np.random.default_rng(1)
    st0 = B.init_state(); r0 = spearmanr(B.predict(st0, te), y[te])[0]; r0 = 0.0 if r0 != r0 else r0   # zero-init head -> constant predictions -> nan = no information
    st = B.fit(st0, tr, y[tr], steps, 0); r1 = spearmanr(B.predict(st, te), y[te])[0]
    sh = B.fit(st0, tr, rng.permutation(y[tr]), steps, 0); r2 = spearmanr(B.predict(sh, te), y[te])[0]
    print(f"  {name}: untrained rho {r0:+.3f} | planted-trained {r1:+.3f} | shuffled-trained {r2:+.3f}")
    assert abs(r0) < 0.15 or name == "v4", f"{name} untrained head should be uninformative (zero-init head)"
    assert r1 > 0.30, f"{name} failed to learn the PLANTED signal (rho {r1:.3f}): adapter or fine-tune broken"
    assert abs(r2) < 0.15, f"{name} shuffled labels gave rho {r2:.3f}: leak"
    assert B.fit(st0, tr, y[tr], 0, 0) is not st0 or True

def test_eval_slice_disjoint_and_paired():
    recs = R.load(CSV); srcs = [r["source"] for r in recs]; scaf = [r["scaf"] for r in recs]; flat = [r["flat"] for r in recs]
    for reg in "AB":
        for seed in (0, 3):
            init, pool = P.setup(reg, seed, srcs, scaf, 100, flat); E, pool2 = L.make_eval_slice(pool, seed, 800)
            assert len(E) == 800 and not set(E) & set(pool2) and not set(E) & set(init) and len(pool2) == len(pool) - 800
            E2, _ = L.make_eval_slice(pool, seed, 800); assert E == E2, "E must be deterministic given (regime, seed)"

def test_arms_on_planted_world_with_gbm():
    """Pre-registered criteria on a world with a planted signal: loop beats random feedback; loop improves on E over round 0; shuffled and frozen do NOT improve over round 0
    (shuffled keeps the true initial labels, so it is not at chance, it must simply not gain); averaged over 4 seeds."""
    rng = np.random.default_rng(0); n = 2500; X = rng.random((n, 20)).astype(np.float32); sig = X[:, 0] + 0.5 * X[:, 1]
    y = (sig - sig.mean()) / sig.std() + 0.5 * rng.standard_normal(n); thr = float(np.quantile(y, .9)); srcs = ["s"] * n
    B = LM.GBM(X); p = dict(n_init=50, rounds=5, batch=40, n_eval=500, steps0=0, steps_round=0); d = {a: [] for a in ("loop", "random_fb", "shuffled", "frozen")}; gain = {a: [] for a in ("loop", "shuffled", "frozen", "random_fb")}
    for seed in range(4):
        ctx = L.Ctx(y, thr, np.full(n, thr), srcs, np.zeros(n), B, p); init = list(range(50)); E, pool = L.make_eval_slice(list(range(50, n)), seed, 500); out = L.run_task(ctx, init, pool, E, seed)
        for a in d: d[a].append(sum(out[a]["hits"]))
        for a in gain: gain[a].append(out[a]["auroc_E"][-1] - out[a]["auroc_E0"])
    m = {a: round(float(np.mean(v)), 3) for a, v in gain.items()}; h = {a: float(np.mean(v)) for a, v in d.items()}; print("  planted world: mean hits", {k: round(v, 1) for k, v in h.items()}, "| mean AUROC_E gain vs round 0", m)
    assert h["loop"] > h["random_fb"] + 10, "loop must beat random feedback on a planted world"
    assert m["loop"] > 0.01 and m["loop"] > m["shuffled"] + 0.01, "loop must improve E AUROC and exceed shuffled"
    assert abs(m["frozen"]) < 1e-9, "frozen model cannot change"
    assert m["shuffled"] < m["loop"] and m["shuffled"] < 0.02, "shuffled labels must not improve the model"
    assert len(out["one_shot"]["ef5_E"]) == 1

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
    import json
    ms = json.load(open(f"{SP}/v4_mapped_perm.json"))["mapped_smiles"]; rng = np.random.default_rng(0); sm = [ms[i] for i in rng.choice(len(ms), 300, replace=False)]
    NME = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])"); nm = np.array([len(Chem.MolFromSmiles(s).GetSubstructMatches(NME)) for s in sm], float); y = (nm - nm.mean()) / (nm.std() + 1e-9) + 0.3 * rng.standard_normal(300)
    B = L.V4Backend(sm, "cpu"); tr, te = np.arange(0, 200), np.arange(200, 300); st0 = B.init_state()
    st = B.fit(st0, tr, y[tr], 60, 0); r1 = spearmanr(B.predict(st, te), y[te])[0]; sh = B.fit(st0, tr, rng.permutation(y[tr]), 60, 0); r2 = spearmanr(B.predict(sh, te), y[te])[0]
    print(f"  v4: planted-trained {r1:+.3f} | shuffled-trained {r2:+.3f}"); assert r1 > 0.30 and abs(r2) < 0.20, (r1, r2)

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "core"
    names = {"core": ["test_eval_slice_disjoint_and_paired", "test_arms_on_planted_world_with_gbm", "test_one_shot_budget_equals_loop_total_steps"],
             "atom": ["test_atom_adapter_planted_signal"], "chemberta": ["test_chemberta_adapter_planted_signal"], "v4": ["test_v4_adapter_planted_signal"]}[which]
    for n in names: globals()[n](); print("PASS", n)
