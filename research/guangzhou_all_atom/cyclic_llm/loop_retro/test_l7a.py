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
    """Null SE of a Spearman rho at n=100 is ~0.1, so one shuffle exceeds |0.2| ~5 % of the time by chance. Require the MEAN over independent shuffles within +-0.12 and no single shuffle beyond +-0.35."""
    return abs(float(np.mean(rhos))) < 0.12 and max(abs(r) for r in rhos) < 0.35

def adapter_control(make_backend, steps, name, n_shuf=3):
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
    arms = ("loop", "random_fb", "shuffled", "frozen", "loop_sub", "loop_kn_sub", "frozen_sub", "shuffled_sub"); d = {a: [] for a in arms}; gain = {a: [] for a in arms}
    for seed in range(4):
        init = list(range(50)); E, pool = L.make_eval_slice(list(range(50, n)), seed, 500); Ef, Efg, pool = L.make_flat_slice(pool, flat, seed, 20)
        assert not set(Ef) & set(pool) and not set(Ef) & set(E) and len(Efg) == 20 and all(len(g) >= 4 for g in Efg)
        ctx = L.Ctx(y, thr, np.full(n, thr), srcs, np.zeros(n), B, p, Kn, Ef, Efg); out = L.run_task(ctx, init, pool, E, seed)
        for a in arms: d[a].append(sum(out[a]["hits"])); gain[a].append(out[a]["auroc_E"][-1] - out[a]["auroc_E0"])
        assert len(out["loop"]["stereo_rho"]) == 5 and "stereo_rho0" in out["loop"]
    m = {a: round(float(np.mean(v)), 3) for a, v in gain.items()}; h = {a: round(float(np.mean(v)), 1) for a, v in d.items()}; print("  planted world: mean hits", h, "| mean AUROC_E gain", m)
    assert h["loop"] > h["random_fb"] + 10, "loop must beat random feedback"
    assert m["loop"] > 0.01 and m["loop"] > m["shuffled"] + 0.01, "loop must improve E AUROC and exceed shuffled"
    assert abs(m["frozen"]) < 1e-9 and abs(m["frozen_sub"]) < 1e-9, "frozen cannot change"
    assert m["shuffled"] < m["loop"] and m["shuffled"] < 0.02 and m["shuffled_sub"] < m["loop_sub"], "shuffled labels must not improve the model"
    assert h["loop_sub"] > h["frozen_sub"] and h["loop_kn_sub"] >= h["loop_sub"] - 5, "subset loop must beat frozen; informative KB must not hurt"
    assert len(out["one_shot"]["ef5_E"]) == 1

def test_subset_identical_between_small_and_large_runners():
    import run_l7a_llm as LL
    pool0 = list(range(100, 3100)); rv = list(range(100, 160))
    for seed in (0, 3):
        for r in (0, 4, 9): assert L.subset(pool0, seed, r, rv, 150) == LL.subset(pool0, seed, r, rv), "the large-LLM runner must use the same candidate subsets as the small-model *_sub arms"
    s = L.subset(pool0, 0, 2, rv, 150); assert not set(s) & set(rv) and len(s) <= 150

def test_stereo_rho_planted():
    rng = np.random.default_rng(0); groups = [list(range(k * 5, k * 5 + 5)) for k in range(40)]; y = rng.standard_normal(200)
    assert L.stereo_rho(y.copy(), groups, y) > 0.99 and L.stereo_rho(-y, groups, y) < -0.99 and abs(L.stereo_rho(rng.standard_normal(200), groups, y)) < 0.2

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
    r1 = spearmanr(B.predict(B.fit(st0, tr, y[tr], 60, 0), te), y[te])[0]
    r2 = [spearmanr(B.predict(B.fit(st0, tr, rng.permutation(y[tr]), 60, k), te), y[te])[0] for k in range(3)]
    print(f"  v4: planted-trained {r1:+.3f} | shuffled-trained {[round(float(r), 3) for r in r2]}"); assert r1 > 0.30 and shuffled_ok(r2), (r1, r2)

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

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "core"
    names = {"core": ["test_eval_slice_disjoint_and_paired", "test_arms_on_planted_world_with_gbm", "test_one_shot_budget_equals_loop_total_steps", "test_stereo_rho_planted", "test_subset_identical_between_small_and_large_runners"],
             "atom": ["test_atom_heads_functional", "test_atom_adapter_planted_signal"], "chemberta": ["test_chemberta_adapter_planted_signal"], "v4": ["test_v4_adapter_planted_signal"]}[which]
    for n in names: globals()[n](); print("PASS", n)
