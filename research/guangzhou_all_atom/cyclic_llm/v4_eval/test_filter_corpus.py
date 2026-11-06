"""Corpus filter controls (cd cyclic_llm && python3 -m pytest -q v4_eval/test_filter_corpus.py):
 - blocked numpy filter == brute-force RDKit BulkTanimoto filter (exactness of the popcount window), on a corpus with planted neighbours
 - planted exact copy, stereo-flipped copy (same flat structure) and close analogue (Tanimoto >= 0.9) of held-out compounds are removed; unrelated molecules are kept
 - a held-out compound that is itself NOT in the corpus removes nothing unless a neighbour exists (no over-removal)"""
import os, sys, random
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import filter_corpus as F
from rdkit import Chem, DataStructs
from rdkit.Chem import rdFingerprintGenerator

PEPS = ["C[C@H]1C(=O)N[C@H](CC(C)C)C(=O)N(C)[C@@H](Cc2ccccc2)C(=O)NCC(=O)N2CCC[C@H]2C(=O)N1",
        "CC(C)C[C@H]1C(=O)N[C@@H](CC(=O)O)C(=O)NCC(=O)N[C@@H](CCCNC(=N)N)C(=O)N[C@H](Cc2ccc(O)cc2)C(=O)N[C@@H](C)C(=O)N1",
        "N[C@@H](CCCNC(=N)N)C(=O)NCC(=O)N[C@@H](CC(=O)O)C(=O)N[C@@H](CC(C)C)C(=O)N[C@@H](Cc1ccccc1)C(=O)N[C@@H](Cc1ccc(O)cc1)C(=O)O"]


def flip(s): return s.replace("@@", "!").replace("@", "@@").replace("!", "@")


def make_world():
    rng = random.Random(0)
    drug = ["CCN(CC)CCOC(=O)c1ccc(N)cc1", "c1ccc2c(c1)[nH]c1ccccc12", "CC(C)Cc1ccc(C(C)C(=O)O)cc1", "O=C(O)c1ccccc1O", "CN1CCC[C@H]1c1cccnc1", "CC(=O)Nc1ccc(O)cc1"]
    corpus = []
    for i in range(1500):  # random chains/rings drug-like noise
        corpus.append("".join(rng.choice(["C", "CC", "CCO", "c1ccccc1", "N", "C(=O)", "CN", "CS"]) for _ in range(rng.randint(3, 9))))
    corpus = [c for c in corpus if Chem.MolFromSmiles(c)] + drug
    held = list(PEPS)
    planted = {"exact": PEPS[0], "stereo_flip": flip(PEPS[1]), "analogue": PEPS[2].replace("C(=O)O", "C(=O)N", 1)}
    corpus += list(planted.values()); corpus += [Chem.MolToSmiles(Chem.MolFromSmiles("CC(C)Cc1ccc(C(C)C(=O)O)cc1"))]
    return corpus, held, planted


def brute(corpus, held, tan=0.9):
    gen = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
    hf = [gen.GetFingerprint(Chem.MolFromSmiles(h)) for h in held]; hflat = {Chem.MolToSmiles(Chem.MolFromSmiles(h), isomericSmiles=False) for h in held}
    rem = set()
    for i, s in enumerate(corpus):
        m = Chem.MolFromSmiles(s)
        if m is None: continue
        if Chem.MolToSmiles(m, isomericSmiles=False) in hflat: rem.add(i); continue
        fp = gen.GetFingerprint(m)
        if max(DataStructs.BulkTanimotoSimilarity(fp, hf)) >= tan: rem.add(i)
    return rem


def test_blocked_equals_brute_force_and_planted_removed():
    corpus, held, planted = make_world()
    c_flat, c_pc, c_fp = F.featurize_all(corpus, 1)
    by_flat, by_tan = F.removed_for(held, c_flat, c_pc, c_fp)
    got = by_flat | by_tan; ref = brute(corpus, held)
    assert got == ref, (sorted(got - ref), sorted(ref - got))
    idx = {s: i for i, s in enumerate(corpus)}
    assert idx[planted["exact"]] in by_flat and idx[planted["stereo_flip"]] in by_flat
    an = Chem.MolFromSmiles(planted["analogue"]); gen = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
    t = max(DataStructs.BulkTanimotoSimilarity(gen.GetFingerprint(an), [gen.GetFingerprint(Chem.MolFromSmiles(h)) for h in held]))
    assert (idx[planted["analogue"]] in got) == (t >= 0.9)
    assert not any(corpus[i] in ("CC(=O)Nc1ccc(O)cc1", "O=C(O)c1ccccc1O") for i in got), "unrelated small molecules must be kept"


def test_no_over_removal_when_no_neighbours():
    corpus, _, _ = make_world(); other = ["CC(C)(C)OC(=O)N[C@@H](CC(C)C)C(=O)N1CCCC1C(=O)NC(Cc1ccccc1)C(=O)NC(CCCCN)C(=O)NC(CO)C(=O)O"]
    c_flat, c_pc, c_fp = F.featurize_all(corpus, 1); a, b = F.removed_for(other, c_flat, c_pc, c_fp)
    assert not (a | b)


def test_sharded_featurisation_resumes_and_matches(tmp_path=None):
    import tempfile
    corpus, held, planted = make_world()
    with tempfile.TemporaryDirectory() as d:
        a = F.featurize_sharded(corpus, 1, d, shard=700, log=lambda m: None); b = F.featurize_sharded(corpus, 1, d, shard=700, log=lambda m: None)        # second call reuses every shard
        ref = F.featurize_all(corpus, 1)
        assert all(np.array_equal(x, y) for x, y in zip(a, ref)) and all(np.array_equal(x, y) for x, y in zip(a, b))
        import glob, os
        os.remove(sorted(glob.glob(d + "/shard_*.npz"))[0]); c = F.featurize_sharded(corpus, 1, d, shard=700, log=lambda m: None)        # a lost shard is recomputed (spot reclaim)
        assert all(np.array_equal(x, y) for x, y in zip(c, ref))
