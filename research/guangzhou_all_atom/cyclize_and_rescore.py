"""Does head-to-tail macrocyclization move the generated designs toward permeable chemistry?
(tests the Phase-1 closure lever's developability payoff, computationally).

Takes generated peptide sequences, forms the head-to-tail amide bond (RDKit), and compares
linear vs cyclized on MW / HBD / TPSA and predicted permeability (the ECFP4 regressor). The
chemistry analysis predicted cyclization should cut HBD/TPSA; this quantifies the effect and how
many designs become predicted-permeable after closure.

Honest limits: 2D macrocyclization of the sequence (not the generator's 3D closure); permeability
model is ranking-grade (R2~0.23); still no N-methylation (needs Phase-1b) and no wet lab.
"""
import argparse
import csv
import json
from pathlib import Path

import numpy as np
from rdkit import Chem, RDLogger
from rdkit.Chem import Descriptors, rdMolDescriptors, rdFingerprintGenerator
from sklearn.ensemble import HistGradientBoostingRegressor

RDLogger.DisableLog("rdApp.*")
ROOT = Path(__file__).resolve().parent
_FP = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
_ACID = Chem.MolFromSmarts("[CX3](=O)[OX2H1]")               # C-terminal COOH
_AMINE = Chem.MolFromSmarts("[NX3;H2;!$([NX3][CX3]=[OX1])]")  # N-terminal free amine


def cyclize(mol):
    """Form head-to-tail amide: bond N-term amine N to C-term carbonyl C, drop the -OH."""
    a = mol.GetSubstructMatches(_ACID)
    n = mol.GetSubstructMatches(_AMINE)
    if not a or not n:
        return None
    c_atom, oh_atom = a[-1][0], a[-1][1]   # carboxyl C, hydroxyl O
    n_atom = n[0][0]                        # amine N
    rw = Chem.RWMol(mol)
    rw.AddBond(n_atom, c_atom, Chem.BondType.SINGLE)
    rw.RemoveAtom(oh_atom)
    m = rw.GetMol()
    try:
        Chem.SanitizeMol(m)
    except Exception:
        return None
    return m


def feats(mol):
    return {"mw": Descriptors.MolWt(mol), "hbd": rdMolDescriptors.CalcNumHBD(mol),
            "tpsa": rdMolDescriptors.CalcTPSA(mol),
            "fp": np.asarray(_FP.GetFingerprint(mol), dtype=np.float32)}


def train_perm(csv_path, n=5, seed=0):
    X, y = [], []
    for r in csv.DictReader(open(csv_path)):
        try:
            p = float(r.get("Permeability", ""))
        except (TypeError, ValueError):
            continue
        if not (-10.5 < p < -3.5):
            continue
        m = Chem.MolFromSmiles(r.get("SMILES", "").strip())
        if m is not None:
            X.append(np.asarray(_FP.GetFingerprint(m), dtype=np.float32)); y.append(p)
    X, y = np.array(X), np.array(y)
    rng = np.random.default_rng(seed); models = []
    for s in range(n):
        idx = rng.integers(0, len(y), len(y))
        mm = HistGradientBoostingRegressor(max_iter=150, learning_rate=0.06, max_leaf_nodes=31,
                                           l2_regularization=1.0, random_state=s)
        mm.fit(X[idx], y[idx]); models.append(mm)
    return lambda F: np.vstack([m.predict(F) for m in models]).mean(0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--perm-csv", type=Path, default=ROOT / "data/raw/CycPeptMPDB_Peptide_All.csv")
    ap.add_argument("--attempts", type=Path, default=ROOT / "results/cyclic_eval/attempts_none_n16.json")
    ap.add_argument("--out", type=Path, default=ROOT / "results/cyclization_permeability.json")
    args = ap.parse_args()

    perm = train_perm(args.perm_csv)
    seqs = [r["sequence"] for r in json.load(open(args.attempts))
            if r.get("status") == "serialized" and r.get("sequence")]

    lin, cyc = [], []           # feature dicts for paired designs (only where cyclization succeeds)
    for s in seqs:
        m = Chem.MolFromSequence(s)
        if m is None:
            continue
        mc = cyclize(m)
        if mc is None:
            continue
        lin.append(feats(m)); cyc.append(feats(mc))
    n = len(lin)
    if n == 0:
        print("cyclization produced 0 valid macrocycles"); return

    def agg(dl, key):
        return round(float(np.mean([d[key] for d in dl])), 2)
    pl = perm(np.array([d["fp"] for d in lin]))
    pc = perm(np.array([d["fp"] for d in cyc]))

    report = {
        "n_designs_cyclized": n, "cyclization_success_rate": round(n / len(seqs), 3),
        "linear": {"mw": agg(lin, "mw"), "hbd": agg(lin, "hbd"), "tpsa": agg(lin, "tpsa"),
                   "pred_logPapp_mean": round(float(pl.mean()), 3),
                   "frac_permeable(>-6)": round(float((pl > -6).mean()), 3)},
        "cyclized": {"mw": agg(cyc, "mw"), "hbd": agg(cyc, "hbd"), "tpsa": agg(cyc, "tpsa"),
                     "pred_logPapp_mean": round(float(pc.mean()), 3),
                     "frac_permeable(>-6)": round(float((pc > -6).mean()), 3)},
        "delta_pred_logPapp_cyc_minus_lin": round(float((pc - pl).mean()), 3),
        "reference_permeable_subset": {"mw": 949, "hbd": 3.7, "tpsa": 209, "n_nmethyl": 2.9},
        "interpretation": ("Cyclization should cut HBD/TPSA and raise predicted permeability. Even "
                           "if it helps, designs still lack N-methylation and are large — so closure "
                           "alone is necessary-not-sufficient; Phase-1b (N-Me) + smaller designs "
                           "still needed to reach the permeable region."),
        "limits": ["2D head-to-tail cyclization of the sequence, not the generator's 3D closure",
                   "permeability model ranking-grade (R2~0.23); no wet lab"],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
