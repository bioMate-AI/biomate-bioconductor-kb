"""Step 4d data: pull ChEMBL (release ChEMBL_37, 2026-05-01; licence CC BY-SA 3.0) molecules MW 700-1400 via the public REST API,
stream-filter locally to peptide-like macrocycles (largest ring >=12 atoms AND >=3 amide bonds), drop anything whose InChIKey
(first block) matches a CycPeptMPDB peptide, keep only (chembl_id, canonical smiles). Unlabelled w.r.t. permeability: pretraining
uses only RDKit-computed descriptors as self-supervised targets. Raw pages are not stored."""
import json, time, urllib.request, pandas as pd
from rdkit import Chem, RDLogger
from rdkit.Chem import inchi
from common import *
RDLogger.DisableLog("rdApp.*")
amide = Chem.MolFromSmarts("C(=O)[NX3]")
c = pd.read_csv(CLEAN)
cpm_keys = set()
for s in c.can.unique():
    m = Chem.MolFromSmiles(s)
    try: cpm_keys.add(inchi.MolToInchiKey(m).split("-")[0])
    except Exception: pass
keep, seen, tot, off = [], 0, None, 0
while True:
    url = f"https://www.ebi.ac.uk/chembl/api/data/molecule.json?molecule_properties__full_mwt__range=700,1400&only=molecule_chembl_id,molecule_structures&limit=1000&offset={off}"
    for attempt in range(4):
        try:
            d = json.load(urllib.request.urlopen(url, timeout=120)); break
        except Exception as e:
            time.sleep(5)
    else: raise SystemExit("api failure at offset %d" % off)
    tot = d["page_meta"]["total_count"]
    for mol in d["molecules"]:
        st = mol.get("molecule_structures") or {}
        smi = st.get("canonical_smiles")
        if not smi: continue
        m = Chem.MolFromSmiles(smi)
        if m is None: continue
        rings = m.GetRingInfo().AtomRings()
        if max((len(r) for r in rings), default=0) < 12: continue
        if len(m.GetSubstructMatches(amide)) < 3: continue
        key = (st.get("standard_inchi_key") or "").split("-")[0]
        if key in cpm_keys: seen += 1; continue
        keep.append((mol["molecule_chembl_id"], Chem.MolToSmiles(m)))
    off += 1000
    print(off, tot, len(keep), flush=True)
    if off >= tot: break
pd.DataFrame(keep, columns=["chembl_id", "smiles"]).to_csv(os.path.join(HERE, "data/chembl_macrocycle_pool.csv"), index=False)
json.dump({"chembl_release": "ChEMBL_37 (2026-05-01)", "licence": "CC BY-SA 3.0", "query": "molecule_properties__full_mwt__range=700,1400", "api_total": tot,
           "kept_macrocycle_peptidelike": len(keep), "removed_overlap_with_cycpeptmpdb_inchikey": seen}, open(os.path.join(HERE, "results/chembl_pool_report.json"), "w"), indent=1)
