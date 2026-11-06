"""Does non-natural chemistry (N-methylation, size, H-bond donors) drive permeability? — evidence
for Phase-1b from real data. Quantifies, on the 8466 CycPeptMPDB cyclic peptides with measured
log Papp, how permeability relates to: N-methylated backbone amides, molecular weight, H-bond
donors (NH/OH), TPSA, ring count. Grounds the decision to invest in non-natural-monomer
generation (which the current natural-AA generator cannot produce).

Also contrasts the *generated* designs' chemistry vs the permeable subset of CycPeptMPDB, to show
whether the generator's outputs are in a permeable region of chemistry space.
"""
import argparse
import csv
import json
from pathlib import Path

import numpy as np
from rdkit import Chem, RDLogger
from rdkit.Chem import Descriptors, rdMolDescriptors

RDLogger.DisableLog("rdApp.*")
ROOT = Path(__file__).resolve().parent
NME = Chem.MolFromSmarts("[NX3;$([N]C=O)][CH3]")  # N-methylated amide (approx)


def features(mol):
    return {
        "mw": Descriptors.MolWt(mol),
        "n_nmethyl": len(mol.GetSubstructMatches(NME)),
        "hbd": rdMolDescriptors.CalcNumHBD(mol),
        "tpsa": rdMolDescriptors.CalcTPSA(mol),
        "rings": rdMolDescriptors.CalcNumRings(mol),
    }


def pearson(a, b):
    a, b = np.array(a), np.array(b)
    if len(a) < 3 or a.std() == 0 or b.std() == 0:
        return None
    return float(np.corrcoef(a, b)[0, 1])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--perm-csv", type=Path, default=ROOT / "data/raw/CycPeptMPDB_Peptide_All.csv")
    ap.add_argument("--attempts", type=Path, default=ROOT / "results/cyclic_eval/attempts_none_n16.json")
    ap.add_argument("--out", type=Path, default=ROOT / "results/chemistry_permeability_analysis.json")
    args = ap.parse_args()

    perm, feats = [], []
    for r in csv.DictReader(open(args.perm_csv)):
        try:
            p = float(r.get("Permeability", ""))
        except (TypeError, ValueError):
            continue
        if not (-10.5 < p < -3.5):
            continue
        m = Chem.MolFromSmiles(r.get("SMILES", "").strip())
        if m is None:
            continue
        perm.append(p); feats.append(features(m))
    perm = np.array(perm)
    F = {k: np.array([f[k] for f in feats]) for k in feats[0]}

    corr = {k: round(pearson(F[k], perm), 3) for k in F}
    # permeability by N-methyl bins
    nme = F["n_nmethyl"]
    bins = {"0": nme == 0, "1-2": (nme >= 1) & (nme <= 2), "3-5": (nme >= 3) & (nme <= 5), "6+": nme >= 6}
    perm_by_nme = {k: {"n": int(v.sum()), "mean_logPapp": round(float(perm[v].mean()), 3)}
                   for k, v in bins.items() if v.sum()}
    # permeable subset chemistry (logPapp > -6) vs whole
    permeable = perm > -6.0
    chem_permeable = {k: round(float(F[k][permeable].mean()), 2) for k in F}
    chem_all = {k: round(float(F[k].mean()), 2) for k in F}

    # generated designs chemistry
    gen = {k: [] for k in F}
    for rr in json.load(open(args.attempts)):
        if rr.get("status") == "serialized" and rr.get("sequence"):
            m = Chem.MolFromSequence(rr["sequence"])
            if m:
                for k, v in features(m).items():
                    gen[k].append(v)
    chem_gen = {k: round(float(np.mean(v)), 2) for k, v in gen.items() if v}

    report = {
        "n_cycpeptmpdb": int(len(perm)),
        "pearson_r_vs_logPapp": corr,
        "note_corr": "higher logPapp = more permeable; negative r means the feature HURTS permeability",
        "logPapp_by_N_methyl_count": perm_by_nme,
        "chemistry_permeable_subset(logPapp>-6)": chem_permeable,
        "chemistry_all_cycpeptmpdb": chem_all,
        "chemistry_generated_designs": chem_gen,
        "interpretation": ("If N-methylation correlates + and HBD/TPSA correlate -, non-natural "
                           "chemistry (N-Me, low HBD) is the permeability lever — which the natural-"
                           "AA generator cannot access, motivating Phase-1b. Compare generated-"
                           "design chemistry to the permeable subset to see the gap."),
        "limits": ["correlational (measured permeability, real peptides); not causal per-design",
                   "N-methyl SMARTS is approximate; generated designs scored as linear peptides"],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
