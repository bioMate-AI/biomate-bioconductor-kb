"""Shared data prep for stratification analyses (Part A2/A3/A4)."""
import sys, os
import numpy as np, pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "loop_retro"))          # read-only import of source_normalize
import run_loop_prior as K
from rdkit import Chem, RDLogger
from rdkit.Chem import AllChem
RDLogger.DisableLog("rdApp.*")

FAMILIES = {
    "physchem": ["mw", "tpsa", "logp", "hbd", "hba", "rotb", "arom_rings", "heavy", "fsp3"],
    "ring_topology": ["n_monomers", "n_residues", "ring_res", "tail_res", "ring_atoms_max", "n_rings", "n_cap_n", "n_cap_c", "topo_lariat_sc_cterm", "topo_lariat_nterm_sc"],
    "nme_pattern": ["n_nme_final", "nme_frac_final", "nme_adj", "nme_alt", "nme_run", "nme_adj_pro", "nme_adj_D"],
    "chirality": ["n_D", "d_frac", "d_adj", "d_alt", "d_run", "n_D_and_nme", "n_dpro"],
    "composition": ["frac_aliphatic", "frac_aromatic", "frac_polar", "frac_positive", "frac_negative", "frac_proline", "frac_unknown", "n_pro", "n_gly",
                    "n_peptoid", "n_nalkyl", "n_ext", "n_alpha_disub", "n_backbone_mod", "n_unknown", "n_sidechain_mod", "n_nonstd_base"],
}


def load_labelled(ann_path=None):
    ann = pd.read_csv(ann_path or os.path.join(HERE, "data", "annotations.csv.gz"), index_col=0)
    d = ann[ann["pampa"].notna()].copy()
    d["y_raw"] = d["pampa"]; d["y"] = K.source_normalize(d["y_raw"].values, d["Source"].values)
    d["nme_frac_final"] = d["n_nme_final"] / d["n_residues"].clip(lower=1)
    d["topo_lariat_sc_cterm"] = (d["helm_topology"] == "lariat_sc_cterm").astype(int)
    d["topo_lariat_nterm_sc"] = (d["helm_topology"] == "lariat_nterm_sc").astype(int)
    codes, uniq = pd.factorize(d["flat_smiles"]); d["flat_id"] = codes
    d["flat_size"] = d.groupby("flat_id")["y"].transform("size")
    d["src_n"] = d.groupby("Source")["y"].transform("size")
    return d


def fingerprints(smiles, chiral):
    X = np.zeros((len(smiles), 2048), np.float32)
    for r, s in enumerate(smiles):
        m = Chem.MolFromSmiles(s)
        for i, c in AllChem.GetMorganFingerprint(m, 2, useChirality=chiral).GetNonzeroElements().items(): X[r, i % 2048] += c
    return X


def desc_matrix(d, families=None):
    cols = [c for f in (families or FAMILIES) for c in FAMILIES[f]]
    return d[cols].astype(float).values, cols


def strata(d):
    """name -> {level: boolean mask} (Part A3)."""
    S = {}
    S["topology"] = {k: (d.helm_topology == k).values for k in ("head_to_tail", "lariat_sc_cterm", "lariat_nterm_sc")}
    L = d.n_monomers
    S["length"] = {"<=5": (L <= 5).values, "6": (L == 6).values, "7": (L == 7).values, "8": (L == 8).values, ">=9": (L >= 9).values}
    n = d.n_nme_final
    S["n_methyl"] = {"0": (n == 0).values, "1-2": n.between(1, 2).values, "3-4": n.between(3, 4).values, ">=5": (n >= 5).values}
    D = d.n_D
    S["n_D"] = {"0": (D == 0).values, "1-2": D.between(1, 2).values, ">=3": (D >= 3).values}
    S["peptoid"] = {"yes": (d.n_peptoid > 0).values, "no": (d.n_peptoid == 0).values}
    S["unknown_monomer"] = {"yes": (d.n_unknown > 0).values, "no": (d.n_unknown == 0).values}
    S["ext_backbone"] = {"yes": (d.n_ext > 0).values, "no": (d.n_ext == 0).values}
    S["backbone_mod"] = {"yes": (d.n_backbone_mod > 0).values, "no": (d.n_backbone_mod == 0).values}
    q = d.ring_atoms_max.quantile([1 / 3, 2 / 3]).values
    S["ring_atoms"] = {"low(<=%d)" % q[0]: (d.ring_atoms_max <= q[0]).values, "mid": ((d.ring_atoms_max > q[0]) & (d.ring_atoms_max <= q[1])).values, "high(>%d)" % q[1]: (d.ring_atoms_max > q[1]).values}
    g = d.flat_size
    S["stereo_group"] = {"1": (g == 1).values, "2-7": g.between(2, 7).values, ">=8": (g >= 8).values}
    s = d.src_n
    S["source_size"] = {"<50": (s < 50).values, "50-299": s.between(50, 299).values, ">=300": (s >= 300).values}
    y = d.Year
    S["year"] = {"<=2013": (y <= 2013).values, "2014-2019": y.between(2014, 2019).values, ">=2020": (y >= 2020).values}
    return S
