#!/usr/bin/env python3
"""Planted-label wrapper for the frozen aware-vs-blind experiment (docs/20261031_FROZEN_AWARE_VS_BLIND_PREREG.md, section 6).
usage: planted_run.py {chiral|flat} <run_l7a.py arguments...>
Replaces the raw label of every peptide by a SYNTHETIC label, then runs the unchanged run_l7a.main() (same regimes, splits, source standardisation, hit threshold, frozen arms).
  chiral: signal = fraction of assigned CIP centres labelled S (a function of STEREOCHEMISTRY; stereoisomers of one graph differ) + noise
  flat:   signal = Crippen logP (a function of the 2-D GRAPH only; stereoisomers of one graph are identical) + noise
Noise: N(0, 0.5 sd(signal)), one fixed generator (seed 20261031) in record order. Nothing here touches the real labels used elsewhere."""
import os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); LR = os.path.dirname(HERE); sys.path.insert(0, LR)


def synthetic_raw_labels(smiles, kind, seed=20261031):
    from rdkit import Chem
    from rdkit.Chem import Crippen
    sig = []
    for s in smiles:
        m = Chem.MolFromSmiles(s)
        if kind == "chiral":
            cc = [c for _, c in Chem.FindMolChiralCenters(m, includeUnassigned=True, useLegacyImplementation=True) if c in ("R", "S")]
            sig.append(sum(c == "S" for c in cc) / len(cc) if cc else 0.0)
        elif kind == "flat":
            sig.append(Crippen.MolLogP(m))
        else:
            raise SystemExit("kind must be chiral|flat")
    sig = np.asarray(sig, float); sd = sig.std() if sig.std() > 0 else 1.0
    z = (sig - sig.mean()) / sd
    return z + 0.5 * np.random.default_rng(seed).standard_normal(len(z))


def main():
    kind = sys.argv[1]; sys.argv = ["run_l7a.py"] + sys.argv[2:]
    import run_loop as R
    orig = R.load

    def load(path):
        recs = orig(path); y = synthetic_raw_labels([r["smiles"] for r in recs], kind)
        for r, v in zip(recs, y): r["y"] = float(v)
        return recs
    R.load = load
    import run_l7a
    run_l7a.main()


if __name__ == "__main__":
    main()
