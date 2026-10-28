"""Atom-level LM tests (tokenizer, causality, exact resume, upsampling, learn-and-sample). Run: python3 test_atom_lm.py"""
import os, sys, tempfile
import numpy as np, torch
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atom_lm as A

CYC = "CC(C)C[C@@H]1C(=O)N(C)[C@@H](C)C(=O)N[C@H](Cc2ccccc2)C(=O)N(C)[C@@H](CC(C)C)C(=O)N[C@@H](C)C(=O)N1C"
BIG = "C%10CC%11CCC%12CCCC%13CC%10%11%12%13"          # two-digit ring closures ("%nn") must survive tokenisation
MOLS = ["CCO", "c1ccccc1O", "CC(=O)Nc1ccc(O)cc1", "[NH3+]CC(=O)[O-]", "BrCCCl", CYC, BIG, "C[C@H](N)C(=O)O", "O=C1CCCCN1", "CS(=O)(=O)N", "O=C1CNC(=O)CNC(=O)CNC(=O)CNC(=O)CNC(=O)CN1"]

def test_tokenizer_roundtrip_and_ring_closures():
    for s in MOLS:
        t = A.tokenize(s); assert "".join(t) == s, (s, t)
    assert "%10" in A.tokenize(BIG) and "[C@@H]" in A.tokenize(CYC) and "Cl" in A.tokenize("BrCCCl") and "Br" in A.tokenize("BrCCCl")

def test_vocab_encode_decode_roundtrip_and_unk():
    v = A.Vocab.build(MOLS); ids = v.encode(CYC); assert ids[0] == v.bos and ids[-1] == v.eos and v.decode(ids) == CYC
    assert v.unk in v.encode("[Fe]")                                         # unseen bracket atom -> <unk>, never a crash

def test_model_is_causal():
    torch.manual_seed(0); v = A.Vocab.build(MOLS); m = A.GPT(len(v), d=32, layers=2, heads=2, max_len=64).eval()
    x = torch.tensor([v.encode(CYC)[:30]]); y = x.clone(); y[0, 20] = (y[0, 20] + 1) % len(v)
    with torch.no_grad(): a, b = m(x), m(y)
    assert torch.allclose(a[0, :20], b[0, :20], atol=1e-5) and not torch.allclose(a[0, 20:], b[0, 20:], atol=1e-5)

def test_resume_is_bitwise_deterministic():
    v = A.Vocab.build(MOLS); enc = [v.encode(s) for s in MOLS]; d = tempfile.mkdtemp()
    def run(steps, ckpt, resume=False):
        torch.manual_seed(1); m = A.GPT(len(v), d=32, layers=2, heads=2, max_len=64)
        return A.train(m, enc, v, steps=steps, batch_size=4, lr=1e-3, seed=7, ckpt=ckpt, ckpt_every=10, resume=resume, device="cpu")
    full = run(20, os.path.join(d, "full.pt")); part = run(10, os.path.join(d, "p.pt")); resumed = run(20, os.path.join(d, "p.pt"), resume=True)
    for (k, a), (_, b) in zip(full.state_dict().items(), resumed.state_dict().items()): assert torch.equal(a, b), k

def test_macrocycle_upsampling_changes_batch_composition():
    v = A.Vocab.build(MOLS); enc = [v.encode(s) for s in MOLS]; macro = np.array([A.has_macrocycle(s) for s in MOLS])
    assert macro.sum() >= 2 and macro.sum() < len(MOLS)
    w1 = A.sampling_weights(macro, upsample=1.0); w20 = A.sampling_weights(macro, upsample=20.0)
    f = lambda w: np.mean([macro[i] for st in range(300) for i in A.batch_indices(len(MOLS), 8, st, 3, w)])
    assert f(w20) > f(w1) + 0.2, (f(w1), f(w20))

def test_learns_and_samples_valid_molecules():
    torch.manual_seed(0); v = A.Vocab.build(MOLS); enc = [v.encode(s) for s in MOLS]; m = A.GPT(len(v), d=64, layers=2, heads=2, max_len=160)
    l0 = A.eval_loss(m, enc, v, "cpu"); A.train(m, enc, v, steps=400, batch_size=8, lr=3e-3, seed=0, device="cpu"); l1 = A.eval_loss(m, enc, v, "cpu")
    assert l1 < 0.35 * l0, (l0, l1)
    out = A.sample(m, v, n=60, max_len=150, temperature=0.8, seed=0, device="cpu"); ok = np.mean([A.valid(s) for s in out])
    assert ok > 0.5, ok

if __name__ == "__main__":
    k = 0
    for n, f in sorted(globals().items()):
        if n.startswith("test_"): f(); k += 1; print("PASS", n)
    print(k, "tests passed")
