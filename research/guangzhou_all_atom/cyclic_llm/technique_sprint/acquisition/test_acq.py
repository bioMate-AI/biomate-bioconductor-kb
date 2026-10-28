#!/usr/bin/env python3
"""Unit tests for the T2 acquisition code (pre-registration 1.9 C1/C5). Run: OMP_NUM_THREADS=1 python3 test_acq.py"""
import os, sys, csv, tempfile, collections, random
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import acq as A

CFG_OFF = dict(lam=0.0, cap_src=50, cap_flat=A.BIG)


def synth(n=3000, seed=0, planted_src=0, planted_bit=3, effect=4.0, thr_abs=2.5):
    """Synthetic fixture with real-code structure: 5 sources, 64-bit count fingerprints, one planted series inside source `planted_src`.
    Hits are defined by an ABSOLUTE threshold on the noise scale (thr_abs) so the random hit rate equals the series prevalence (~5 %), not a fixed 10 %: a
    10 % quantile threshold made the first version of this control invalid (greedy 99 vs random 52 hits; greedy cannot exceed ~3x random at 10 % base rate)."""
    rng = np.random.default_rng(seed); sizes = [1200, 800, 500, 300, 200]; srcs = []
    for k, s in enumerate(sizes): srcs += [f"src{k}"] * s
    srcs = srcs[:n]; n = len(srcs)
    X = rng.poisson(0.25, size=(n, 64)).astype(np.float32); X[:, planted_bit] = 0
    sid = np.array([int(s[3:]) for s in srcs]); mem = (sid == planted_src) & (rng.random(n) < 0.12); X[mem, planted_bit] = 1.0
    y = rng.standard_normal(n) + effect * mem; thr = float(thr_abs)
    flat = [f"f{i // 3}" for i in range(n)]                        # groups of 3 stereo-siblings
    D = dict(srcs=srcs, scaf=[f"s{i}" for i in range(n)], flat=flat, y=y, thr=thr, thr_g=np.full(n, thr), Kphys=rng.standard_normal(n), X=X, smiles=["C"] * n)
    return A.prepare_derived(D), mem


def test_caps_respected():
    D, _ = synth(); U = np.arange(len(D["y"])); score = np.where(D["src_code"] == 0, 5.0, 0.0) + 1e-3 * np.arange(len(U))   # source 0 is hugely attractive
    sel = A.select_diverse(score, U, D, lam=0.0, cap_src=10, cap_flat=A.BIG, flat_count={})
    cnt = collections.Counter(D["src_code"][U[sel]]); assert max(cnt.values()) <= 10 and len(sel) == 50 and len(set(sel)) == 50, cnt
    fc = {int(f): 2 for f in D["flat_code"][U]}                    # every flat group already has 2 cumulative picks
    sel = A.select_diverse(score, U, D, lam=0.0, cap_src=50, cap_flat=3, flat_count=fc)
    c2 = collections.Counter(D["flat_code"][U[sel]]); assert max(c2.values()) <= 1, c2          # at most 3-2 = 1 more per flat group
    print("PASS caps respected (source cap per batch, cumulative flat cap)")


def test_no_diversity_equals_topk():
    D, _ = synth(); U = np.arange(len(D["y"])); score = np.random.default_rng(1).standard_normal(len(U))
    sel = A.select_diverse(score, U, D, lam=0.0, cap_src=50, cap_flat=A.BIG, flat_count={})
    ref = [int(j) for j in np.argsort(-score, kind="stable")[:50]]; assert sel == ref
    print("PASS lam=0, no caps reproduces plain top-50")


def test_lambda_spreads_similarity():
    D, _ = synth(); U = np.arange(len(D["y"])); j0 = 0
    sim = A.tanimoto_to(D, U, j0); score = 3.0 * sim                  # reward similarity to compound 0
    plain = A.select_diverse(score, U, D, 0.0, 50, A.BIG, {}); div = A.select_diverse(score, U, D, 2.0, 50, A.BIG, {})
    def mean_pair(sel):
        v = [A.tanimoto_to(D, U[sel], U[s])[k] for k, s in enumerate(sel)]; M = [np.mean(A.tanimoto_to(D, U[sel], U[s])) for s in sel]; return float(np.mean(M))
    assert mean_pair(div) < mean_pair(plain), (mean_pair(div), mean_pair(plain))
    print("PASS within-batch penalty lowers mean pairwise similarity of a batch")


def test_tanimoto_matches_rdkit():
    from rdkit import DataStructs
    D, _ = synth(); idx = np.arange(0, 200); rng = np.random.default_rng(3)
    for j in rng.integers(0, 200, 8):
        s = A.tanimoto_to(D, idx, int(j))
        for i in rng.integers(0, 200, 6):
            a = DataStructs.ExplicitBitVect(64); b = DataStructs.ExplicitBitVect(64)
            for k in np.where(D["B"][i] > 0)[0]: a.SetBit(int(k))
            for k in np.where(D["B"][int(j)] > 0)[0]: b.SetBit(int(k))
            ref = DataStructs.TanimotoSimilarity(a, b) if (a.GetNumOnBits() + b.GetNumOnBits()) > 0 else 0.0
            assert abs(ref - s[int(i)]) < 1e-6, (ref, s[int(i)])
    print("PASS binary Tanimoto equals RDKit TanimotoSimilarity")


def test_setup_L_equals_original():
    import run_l7a as L7
    D, _ = synth(); srcs = [f"s{i % 40}" for i in range(7000)]; srcs[:2900] = ["2020_Townsend"] * 2900; srcs[2900:4400] = ["2021_Kelly"] * 1500
    for seed in (0, 1, 5, 11):
        a = A.setup_L(seed, srcs, 100); b = L7.setup_L(seed, srcs, 100); assert a == b, seed
        E1 = A.make_eval_slice(a[2], seed, 300); E2 = L7.make_eval_slice(b[2], seed, 300); assert E1 == E2
    print("PASS setup_L / make_eval_slice equal run_l7a originals (4 seeds)")


def test_loop_planted_and_caps():
    """End-to-end on the synthetic fixture: greedy finds the planted series; prov (caps) keeps most of that yield and obeys the caps in every round."""
    D, mem = synth(); init = list(range(100)); pool = list(range(100, len(D["y"]))); cfg = dict(lam=0.5, cap_src=25, cap_flat=5)
    rg = A.run_arm("greedy", D, init, pool, 1, CFG_OFF); rr = A.run_arm("random", D, init, pool, 1, CFG_OFF); rp = A.run_arm("prov", D, init, pool, 1, cfg)
    hg, hr, hp = sum(rg["rounds"]), sum(rr["rounds"]), sum(rp["rounds"]); assert hg >= 3 * max(hr, 1), (hg, hr)          # positive control valid
    assert hp >= 0.8 * hg, (hp, hg)                                                                                         # diversity must not suppress a genuine series
    for r in range(A.ROUNDS):
        batch = rp["picks"][r * 50:(r + 1) * 50]; assert max(collections.Counter(D["src_code"][batch]).values()) <= 25
    fc = collections.Counter(D["flat_code"][rp["picks"]]); assert max(fc.values()) <= 5
    print(f"PASS planted series: greedy {hg} / prov {hp} / random {hr} hits; caps obeyed in every round")


def test_deterministic_and_paired():
    D, _ = synth(); init = list(range(100)); pool = list(range(100, len(D["y"]))); a = A.run_arm("ucb", D, init, pool, 7, CFG_OFF); b = A.run_arm("ucb", D, init, pool, 7, CFG_OFF)
    assert a["picks"] == b["picks"]
    g = A.run_arm("greedy", D, init, pool, 7, CFG_OFF); assert g["picks"][:1] != [] and len(g["picks"]) == 500
    print("PASS deterministic for a fixed seed; 500 picks per run")


def test_prepare_pipeline_small_csv():
    """Pipeline test of prepare(): K_phys formula and within-source standardisation on a tiny CSV with the CycPeptMPDB columns the loader needs."""
    from rdkit import Chem
    from rdkit.Chem import Crippen, rdMolDescriptors
    rows = []; rng = np.random.default_rng(5); smi = ["CC(=O)NCC(=O)N1CCCC1C(=O)NC(C)C(=O)O", "CC(C)CC(NC(=O)C(C)N)C(=O)N1CCCC1C(=O)O", "NC(Cc1ccccc1)C(=O)NC(CO)C(=O)N(C)C(C)C(=O)O"]
    for k, s in enumerate(("srcA", "srcB", "srcC")):
        for i in range(25):
            m = smi[(i + k) % 3] + ("C" * (i % 4)); rows.append(dict(Structurally_Unique_ID=str(len(rows) + 1), SMILES=m, Source=s, PAMPA=f"{-5 - rng.random() * 2:.3f}", Permeability=f"{-5 - rng.random() * 2:.3f}"))
    with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows); path = f.name
    D = A.prepare(path); n = len(D["y"]); assert n > 40
    for s in set(D["srcs"]):
        m = np.array([x == s for x in D["srcs"]]); assert abs(D["y"][m].mean()) < 1e-6          # within-source standardisation
    M = [Chem.MolFromSmiles(x) for x in D["smiles"]]; tp = np.array([rdMolDescriptors.CalcTPSA(m) for m in M]); hb = np.array([rdMolDescriptors.CalcNumHBD(m) for m in M]); lg = np.array([Crippen.MolLogP(m) for m in M])
    import run_loop_prior as K
    ref = (K.source_normalize(-tp, D["srcs"]) + K.source_normalize(-hb, D["srcs"]) + K.source_normalize(lg, D["srcs"])) / 3.0
    assert np.allclose(ref, D["Kphys"], atol=1e-9); os.unlink(path)
    print("PASS prepare(): label standardisation and K_phys equal the independent formula")


if __name__ == "__main__":
    for t in (test_caps_respected, test_no_diversity_equals_topk, test_lambda_spreads_similarity, test_tanimoto_matches_rdkit, test_setup_L_equals_original, test_prepare_pipeline_small_csv,
              test_deterministic_and_paired, test_loop_planted_and_caps):
        t()
    print("all tests passed")
