"""Benchmark-domain strata (Part A9): topology (SMILES-only rule T2), N-methyl count, size and stereo-group size for the frozen retro_recovery compounds and items (read-only).
Output data/benchmark_strata.csv and data/benchmark_strata_summary.json."""
import sys, os, json
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import annotate as A, common as C
from rdkit import Chem, RDLogger
RDLogger.DisableLog("rdApp.*")
R = os.path.abspath(os.path.join(C.HERE, "..", "..", "multitarget", "integrin_chembl", "retro_recovery", "data"))
comp = pd.read_csv(os.path.join(R, "compounds.csv.gz")); folds = pd.read_csv(os.path.join(R, "folds_v1.csv")); targets = pd.read_csv(os.path.join(R, "targets.csv"))
topo, nme, hv = [], [], []
for s in comp.iso_smiles:
    m = Chem.MolFromSmiles(s)
    if m is None: topo.append("parse_fail"); nme.append(np.nan); continue
    topo.append(A.rdkit_topology(m)); nme.append(len({mt[2] for mt in m.GetSubstructMatches(A.NME_AMIDE)}))
comp["topology_T2"] = topo; comp["n_nme"] = nme
comp["flat_size"] = comp.groupby("flat_key")["compound_id"].transform("size")
fam_fold = dict(zip(folds.family, folds.fold)); tf = dict(zip(targets.target_key, targets.family.map(fam_fold))); tfam = dict(zip(targets.target_key, targets.family))
out = []
for name in ("items_I", "items_M2"):
    it = pd.read_csv(os.path.join(R, name + ".csv.gz")).merge(comp, on="compound_id"); it["fold"] = it.target_key.map(tf)
    pos = it[it.label == 1]
    for col, bins in (("topology_T2", None), ("stratum", None), ("n_nme", [-1, 0, 2, 4, 100]), ("flat_size", [0, 1, 7, 10000])):
        g = pos.copy()
        if bins: g[col] = pd.cut(g[col], bins).astype(str)
        for lv, sub in g.groupby(col):
            out.append(dict(items=name, stratifier=col, level=str(lv), n_positive_items=int(len(sub)), n_positive_compounds=int(sub.compound_id.nunique()), n_targets=int(sub.target_key.nunique()), n_families=int(sub.target_key.map(tfam).nunique()), n_folds=int(sub.target_key.map(tf).nunique()),
                            positives_in_folds=json.dumps({int(k): int(v) for k, v in sub.fold.value_counts().items()}), thin=bool(sub.target_key.nunique() < 10 or len(sub) < 30 or sub.target_key.map(tfam).nunique() < 3)))
O = pd.DataFrame(out); O.to_csv(os.path.join(C.HERE, "data", "benchmark_strata.csv"), index=False)
summ = dict(n_compounds=int(len(comp)), topology_T2=comp.topology_T2.value_counts().to_dict(), stratum=comp.stratum.value_counts().to_dict(), n_nme_mean=float(comp.n_nme.mean()), flat_size_gt1_frac=float((comp.flat_size > 1).mean()))
json.dump(summ, open(os.path.join(C.HERE, "data", "benchmark_strata_summary.json"), "w"), indent=1); print(json.dumps(summ, indent=1))
pd.set_option("display.width", 250); pd.set_option("display.max_rows", 100); print(O[O["items"] == "items_I"][["stratifier", "level", "n_positive_items", "n_positive_compounds", "n_targets", "n_families", "n_folds", "thin"]].to_string(index=False))
