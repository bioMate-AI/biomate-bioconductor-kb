"""Compound-level no-target proxies (PREREG A7) for every compound that can appear in any analysis or decoy pool. Output data/proxies.csv.gz.
heavy, charge, n_arom, tpsa, logp, hbd, hba, rotb, fsp3, ring (largest ring), n_rings, n_frac / o_frac (share of heavy atoms), has_s, has_halogen, ncaa_frac, n_alpha,
in_corpus (exact isomeric SMILES in the atom-LM pretraining corpus = 'corpus frequency' proxy), in_cycpeptmpdb, typicality (atom-LM mean per-token log-likelihood, WS1 scorer)."""
import os, gzip, pickle, numpy as np, pandas as pd
from rdkit import Chem, RDLogger
RDLogger.DisableLog("rdApp.*")
import chem
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; SP = "/private/tmp/claude-501/-Users-kky-biomate-review/195b4da4-5c44-48ae-a4e1-005d493239c0/scratchpad"
C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); DESC = pickle.load(open(f"{SP}/desc.pkl", "rb"))
P = pd.read_csv(f"{DATA}/pair_labels.csv.gz"); need = sorted(set(P.compound_id))
corp = set(l.split()[0] for l in gzip.open(f"{SP}/pretrain_corpus.smi.gz", "rt") if l.strip())
d = pd.read_csv(f"{SP}/CycPeptMPDB_Peptide_All.csv", low_memory=False); cp = set()
for s in d.SMILES.dropna().unique():
    m = chem.parse(s)
    if m is not None: cp.add(chem.keys(m)[0])
typ = pd.read_csv(f"{DATA}/typicality_atomlm.csv.gz").set_index("compound_id").score
rows = {}
for c in need:
    m = chem.parse(C.loc[c, "iso_smiles"]); dsc = DESC.loc[c]; hv = max(m.GetNumHeavyAtoms(), 1)
    syms = [a.GetSymbol() for a in m.GetAtoms()]
    rows[c] = dict(heavy=dsc.heavy, charge=dsc.charge, n_arom=dsc.n_arom, tpsa=dsc.tpsa, logp=dsc.logp, hbd=dsc.hbd, hba=dsc.hba, rotb=dsc.rotb, fsp3=dsc.fsp3, ring=dsc.ring, n_rings=m.GetRingInfo().NumRings(),
                   n_frac=syms.count("N") / hv, o_frac=syms.count("O") / hv, has_s=float("S" in syms), has_halogen=float(any(x in ("F", "Cl", "Br", "I") for x in syms)),
                   ncaa_frac=(dsc.n_d + dsc.n_nsub) / max(dsc.n_alpha, 1), n_alpha=dsc.n_alpha, in_corpus=float(C.loc[c, "iso_smiles"] in corp), in_cycpeptmpdb=float(C.loc[c, "iso_smiles"] in cp),
                   typicality=typ.get(c, np.nan))
Pr = pd.DataFrame.from_dict(rows, orient="index"); Pr.index.name = "compound_id"
Pr.to_csv(f"{DATA}/proxies.csv.gz", compression=dict(method="gzip", mtime=0)); print(Pr.shape, "typicality missing", int(Pr.typicality.isna().sum()), "in_corpus mean", round(Pr.in_corpus.mean(), 3))
