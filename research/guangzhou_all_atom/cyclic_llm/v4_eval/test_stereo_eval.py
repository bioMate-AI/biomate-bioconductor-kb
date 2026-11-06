"""Stereo-resolved ranking protocol tests (cd cyclic_llm && python3 -m pytest -q v4_eval/test_stereo_eval.py):
 - LOO 'mean of the other members' predictor: within-group Spearman == -1 exactly (documents the artifact the SAR protocol avoids)
 - SAR protocol (one seeded revealed/target split): stereo-blind scorer -> ~0 (ties), revealed-mean reference -> 0 (ties)
 - planted stereo signal (label depends on a stereo token) is recovered by a chirality-aware scorer under the SAR protocol, not by the blind one
 - split is deterministic, disjoint and covers the group"""
import os, sys, random
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stereo_eval as E
from rdkit import Chem


def synth_groups(n_groups=60, size=6, seed=0, planted=False):
    """each group = one flat scaffold with `size` stereo-variants made by flipping '@'/'@@' of a Lys-containing macrocycle; planted: label = +1 for '@@' at the first centre."""
    rng = random.Random(seed); base = "C[C@H]1C(=O)N[C@H](CC(C)C)C(=O)N[C@@H](CCCCN)C(=O)NCC(=O)N[C@@H](Cc2ccccc2)C(=O)N1"
    groups = {}
    for g in range(n_groups):
        sub = rng.choice(["CC", "CCC", "CCCC", "C(C)C", "CC(C)C", "CCCCC", "C(C)CC", "CC(C)CC"]) ; smi0 = base.replace("CC(C)C", sub, 1)
        items = []; seen = set()
        tries = 0
        while len(items) < size and tries < 200:
            tries += 1; s = smi0
            for k in range(4):
                if rng.random() < 0.5: s = s.replace("[C@H]", "[C@@H]", 1) if k % 2 == 0 else s.replace("[C@@H]", "[C@H]", 1)
            m = Chem.MolFromSmiles(s)
            if m is None: continue
            can = Chem.MolToSmiles(m)
            if can in seen: continue
            seen.add(can); lab = (1.0 if "[C@@H]" in can.split("N")[0] else 0.0) if planted else rng.gauss(0, 1)
            items.append(dict(smiles=can, label=lab + rng.gauss(0, 0.05)))
        if len(items) >= 4: groups[f"g{g}"] = items
    return groups


def test_loo_group_mean_is_exactly_minus_one():
    G = synth_groups(); v = E.loo_group_mean_spearman(G)
    assert abs(v + 1.0) < 1e-9, v


def test_sar_protocol_blind_and_reference_score_zero():
    G = synth_groups(); sg = E.sar_groups(G, seed=0); assert len(sg) > 20
    for name, sc in (("blind", E.chiral_gbm_scorer(False)), ("revealed_mean", E.revealed_mean_scorer)):
        r = E.sar_report(name, sg, sc)
        assert abs(r.get("mean_target_spearman", 0.0)) < 1e-9 and r["n_pairs_scored"] == 0, (name, r)


def test_sar_protocol_recovers_planted_stereo_signal():
    G = synth_groups(planted=True); sg = E.sar_groups(G, seed=0)
    r_chi = E.sar_report("chiral", sg, E.chiral_gbm_scorer(True)); r_blind = E.sar_report("blind", sg, E.chiral_gbm_scorer(False))
    assert r_chi["mean_target_spearman"] > 0.3, r_chi
    assert abs(r_blind["mean_target_spearman"]) < 1e-9


def test_split_deterministic_disjoint_covering():
    G = synth_groups(); f, items = next(iter(G.items())); a = E.split_group(items, f, 0); b = E.split_group(items, f, 0); c = E.split_group(items, f, 1)
    assert [i["smiles"] for i in a[0]] == [i["smiles"] for i in b[0]] and [i["smiles"] for i in a[1]] == [i["smiles"] for i in b[1]]
    assert not ({i["smiles"] for i in a[0]} & {i["smiles"] for i in a[1]}) and len(a[0]) + len(a[1]) == len(items)
    assert [i["smiles"] for i in a[0]] != [i["smiles"] for i in c[0]] or len(items) <= 2
