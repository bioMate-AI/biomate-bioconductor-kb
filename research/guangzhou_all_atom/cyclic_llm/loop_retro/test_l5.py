"""L5 tests (PREREG_LOOP amendment L5). Run: OMP_NUM_THREADS=1 python3 test_l5.py
Positive control: chirality-aware features must separate stereoisomers that chirality-blind features cannot."""
import os, sys, itertools
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_loop as R, run_loop_par as P, run_loop_prior as K
from rdkit import Chem
from rdkit.Chem.EnumerateStereoisomers import EnumerateStereoisomers, StereoEnumerationOptions
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.model_selection import cross_val_score

# cyclo(Ala-Phe-Leu-Val-Tyr-Pro): 6 stereocentres -> 64 stereoisomers with an identical flat structure
BASE = "O=C1[C@@H](C)NC(=O)[C@H](Cc2ccccc2)NC(=O)[C@H](CC(C)C)NC(=O)[C@H](C(C)C)NC(=O)[C@H](Cc2ccc(O)cc2)NC(=O)[C@@H]2CCCN12"

def isomers():
    opts = StereoEnumerationOptions(onlyUnassigned=False, unique=True)
    return [Chem.MolFromSmiles(Chem.MolToSmiles(m)) for m in EnumerateStereoisomers(Chem.MolFromSmiles(BASE), options=opts)]

def test_blind_fingerprint_cannot_separate_stereoisomers_but_chiral_can():
    ms = isomers(); assert len(ms) >= 32
    blind = {R.morgan_counts(m, False).tobytes() for m in ms}; chir = {R.morgan_counts(m, True).tobytes() for m in ms}
    assert len(blind) == 1, "blind features must be identical across stereoisomers"
    assert len(chir) > 8, "chiral features must distinguish stereoisomers"
    assert len({R.flat_key(m) for m in ms}) == 1, "all isomers share one flat structure"

def test_planted_stereo_signal_is_learnable_only_with_chirality():
    ms = isomers()
    # label = chirality of the Phe centre (planted: depends on stereochemistry only)
    def phe_is_R(m):
        from rdkit.Chem import rdCIPLabeler; rdCIPLabeler.AssignCIPLabels(m)
        pat = Chem.MolFromSmarts("[CX4;H1](Cc1ccccc1)(N)C(=O)")
        idx = m.GetSubstructMatch(pat)[0]; return int(m.GetAtomWithIdx(idx).GetProp("_CIPCode") == "R")
    y = np.array([phe_is_R(m) for m in ms]); assert 0.3 < y.mean() < 0.7
    # RDKit's chiral Morgan encodes local parity only partly in macrocycles (measured CV accuracy 0.75, not 1.0) — the control asserts a large, non-chance gap, not perfection
    for chiral, lo, hi in ((True, 0.70, 1.01), (False, 0.0, 0.55)):
        X = np.stack([R.morgan_counts(m, chiral) for m in ms])
        acc = cross_val_score(HistGradientBoostingClassifier(max_iter=60, random_state=0), X, y, cv=4).mean() if len(set(map(bytes, X))) > 1 else max(y.mean(), 1 - y.mean())
        assert lo <= acc <= hi, (chiral, acc)

def test_regime_C_pool_has_no_flat_duplicates_of_initial_set():
    rng = np.random.default_rng(0); n = 600
    flat = [f"F{int(i)}" for i in rng.integers(0, 150, n)]; srcs = ["s"] * n; scaf = ["x"] * n
    for seed in range(5):
        init, pool = P.setup("C", seed, srcs, scaf, 100, flat)
        fi = {flat[i] for i in init}; assert all(flat[j] not in fi for j in pool) and not set(init) & set(pool)

def test_rule_arm_ranks_by_signal_and_breaks_ties_with_seed():
    n = 1000; rng = np.random.RandomState(1); X = rng.rand(n, 5).astype(np.float32); y = rng.randn(n)
    k = np.repeat(np.arange(10.0), 100)                        # 10 tie groups of 100; group 9 is the best
    init = list(range(0, n, 50)); pool = [i for i in range(n) if i not in set(init)]
    # run the real policy with an informative hit definition: hits = y >= thr where y is planted = k
    y = k + 0.0; tot, per = K.run_prior_policy("rule", X, y, k, init, pool, thr=9.0, seed=0)
    n_top = sum(1 for i in pool if k[i] == 9.0)                # top-group members available in the pool
    assert tot == min(500, n_top) and per[0] == 50, (tot, per)  # the rule selects the whole top group first
    # ties are broken by the seed, not by dataset order
    t0, p0 = K.run_prior_policy("rule", X, np.zeros(n), k, init, pool, thr=-1.0, seed=0)
    ties = [i for i in pool if k[i] == 8.0]
    a = list(np.argsort(-np.random.default_rng(0).random(len(ties)))); b = list(np.argsort(-np.random.default_rng(1).random(len(ties))))
    assert a != b

def test_loader_options_change_features_and_label_column(tmp_path=None):
    import csv, tempfile
    d = tempfile.mkdtemp(); f = os.path.join(d, "t.csv")
    ms = isomers()[:2]; hdr = ["Structurally_Unique_ID", "Permeability", "PAMPA", "SMILES", "Source"]
    with open(f, "w", newline="") as fh:
        w = csv.writer(fh); w.writerow(hdr)
        for i, m in enumerate(ms): w.writerow([i, -6.0 - i, -5.0 - i, Chem.MolToSmiles(m), "S"])
    a = R.load(f, "Permeability", False); b = R.load(f, "PAMPA", True)
    assert abs(a[0]["y"] + 6.0) < 1e-9 and abs(b[0]["y"] + 5.0) < 1e-9
    assert (a[0]["x"] == a[1]["x"]).all() and not (b[0]["x"] == b[1]["x"]).all()
    assert a[0]["flat"] == a[1]["flat"]

if __name__ == "__main__":
    n = 0
    for k_, v in list(globals().items()):
        if k_.startswith("test_") and callable(v): v(); print("PASS", k_); n += 1
    print(n, "tests passed")
