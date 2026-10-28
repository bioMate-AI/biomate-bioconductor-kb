"""AtomLoopModel positive controls (cd cyclic_llm && python3 -m pytest -q v4_eval/test_atom_loop_model.py): planted substring learned from correct labels, not from permuted; cost reported."""
import os, sys, random
import numpy as np, torch
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "allatom"))
import atom_lm as A
from atom_loop_model import AtomLoopModel
from sklearn.metrics import roc_auc_score
ALPH = ["C", "c", "N", "O", "(", ")", "=", "1"]

def world(n, seed):
    rng = random.Random(seed); out = []
    for _ in range(n):
        s = "".join(rng.choice(ALPH) for _ in range(rng.randint(14, 24))); pos = rng.random() < 0.5
        s = s.replace("NN", "NC")
        if pos: p = rng.randrange(0, len(s) - 2); s = s[:p] + "NN" + s[p + 2:]
        out.append(dict(smiles=s, target_seq="T", label=1.0 if pos else 0.0, y=int(pos)))
    return out

def fresh():
    torch.manual_seed(0); vocab = A.Vocab(ALPH)
    return AtomLoopModel(A.GPT(len(vocab), d=64, layers=2, heads=4, max_len=64), vocab)

def auc(m, test): return roc_auc_score([r["y"] for r in test], m.score([r["smiles"] for r in test]))

def test_planted_and_permuted():
    """The untrained model is not at chance on this world (composition confound, AUC ~0.62), so the controls are RELATIVE to it:
    correct labels must raise held-out AUC by >= 0.12; permuted labels must raise it by < 0.08."""
    m0 = fresh(); tr, te = world(120, 1), world(500, 2); a0 = auc(m0, te); fp0 = m0.fingerprint()
    kw = dict(seed=0, steps=250, lr=3e-3, beta=5.0)
    m1 = m0.update(tr, "finetune_ranking", **kw)
    perm = [dict(r) for r in tr]; lab = [r["label"] for r in perm]; random.Random(3).shuffle(lab)
    for r, l in zip(perm, lab): r["label"] = l
    mp = m0.update(perm, "finetune_ranking", **kw)
    assert auc(m1, te) > a0 + 0.12, (a0, auc(m1, te)); assert auc(mp, te) < a0 + 0.08, (a0, auc(mp, te))
    assert m0.fingerprint() == fp0 and m1.fingerprint() != fp0


def test_cost_and_one_shot_budget():
    m0 = fresh(); tr = world(60, 1)
    a = m0.update(tr, "one_shot_matched", seed=0, steps=10, lr=2e-3, rounds=3); b = m0.update(tr, "finetune_ranking", seed=0, steps=30, lr=2e-3)
    assert all(torch.allclose(x, y) for x, y in zip(a.model.state_dict().values(), b.model.state_dict().values()))
    c = a.cost(); assert c["n_params"] > 0 and c["train_tokens"] > 0 and c["flops"] > 0 and c["updates"] == 1 and m0.cost()["updates"] == 0
