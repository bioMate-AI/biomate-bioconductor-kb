"""Positive controls for LoopModel.update (run: cd cyclic_llm && python3 -m pytest -q v4_eval/test_loop_model.py).
Planted-label world: a compound's label is high iff it contains the RGD motif; the model starts untrained.
 - finetune_ranking on correct labels must raise held-out AUC well above chance
 - the same update on PERMUTED labels must not
 - frozen / original model unchanged (no mutation); fingerprints differ iff updated
 - dpo path runs and also improves on correct labels"""
import os, sys, random
import numpy as np, torch
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import unified_cyclic_llm as U
from loop_model import LoopModel
from train_cyclic_llm_v3 import make_model, TFEAT_DIM
from sklearn.metrics import roc_auc_score

AA = list("ACDEFGHIKLMNPQRSTVWY")
TSEQ = "MAQGTLIRVTPEQPTHAVCVLGTLTQLDIC" * 3


def world(n, seed):
    rng = random.Random(seed); out = []
    for _ in range(n):
        L = rng.randint(7, 11); s = [rng.choice(AA) for _ in range(L)]
        pos = rng.random() < 0.5
        for p in range(L - 2):
            if s[p:p + 3] == list("RGD"): s[p] = "A"
        if pos: p = rng.randrange(0, L - 2); s[p:p + 3] = list("RGD")
        out.append(dict(tokens=s, target_seq=TSEQ, label=1.0 if pos else 0.0, y=int(pos)))
    return out


def fresh_model(seed=0):
    torch.manual_seed(seed)
    toks = [U.PAD, U.BOS, U.EOS] + U.EBUCK + U.PBUCK + AA
    return LoopModel(make_model(len(toks), TFEAT_DIM, d_model=64, n_layer=2, n_head=4, block=24), toks, 24)


def auc(m, test): return roc_auc_score([r["y"] for r in test], m.score_tokens([r["tokens"] for r in test], TSEQ))


def test_update_learns_planted_signal_and_not_permuted():
    m0 = fresh_model(); train = world(60, 1); test = world(300, 2)
    a0 = auc(m0, test); fp0 = m0.fingerprint()
    m1 = m0.update_tokens(train, "finetune_ranking", seed=0, steps=40, lr=1e-3)
    perm = [dict(r) for r in train]; lab = [r["label"] for r in perm]; random.Random(5).shuffle(lab)
    for r, l in zip(perm, lab): r["label"] = l
    mp = m0.update_tokens(perm, "finetune_ranking", seed=0, steps=40, lr=1e-3)
    a1, ap = auc(m1, test), auc(mp, test)
    assert 0.35 < a0 < 0.65, a0
    assert a1 > 0.85, f"update on correct labels failed to learn planted signal ({a1})"
    assert ap < 0.70, f"update on permuted labels must not learn the signal ({ap})"
    assert m0.fingerprint() == fp0, "original model was mutated"
    assert m1.fingerprint() != fp0 and m1.fingerprint() != mp.fingerprint()


def test_frozen_is_identity_and_dpo_runs():
    m0 = fresh_model(); fz = m0.update_tokens(world(20, 3), "frozen")
    assert all(torch.equal(a, b) for a, b in zip(m0.model.state_dict().values(), fz.model.state_dict().values()))
    test = world(200, 4); md = m0.update_tokens(world(60, 1), "dpo", seed=0, steps=40, lr=1e-3)
    assert auc(md, test) > auc(m0, test) + 0.15
