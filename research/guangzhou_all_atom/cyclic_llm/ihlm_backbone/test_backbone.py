"""Tests for the PeptideCLM-2 backbone re-implementation and the IH-LM adapter (CPU). Needs the weights: PCLM2_DIR=<dir containing small/ [and base/]> or run fetch_weights.py.
Public test molecules: CREMP (CC BY 4.0) 4-/5-mers with any CycPeptMPDB flat-structure match removed; CycPeptMPDB is used ONLY for that exclusion. Set CREMP_CSV and CYCPEPTMPDB_CSV."""
import os, sys, csv, math, random, unittest
import numpy as np, torch
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from fetch_weights import fetch
from pclm_tokenizer import PClmTokenizer
from pclm_encoder import PClmMLM
from rdkit import Chem, RDLogger; RDLogger.DisableLog("rdApp.*")
SCR = "/private/tmp/claude-501/-Users-kky-biomate-review/195b4da4-5c44-48ae-a4e1-005d493239c0/scratchpad"
CREMP = os.environ.get("CREMP_CSV", SCR + "/cremp_summary.csv"); CPMPDB = os.environ.get("CYCPEPTMPDB_CSV", SCR + "/CycPeptMPDB_Peptide_All.csv")

def flat(s):
    m = Chem.MolFromSmiles(s)
    if m is None: return None
    Chem.RemoveStereochemistry(m); return Chem.MolToSmiles(m)

def public_test_set(n=200, seed=0):
    with open(CPMPDB, encoding="utf-8-sig") as fh: excl = {flat(r["SMILES"]) for r in csv.DictReader(fh) if r.get("SMILES")}
    excl.discard(None)
    with open(CREMP) as fh: rows = [r for r in csv.DictReader(fh) if int(r["num_monomers"]) in (4, 5)]
    random.Random(seed).shuffle(rows); out = []
    for r in rows:
        f = flat(r["smiles"])
        if f is not None and f not in excl: out.append(r["smiles"])
        if len(out) == n: break
    return out

_D = {}
def wdir(size="small"):
    if size not in _D: _D[size] = fetch(size)
    return _D[size]
TEST = None
def test_set():
    global TEST
    if TEST is None: TEST = public_test_set()
    return TEST

def mlm_nll(model, tk, smi, p=0.15, seed=0):
    g = torch.Generator().manual_seed(seed); tot = n = hit = 0
    for i in range(0, len(smi), 20):
        enc = [tk.encode(s) for s in smi[i:i + 20]]; T = max(map(len, enc)); X = torch.zeros(len(enc), T, dtype=torch.long); M = torch.zeros_like(X)
        for j, e in enumerate(enc): X[j, :len(e)] = torch.tensor(e); M[j, :len(e)] = 1
        sel = (torch.rand(X.shape, generator=g) < p) & (X > 4) & (M == 1); Xin = X.clone(); Xin[sel] = tk.MASK
        with torch.no_grad(): lg = model(Xin, M)
        lp = torch.log_softmax(lg[sel], -1); t = X[sel]; tot += float(-lp[torch.arange(len(t)), t].sum()); n += len(t); hit += int((lg[sel].argmax(-1) == t).sum())
    return tot / n, hit / n


class TestTokenizer(unittest.TestCase):
    def test_parity_with_rust_tokenizers(self):
        from tokenizers import Tokenizer      # library reads the JSON; no repo code
        d = wdir(); ref = Tokenizer.from_file(os.path.join(d, "tokenizer.json")); tk = PClmTokenizer(os.path.join(d, "tokenizer.json"))
        with open(CREMP) as fh: rows = [r["smiles"] for r in list(csv.DictReader(fh))[:3000]]
        extra = ["CC(C)C[C@H](NC(=O)[C@@H]1CCCN1)C(=O)O", "C%11CC%11", "[Xx]CC", "ClCCBr", "N#CC(=O)O.[Na+]", "XXXXX", "C" * 150, "", "C" * 101]
        bad = [s for s in rows + extra if tk.encode(s) != ref.encode(s).ids]
        self.assertEqual(bad, [])
    def test_special_ids_and_truncation(self):
        tk = PClmTokenizer(os.path.join(wdir(), "tokenizer.json"), max_len=16); e = tk.encode("CC" * 50)
        self.assertEqual((e[0], e[-1], len(e)), (tk.CLS, tk.SEP, 16)); self.assertEqual(len(tk), 405)


class TestEncoder(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        d = wdir(); cls.tk = PClmTokenizer(os.path.join(d, "tokenizer.json")); cls.m, cls.cfg, cls.res = PClmMLM.from_dir(d); cls.m.eval()
    def test_strict_load_and_param_count(self):
        self.assertEqual((self.res.missing_keys, self.res.unexpected_keys), ([], [])); self.assertEqual(sum(p.numel() for p in self.m.parameters()), 31668629)
    def test_finite_and_padding_invariant(self):
        smi = test_set()[:6]; enc = [self.tk.encode(s) for s in smi]; T = max(map(len, enc)); X = torch.zeros(len(enc), T, dtype=torch.long); M = torch.zeros_like(X)
        for j, e in enumerate(enc): X[j, :len(e)] = torch.tensor(e); M[j, :len(e)] = 1
        with torch.no_grad(): lg, h = self.m(X, M, return_hidden=True)
        self.assertTrue(torch.isfinite(lg).all())
        for j, e in enumerate(enc):                                         # same molecule alone (no padding) == in the padded batch
            with torch.no_grad(): _, h1 = self.m(torch.tensor([e]), torch.ones(1, len(e), dtype=torch.long), return_hidden=True)
            self.assertLess(float((h1[0] - h[j, :len(e)]).abs().max()), 2e-4)
    def test_mlm_loss_far_below_random_and_negative_controls(self):
        nll, acc = mlm_nll(self.m, self.tk, test_set()); self.assertLess(nll, 1.0); self.assertGreater(acc, 0.6)                    # observed 0.317 / 0.890
        self.m.set_rope_interleaved(False)
        try: nll_bad, _ = mlm_nll(self.m, self.tk, test_set())
        finally: self.m.set_rope_interleaved(True)
        self.assertGreater(nll_bad, 2.0 * nll + 1.0)                                                                              # the test can fail: wrong RoPE convention -> ~3.0
        torch.manual_seed(0); rnd = PClmMLM(self.cfg).eval(); nll_r, _ = mlm_nll(rnd, self.tk, test_set()); self.assertGreater(nll_r, 0.9 * math.log(405))
    def test_deterministic(self):
        X = torch.tensor([self.tk.encode(test_set()[0])])
        with torch.no_grad(): a = self.m(X); b = self.m(X)
        self.assertTrue(torch.equal(a, b)); m2, _, _ = PClmMLM.from_dir(wdir()); m2.eval()
        with torch.no_grad(): self.assertTrue(torch.equal(a, m2(X)))
    def test_stereo_and_nme_sensitivity_reported(self):
        from symbolic import propose_edit_smiles
        out = {"dflip": [], "nme": [], "other": []}; rng = random.Random(1); smi = test_set()[:60]
        def emb(s):
            with torch.no_grad(): _, h = self.m(torch.tensor([self.tk.encode(s)]), return_hidden=True)
            return h[0, 1:-1].mean(0)
        cos = lambda a, b: float(torch.nn.functional.cosine_similarity(a, b, dim=0))
        for s in smi:
            e0 = emb(s)
            for et, v in propose_edit_smiles(s):
                k = "dflip" if et.startswith("dflip") else ("nme" if et.startswith("nme") else None)
                if k and len(out[k]) < 80: out[k].append(1 - cos(e0, emb(v)))
            o = rng.choice(smi)
            if o != s: out["other"].append(1 - cos(e0, emb(o)))
        rep = {k: (round(float(np.mean(v)), 5), len(v)) for k, v in out.items()}; print("\n1-cosine (mean, n):", rep)
        self.assertGreater(rep["dflip"][1], 20); self.assertGreater(rep["nme"][1], 20)
        self.assertGreater(rep["dflip"][0], 1e-5); self.assertGreater(rep["nme"][0], 1e-5)                                           # edits move the embedding
        self.assertLess(rep["dflip"][0], rep["other"][0]); self.assertLess(rep["nme"][0], rep["other"][0])                           # but less than swapping the molecule


class TestAdapter(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, os.path.join(HERE, "..", "ihlm")); sys.path.insert(0, os.path.join(HERE, "..", "v4_eval"))
        import adapter; cls.A = adapter
    def test_zero_init_cross_attention_equals_pretrained_encoder(self):
        from pclm_encoder import PClmMLM
        m, _, _ = PClmMLM.from_dir(wdir()); m.eval(); bb = self.A.PClmBackbone(m, m.cfg["num_heads"]).eval(); tk = PClmTokenizer(os.path.join(wdir(), "tokenizer.json"))
        X = torch.tensor([tk.encode(s) for s in test_set()[:1]]); mem = torch.randn(1, 7, bb.d); mm = torch.ones(1, 7, dtype=torch.bool)
        with torch.no_grad(): _, h_ref = m(X, torch.ones_like(X), return_hidden=True); h0, _ = bb(X); h1, _ = bb(X, mem, mm)
        self.assertLess(float((h0 - h_ref).abs().max()), 1e-5); self.assertLess(float((h1 - h_ref).abs().max()), 1e-5)         # memory is ignored until cproj is trained
    def _rows(self, smi, label):
        return [dict(smiles=s, target_seq="perm", label=float(label(s)), source="labA" if i % 2 == 0 else "labB") for i, s in enumerate(smi)]
    def test_loop_interface_all_modules(self):
        L = self.A.PClmIHLM(wdir(), modules=("M1", "M2", "M3", "M4", "M5"), knowledge=lambda ss: [float(s.count("C")) for s in ss], k=3, slow_every=1, train_cfg=dict(steps=4, bs=16))
        smi = test_set()[:40]; nme = lambda s: s.count("N(C)") + s.count("n(C)") + s.count("N1C") * 0.0
        m1 = L.update(self._rows(smi[:30], nme), mode="finetune_ranking", seed=0)
        self.assertIsInstance(m1, self.A.PClmIHLM); self.assertTrue(m1.net_trained); self.assertIsInstance(m1.net.bb, self.A.PClmBackbone)
        sc = m1.score(smi[30:], "perm", sources=["labA"] * 10); self.assertEqual(len(sc), 10); self.assertTrue(all(x is not None and math.isfinite(x) for x in sc))
        u = m1.uncertainty(smi[30:34], "perm", sources=["labA"] * 4); self.assertTrue(all(x is not None for x in u))
        self.assertNotEqual(L.fingerprint(), m1.fingerprint()); self.assertEqual(m1.provenance["backbone_init"], "open_weights")
        fz = m1.update(self._rows(smi[:2], nme), mode="frozen"); self.assertEqual(fz.fingerprint(), m1.fingerprint())
        self.assertTrue(m1.propose_edits(smi[0], "perm", source="labA", n=3) is not None)
    def test_planted_signal_is_learnable(self):                      # label = number of N-methylated amides (planted, chemistry-derived); net only
        smi = [s for s in public_test_set(400, seed=3)]
        nme = lambda s: float(len(Chem.MolFromSmiles(s).GetSubstructMatches(Chem.MolFromSmarts("[NX3;H0;!$(N(C)(C)(C)C)]([CH3])C(=O)"))))
        ys = np.array([nme(s) for s in smi]); self.assertGreater(ys.std(), 0.5)
        tr, te = list(range(0, 240)), list(range(240, 400))
        L = self.A.PClmIHLM(wdir(), modules=("M5",), slow_every=1, train_cfg=dict(steps=120, bs=32, lr=1e-4))
        m = L.update([dict(smiles=smi[i], target_seq="perm", label=ys[i], source="labA") for i in tr], mode="finetune_ranking", seed=0)
        p = np.array(m.net_predict([smi[i] for i in te], "perm", use_analogs=False)["y"]); from scipy.stats import spearmanr
        rho = spearmanr(p, ys[te]).correlation; print("\nplanted N-Me count: held-out Spearman", round(float(rho), 3)); self.assertGreater(rho, 0.5)

if __name__ == "__main__":
    unittest.main(verbosity=2)
