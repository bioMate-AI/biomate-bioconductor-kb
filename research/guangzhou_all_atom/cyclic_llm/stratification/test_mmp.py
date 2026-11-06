"""Planted-effect controls for the peptide MMP pipeline. Run: python3 test_mmp.py"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd, mmp as M

def mk(seq_tokens):
    out = []
    import tokens as T
    for t in seq_tokens:
        c = T.classify(t); out.append((c["base"], bool(c["is_D"]), bool(c["is_nme"]), t, c["comp"], c["kind"]))
    return out

def synth(n_sources=12, per=60, seed=0, nme_eff=1.0, d_eff=-0.5):
    rng = np.random.default_rng(seed); rows = []; pid = 0
    AA = ["L", "A", "F", "V", "I", "T", "S", "P"]
    for s in range(n_sources):
        off = rng.normal(0, 3)
        base = [[rng.choice(AA) for _ in range(6)] for _ in range(per // 4)]
        for b in base:
            for variant in range(4):
                toks = list(b); me = [False] * 6; D = [False] * 6
                if variant in (1, 3): me[2] = True
                if variant in (2, 3): D[4] = True
                seq = [("me" if me[i] else "") + ("d" if D[i] else "") + toks[i] if not (me[i] and D[i]) else "Me_d" + toks[i] for i in range(6)]
                seq = [("meL" if (me[i] and not D[i] and toks[i] == "L") else x) for i, x in enumerate(seq)]
                y = off + nme_eff * me[2] + d_eff * D[4] + rng.normal(0, 0.15)
                rows.append(dict(pid=pid, Source=f"S{s}", helm_topology="head_to_tail", n_monomers=6, ring_res=6, items=mk(seq), y=y)); pid += 1
    return pd.DataFrame(rows).set_index("pid")

def test_recovers_planted_effects_and_cancels_source_offsets():
    df = synth(); pr = M.find_single_pairs(df)
    assert len(pr) > 100
    pr["y_a"] = df.loc[pr.id_a, "y"].values; pr["y_b"] = df.loc[pr.id_b, "y"].values; pr["flat_a"] = pr.id_a.values
    eff = M.effects(pr, "y_a", "y_b").set_index("transformation")
    r = eff.loc["N-Me added (with minus without)"]; assert r.meta_lo < 1.0 < r.meta_hi and r.directed
    d = eff.loc["D flip (D minus L)"]; assert d.meta_lo < -0.5 < d.meta_hi

def test_undirected_categories_report_magnitude_only():
    assert M.is_directed("N-Me added (with minus without)") and M.is_directed("substitution: aliphatic->aromatic")
    assert not M.is_directed("substitution: aliphatic->aliphatic") and not M.is_directed("N-Me shift (one N-Me moved)") and not M.is_directed("cap_or_unknown_change")

def test_null_transformation_not_detected():
    df = synth(nme_eff=0.0, d_eff=0.0, seed=1); pr = M.find_single_pairs(df)
    pr["y_a"] = df.loc[pr.id_a, "y"].values; pr["y_b"] = df.loc[pr.id_b, "y"].values; pr["flat_a"] = pr.id_a.values
    eff = M.effects(pr, "y_a", "y_b").set_index("transformation"); r = eff.loc["N-Me added (with minus without)"]; assert r.meta_lo < 0 < r.meta_hi

def test_rotation_alignment_for_head_to_tail():
    a = mk(["L", "A", "F", "V", "I", "T"]); b = mk(["F", "V", "I", "T", "L", "S"])       # b rotated and S for A
    df = pd.DataFrame([dict(Source="X", helm_topology="head_to_tail", n_monomers=6, ring_res=6, items=a, y=0.0), dict(Source="X", helm_topology="head_to_tail", n_monomers=6, ring_res=6, items=b, y=1.0)], index=[0, 1])
    pr = M.find_single_pairs(df); assert len(pr) == 1 and pr.label.iloc[0].startswith("substitution")
    df["helm_topology"] = "lariat_sc_cterm"; assert len(M.find_single_pairs(df)) == 0          # no rotation for lariats

def test_nme_shift_found():
    a = mk(["meL", "A", "F", "V", "I", "T"]); b = mk(["L", "A", "meF", "V", "I", "T"])
    df = pd.DataFrame([dict(Source="X", helm_topology="head_to_tail", n_monomers=6, ring_res=6, items=a), dict(Source="X", helm_topology="head_to_tail", n_monomers=6, ring_res=6, items=b)], index=[0, 1])
    assert len(M.find_nme_shift(df)) == 1

if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for f in fns: f(); print("PASS", f.__name__)
    print(len(fns), "tests passed")
