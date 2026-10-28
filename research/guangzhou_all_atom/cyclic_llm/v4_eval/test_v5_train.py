"""v5 trainer positive controls (cd cyclic_llm && python3 -m pytest -q v4_eval/test_v5_train.py).
 A  planted TARGET-DEPENDENT signal (XOR-like: motif CS matters only for target T1, NO only for T2; neither motif alone is informative) must be learned (within-target AUC > 0.85),
    the WRONG-TARGET control (score with the other target's memory) must lose it, SHUFFLED labels must give chance
 B  Tobit censoring recovers the true mean of right-censored data; naive treat-as-exact is biased
 C  pairwise hard-negative loss: correct order < reversed order
 D  topology tokens are in the vocabulary (not UNK) for real macrocycle SMILES
 E  fold guard raises on a planted overlap and passes on a clean set
 F  resume is bitwise identical to an uninterrupted run"""
import os, sys, random
import numpy as np, torch
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "allatom"))
import atom_lm as A, v5_train as T, v5_atom_tokens as V
from sklearn.metrics import roc_auc_score

ALPH = ["C", "N", "O", "S", "(", ")", "=", "1"]; TD = 16


def targets(seed=0):
    rng = np.random.default_rng(seed); return {"T1": rng.normal(size=(4, TD)).astype("float32"), "T2": rng.normal(size=(4, TD)).astype("float32")}


def make_rows(vocab, n, seed, shuffle_labels=False):
    rng = random.Random(seed); rows = []
    for _ in range(n):
        s = "".join(rng.choice(ALPH) for _ in range(rng.randint(8, 10)))
        s = s.replace("CS", "CC").replace("NO", "NC"); p = rng.randrange(0, len(s) - 2)
        a, b = rng.random() < 0.5, rng.random() < 0.5
        if a: q = rng.randrange(0, len(s) - 1); s = s[:q] + "CS" + s[q + 2:]
        if b: q = rng.randrange(0, len(s) - 1); s = s[:q] + "NO" + s[q + 2:]
        has_cs, has_no = "CS" in s, "NO" in s
        for t, has in (("T1", has_cs), ("T2", has_no)):
            rows.append(dict(ids=vocab.encode(s), target=t, y=(8.0 if has else 5.0) + rng.gauss(0, 0.1), rel=0, smiles=s, has=has))
    if shuffle_labels:
        for t in ("T1", "T2"):
            idx = [i for i, r in enumerate(rows) if r["target"] == t]; ys = [rows[i]["y"] for i in idx]; rng.shuffle(ys)
            for i, y in zip(idx, ys): rows[i]["y"] = y
    return rows


def fresh(vocab, seed=0):
    torch.manual_seed(seed); return T.V5Model(len(vocab), d=64, layers=2, heads=4, max_len=48, target_dim=TD)


def auc_by_target(model, data, rows, swap=False):
    res = []
    for t in ("T1", "T2"):
        rs = [dict(r, target=("T2" if t == "T1" else "T1") if swap else t) for r in rows if r["target"] == t]
        sc = T.predict(model, data, rs); res.append(roc_auc_score([int(r["has"]) for r in rs], sc))
    return res


def test_A_planted_target_dependence_wrong_target_and_shuffled():
    """Criteria (the planted XOR-like world is hard for a 2-layer toy; T1 is learned faster than T2): mean correct-target AUC > 0.85 and min > 0.70;
    WRONG-target memory: AUC <= 0.62 and mean gap to correct > 0.30; SHUFFLED labels: all AUC in (0.35, 0.65)."""
    vocab = A.Vocab(ALPH); tg = targets(); tr = make_rows(vocab, 3000, 1); te = make_rows(vocab, 300, 2)
    d = T.V5Data(tr, tg, TD); m = T.train(fresh(vocab), d, steps=2000, seed=0, lr=1e-3, lm_w=0.0, bs=64)
    ok, sw = auc_by_target(m, d, te), auc_by_target(m, d, te, swap=True)
    assert np.mean(ok) > 0.85 and min(ok) > 0.70, ok
    assert max(sw) <= 0.62 and np.mean(ok) - np.mean(sw) > 0.30, ("wrong-target memory must lose the signal", ok, sw)
    trs = make_rows(vocab, 3000, 1, shuffle_labels=True); ds = T.V5Data(trs, tg, TD); ms = T.train(fresh(vocab), ds, steps=2000, seed=0, lr=1e-3, lm_w=0.0, bs=64)
    sh = auc_by_target(ms, ds, te); assert all(0.35 < a < 0.65 for a in sh), sh


def test_B_tobit_recovers_censored_mean():
    torch.manual_seed(0); x = torch.randn(4000) * 1.0 + 6.0; c = 6.0; cens = x > c
    y = torch.where(cens, torch.full_like(x, c), x); rel = cens.long()   # rel 1: pAct >= y
    mu = torch.zeros((), requires_grad=True); ls = torch.zeros((), requires_grad=True); opt = torch.optim.Adam([mu, ls], lr=0.05)
    for _ in range(2000):
        loss = T.tobit_nll(mu.expand(len(y)), ls, y, rel).mean(); opt.zero_grad(); loss.backward(); opt.step()
    assert abs(float(mu) - 6.0) < 0.12 and abs(float(torch.exp(ls)) - 1.0) < 0.12, (float(mu), float(torch.exp(ls)))
    assert float(y.mean()) - 6.0 < -0.3                      # naive treat-censored-as-exact is biased low
    # left censoring symmetric check
    yl = torch.where(x < 5.0, torch.full_like(x, 5.0), x); rl = (x < 5.0).long() * 2
    mu2 = torch.zeros((), requires_grad=True); ls2 = torch.zeros((), requires_grad=True); o2 = torch.optim.Adam([mu2, ls2], lr=0.05)
    for _ in range(2000):
        l2 = T.tobit_nll(mu2.expand(len(yl)), ls2, yl, rl).mean(); o2.zero_grad(); l2.backward(); o2.step()
    assert abs(float(mu2) - 6.0) < 0.12


def test_C_pairwise_hard_negative():
    y = torch.tensor([3.0, 2.0, 1.0, 0.0]); good = torch.tensor([3.0, 2.0, 1.0, 0.0]); bad = torch.tensor([0.0, 1.0, 2.0, 3.0])
    assert float(T.pairwise_hard_neg(good, y)) < float(T.pairwise_hard_neg(bad, y))
    assert float(T.pairwise_hard_neg(torch.zeros(3), torch.ones(3))) == 0.0     # no strictly-better pairs -> zero loss


def test_D_topology_tokens_in_vocab():
    smis = ["C[C@H]1C(=O)N[C@H](CC(C)C)C(=O)NCC(=O)N2CCC[C@H]2C(=O)N1", "N[C@@H](CSSC[C@H](NC(=O)CN)C(=O)NCC(=O)O)C(=O)O"]
    toks = sorted({t for s in smis for t in A.tokenize(s)}) + V.TOPO_TOKENS; vocab = A.Vocab(toks)
    for s in smis:
        ids, status = V.encode(s, vocab, 512); assert status == "ok" and A.UNK not in ids
    assert vocab.stoi["<topo_h2t>"] in V.encode(smis[0], vocab, 512)[0]


def test_E_fold_guard():
    held = ["C[C@H]1C(=O)N[C@H](CC(C)C)C(=O)NCC(=O)N2CCC[C@H]2C(=O)N1"]
    clean = ["CCO", "c1ccccc1O", "CC(=O)Nc1ccc(O)cc1"]; assert T.assert_fold_clean(clean, held)
    try: T.assert_fold_clean(clean + [held[0].replace("@@", "!").replace("@", "@@").replace("!", "@")], held); raise RuntimeError("guard missed stereo-flip duplicate")
    except AssertionError: pass


def test_F_resume_bitwise_identical():
    vocab = A.Vocab(ALPH); tg = targets(); rows = make_rows(vocab, 60, 1); d = T.V5Data(rows, tg, TD)
    a = T.train(fresh(vocab), d, steps=12, seed=0, lr=1e-3, lm_w=0.0, bs=16)
    with __import__("tempfile").TemporaryDirectory() as tmp:
        ck = f"{tmp}/c.pt"; m1 = T.train(fresh(vocab), d, steps=6, seed=0, lr=1e-3, lm_w=0.0, bs=16, ckpt=ck, ckpt_every=6)
        m2 = T.train(fresh(vocab), d, steps=12, seed=0, lr=1e-3, lm_w=0.0, bs=16, ckpt=ck, ckpt_every=6, resume=True)
    assert all(torch.equal(x, y) for x, y in zip(a.state_dict().values(), m2.state_dict().values()))
