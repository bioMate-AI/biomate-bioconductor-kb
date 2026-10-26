"""Plain-PyTorch D-MPNN (Chemprop-style directed message passing) for cyclic peptides.
Atoms: element, degree, formal charge, #H, hybridisation, aromatic, in-ring, in-macrocycle(ring>=12), CIP R/S (so D- vs L-residues are
distinguished), N-methyl-amide-nitrogen flag, amide-N/carbonyl flags. Bonds: type, conjugated, in-ring, in-macrocycle, E/Z.
Modes: G1 single head + assay one-hot at readout; G2 assay embedding + per-assay heads (multi-task, masked); G3 = G2 + pretrained encoder.
Usage: gnn.py G1|G2|G3 [splits] [--seeds N] ; gnn.py pretrain"""
import sys, time, pickle, argparse, numpy as np, pandas as pd, torch, torch.nn as nn
from rdkit import Chem, RDLogger
from rdkit.Chem import Descriptors
from common import *
import cv
RDLogger.DisableLog("rdApp.*")
DEV = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
ELEM = ["C", "N", "O", "S", "F", "Cl", "Br", "I", "P", "H"]
HYB = [Chem.HybridizationType.SP, Chem.HybridizationType.SP2, Chem.HybridizationType.SP3]
def oh(v, choices):
    o = [0.0] * (len(choices) + 1); o[choices.index(v) if v in choices else -1] = 1.0; return o
_NME = Chem.MolFromSmarts("[CH3][NX3;H0]C=O")

def mol_graph(smiles):
    m = Chem.MolFromSmiles(smiles)
    Chem.AssignStereochemistry(m, cleanIt=True, force=True)
    ri = m.GetRingInfo(); mac_atoms = set(a for r in ri.AtomRings() if len(r) >= 12 for a in r)
    nme_n = set(t[1] for t in m.GetSubstructMatches(_NME))
    amideN = set(t[0] for t in m.GetSubstructMatches(Chem.MolFromSmarts("[NX3]C=O")))
    carbO = set(t[0] for t in m.GetSubstructMatches(Chem.MolFromSmarts("[OX1]=C[NX3]")))
    X = []
    for a in m.GetAtoms():
        cip = a.GetPropsAsDict().get("_CIPCode", "")
        f = (oh(a.GetSymbol(), ELEM) + oh(a.GetDegree(), [1, 2, 3, 4]) + oh(a.GetFormalCharge(), [-1, 0, 1]) + oh(a.GetTotalNumHs(), [0, 1, 2, 3])
             + oh(a.GetHybridization(), HYB) + [float(a.GetIsAromatic()), float(a.IsInRing()), float(a.GetIdx() in mac_atoms),
             float(cip == "R"), float(cip == "S"), float(a.GetIdx() in nme_n), float(a.GetIdx() in amideN), float(a.GetIdx() in carbO), a.GetMass() / 100.0])
        X.append(f)
    src, dst, B = [], [], []
    for b in m.GetBonds():
        i, j = b.GetBeginAtomIdx(), b.GetEndAtomIdx()
        f = (oh(b.GetBondType(), [Chem.BondType.SINGLE, Chem.BondType.DOUBLE, Chem.BondType.TRIPLE, Chem.BondType.AROMATIC])
             + [float(b.GetIsConjugated()), float(b.IsInRing()), float(i in mac_atoms and j in mac_atoms and b.IsInRing()),
                float(b.GetStereo() in (Chem.BondStereo.STEREOE, Chem.BondStereo.STEREOZ))])
        src += [i, j]; dst += [j, i]; B += [f, f]
    n_e = len(src); rev = np.array([k ^ 1 for k in range(n_e)])
    return dict(x=np.array(X, np.float32), src=np.array(src), dst=np.array(dst), ef=np.array(B, np.float32), rev=rev)

def collate(gs, idx):
    xs, src, dst, ef, rev, bat = [], [], [], [], [], []; off = 0; eoff = 0
    for b, i in enumerate(idx):
        g = gs[i]; n = len(g["x"]); xs.append(g["x"]); src.append(g["src"] + off); dst.append(g["dst"] + off); ef.append(g["ef"])
        rev.append(g["rev"] + eoff); bat.append(np.full(n, b)); off += n; eoff += len(g["src"])
    T = lambda a, dt=None: torch.as_tensor(np.concatenate(a), dtype=dt).to(DEV)
    return T(xs), T(src, torch.long), T(dst, torch.long), T(ef), T(rev, torch.long), T(bat, torch.long), len(idx)

class DMPNN(nn.Module):
    def __init__(self, fa, fb, h=128, depth=4, drop=0.1):
        super().__init__()
        self.depth = depth; self.Wi = nn.Linear(fa + fb, h, bias=False); self.Wm = nn.Linear(h, h, bias=False)
        self.Wo = nn.Linear(fa + h, h); self.drop = nn.Dropout(drop); self.h = h
    def forward(self, x, src, dst, ef, rev, bat, B):
        e0 = self.Wi(torch.cat([x[src], ef], 1)); he = torch.relu(e0)
        for _ in range(self.depth - 1):
            node = torch.zeros(x.shape[0], self.h, device=x.device).index_add_(0, dst, he)   # sum of incoming
            m = node[src] - he[rev]                                                          # exclude the reverse edge
            he = self.drop(torch.relu(e0 + self.Wm(m)))
        node = torch.zeros(x.shape[0], self.h, device=x.device).index_add_(0, dst, he)
        ha = self.drop(torch.relu(self.Wo(torch.cat([x, node], 1))))
        cnt = torch.zeros(B, device=x.device).index_add_(0, bat, torch.ones_like(bat, dtype=torch.float)).clamp(min=1)
        return torch.zeros(B, self.h, device=x.device).index_add_(0, bat, ha) / cnt[:, None]

class Net(nn.Module):
    def __init__(self, fa, fb, mode, h=128, nassay=4, nout=1):
        super().__init__()
        self.enc = DMPNN(fa, fb, h); self.mode = mode
        if mode == "G1":
            self.head = nn.Sequential(nn.Linear(h + nassay, h), nn.ReLU(), nn.Dropout(0.1), nn.Linear(h, 1))
        else:
            self.emb = nn.Embedding(nassay, 16)
            self.heads = nn.ModuleList([nn.Sequential(nn.Linear(h + 16, h), nn.ReLU(), nn.Dropout(0.1), nn.Linear(h, 1)) for _ in range(nassay)])
    def forward(self, batch, a):
        z = self.enc(*batch)
        if self.mode == "G1": return self.head(torch.cat([z, nn.functional.one_hot(a, 4).float()], 1))[:, 0]
        z = torch.cat([z, self.emb(a)], 1); out = torch.stack([hd(z)[:, 0] for hd in self.heads], 1)
        return out.gather(1, a[:, None])[:, 0]

def graphs_for(df):
    path = os.path.join(SCRATCH, "graphs_cpm.pkl")
    if os.path.exists(path): return pickle.load(open(path, "rb"))
    gs = [mol_graph(s) for s in df.can]; pickle.dump(gs, open(path, "wb")); return gs

def fit_predict(gs, y, a, tr, va, te, mode, seed, pre=None, epochs=30, bs=64, lr=1e-3, patience=6):
    torch.manual_seed(seed); np.random.seed(seed)
    mu, sd = y[tr].mean(), y[tr].std()
    net = Net(gs[0]["x"].shape[1], gs[0]["ef"].shape[1], mode).to(DEV)
    if pre is not None: net.enc.load_state_dict(pre)
    opt = torch.optim.Adam(net.parameters(), lr=lr); sched = torch.optim.lr_scheduler.ReduceLROnPlateau(opt, factor=0.5, patience=2)
    yt = torch.as_tensor((y - mu) / sd, dtype=torch.float32); at = torch.as_tensor(a, dtype=torch.long)
    def predict(idx):
        net.eval(); out = []
        with torch.no_grad():
            for i in range(0, len(idx), 256):
                j = idx[i:i + 256]; out.append(net(collate(gs, j), at[j].to(DEV)).cpu().numpy())
        return np.concatenate(out) * sd + mu
    best, bstate, bad = 1e9, None, 0
    for ep in range(epochs):
        net.train(); perm = np.random.permutation(tr)
        for i in range(0, len(perm), bs):
            j = perm[i:i + bs]
            if len(j) < 2: continue
            loss = nn.functional.mse_loss(net(collate(gs, j), at[j].to(DEV)), yt[j].to(DEV))
            opt.zero_grad(); loss.backward(); opt.step()
        v = rmse(y[va], predict(va)); sched.step(v)
        if v < best - 1e-4: best, bad = v, 0; bstate = {k: t.detach().clone() for k, t in net.state_dict().items()}
        else:
            bad += 1
            if bad >= patience: break
    net.load_state_dict(bstate)
    return predict(te), best, ep + 1

def run(mode, which, seeds, tag=None, epochs=30):
    c, _ = cv.load(); gs = graphs_for(c); y = c.y.values.astype(float); a = np.array([ASSAY_ORDER.index(x) for x in c.assay])
    pre = torch.load(os.path.join(SCRATCH, "pretrained_enc.pt")) if mode == "G3" else None
    out = []
    for s in cv.splits(which):
        ns = seeds if s["split"] == "S0" else 1
        for sd in range(ns):
            t0 = time.time(); p, vb, ne = fit_predict(gs, y, a, s["tr"], s["va"], s["te"], mode, sd, pre, epochs)
            out.append(pd.DataFrame({"split": s["split"], "fold": s["fold"] * 10 + sd if s["split"] == "S0" else s["fold"], "row": s["te"], "pred": p}))
            print(mode, s["split"], s["fold"], "seed", sd, "test_r2=%.3f val_rmse=%.3f ep=%d %.0fs" % (r2(y[s["te"]], p), vb, ne, time.time() - t0), flush=True)
            pd.concat(out).to_csv(os.path.join(HERE, f"results/preds/{tag or mode}.csv"), index=False)

# ---- self-supervised pretraining on ChEMBL macrocycle pool: regress standardised RDKit descriptors
PRE_DESC = ["MolLogP", "TPSA", "NumHDonors", "NumHAcceptors", "NumRotatableBonds", "FractionCSP3", "RingCount", "NumAromaticRings", "LabuteASA", "BertzCT",
            "MolMR", "HeavyAtomCount", "NumAmideBonds" if hasattr(Descriptors, "NumAmideBonds") else "NHOHCount", "NOCount", "NumHeteroatoms", "qed",
            "Chi0v", "Chi1v", "Kappa1", "Kappa2", "Kappa3", "HallKierAlpha", "fr_amide", "fr_halogen", "fr_benzene", "VSA_EState1", "SlogP_VSA2", "PEOE_VSA1", "SMR_VSA1", "EState_VSA1"]
def pretrain(epochs=8, maxn=20000):
    pool = pd.read_csv(os.path.join(HERE, "data/chembl_macrocycle_pool.csv")).sample(frac=1, random_state=0).head(maxn).reset_index(drop=True)
    fns = dict(Descriptors.descList); gs, T = [], []
    for s in pool.smiles:
        try:
            g = mol_graph(s); m = Chem.MolFromSmiles(s); T.append([fns[n](m) for n in PRE_DESC]); gs.append(g)
        except Exception: pass
    T = np.nan_to_num(np.clip(np.array(T, np.float64), -1e5, 1e5)); T = ((T - T.mean(0)) / (T.std(0) + 1e-6)).astype(np.float32)
    print("pretrain mols", len(gs), flush=True)
    enc = DMPNN(gs[0]["x"].shape[1], gs[0]["ef"].shape[1]).to(DEV); head = nn.Linear(128, T.shape[1]).to(DEV)
    opt = torch.optim.Adam(list(enc.parameters()) + list(head.parameters()), lr=1e-3); Tt = torch.as_tensor(T)
    n = len(gs); hold = np.arange(n)[-500:]; trn = np.arange(n)[:-500]
    for ep in range(epochs):
        enc.train(); perm = np.random.default_rng(ep).permutation(trn); t0 = time.time()
        for i in range(0, len(perm), 64):
            j = perm[i:i + 64]; loss = nn.functional.mse_loss(head(enc(*collate(gs, j))), Tt[j].to(DEV)); opt.zero_grad(); loss.backward(); opt.step()
        enc.eval()
        with torch.no_grad(): hl = nn.functional.mse_loss(head(enc(*collate(gs, hold))), Tt[hold].to(DEV)).item()
        print("pre ep", ep, "holdout mse %.3f" % hl, "%.0fs" % (time.time() - t0), flush=True)
    torch.save({k: v.cpu() for k, v in enc.state_dict().items()}, os.path.join(SCRATCH, "pretrained_enc.pt"))
    json.dump({"n_pretrain_mols": n, "holdout_mse_std_units": hl, "targets": PRE_DESC, "epochs": epochs}, open(os.path.join(HERE, "results/pretrain_report.json"), "w"), indent=1)

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("mode"); ap.add_argument("splits", nargs="?", default="S0,S1,S2,S3"); ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--epochs", type=int, default=30); ap.add_argument("--tag"); A = ap.parse_args()
    if A.mode == "pretrain": pretrain()
    else: run(A.mode, A.splits.split(","), A.seeds, A.tag, A.epochs)
