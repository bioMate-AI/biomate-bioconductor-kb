#!/bin/bash -ue
python3 << 'PYEOF'
import json, csv
from rdkit import Chem, DataStructs
from rdkit.Chem import Descriptors, QED, AllChem, rdMolDescriptors
from rdkit.Chem.FilterCatalog import FilterCatalog, FilterCatalogParams
from rdkit.Chem.Scaffolds import MurckoScaffold

# Load validated input
with open('validated_input.json') as f:
    cfg = json.load(f)
seed_smi = cfg['validated_smiles']
seed_mol = Chem.MolFromSmiles(seed_smi)
seed_fp = AllChem.GetMorganFingerprintAsBitVect(seed_mol, 2, 2048) if seed_mol else None

# PAINS filter
pains_catalog = None
if True:
    params = FilterCatalogParams()
    params.AddCatalog(FilterCatalogParams.FilterCatalogs.PAINS)
    pains_catalog = FilterCatalog(params)

# Read raw molecules
rows = []
with open('raw_molecules.csv') as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows.append(row)

# Try to import SA scorer
try:
    from rdkit.Chem import RDConfig
    import os, sys
    sa_path = os.path.join(RDConfig.RDContribDir, 'SA_Score')
    sys.path.append(sa_path)
    import sascorer
    SA_AVAILABLE = True
except Exception:
    SA_AVAILABLE = False

stats = {"input_molecules": len(rows)}
accepted = []
seen_smiles = set()

for row in rows:
    smi = row['smiles'].strip()
    mol = Chem.MolFromSmiles(smi)
    if mol is None: continue

    # Dedup
    can_smi = Chem.MolToSmiles(mol)
    if can_smi in seen_smiles: continue
    seen_smiles.add(can_smi)

    # QED
    qed_val = QED.qed(mol)
    if qed_val < 0.4: continue

    # SA score
    sa_val = sascorer.calculateScore(mol) if SA_AVAILABLE else 3.5
    if sa_val > 5.0: continue

    # MW
    mw = Descriptors.MolWt(mol)
    if mw > 500: continue

    # Lipinski
    hbd = rdMolDescriptors.CalcNumHBD(mol)
    hba = rdMolDescriptors.CalcNumHBA(mol)
    logp = Descriptors.MolLogP(mol)
    if hbd > 5 or hba > 10 or logp > 5 or mw > 500: continue

    # PAINS
    if pains_catalog and pains_catalog.HasMatch(mol): continue

    # Novelty vs seed
    if seed_fp is not None:
        fp = AllChem.GetMorganFingerprintAsBitVect(mol, 2, 2048)
        tanimoto = DataStructs.TanimotoSimilarity(seed_fp, fp)
        if tanimoto > (1 - 0.4): continue

    # Murcko scaffold for diversity tracking
    try:
        scaffold = Chem.MolToSmiles(MurckoScaffold.GetScaffoldForMol(mol))
    except Exception:
        scaffold = ''

    accepted.append({
        'smiles': can_smi,
        'score': float(row.get('score', 0)),
        'qed': round(qed_val, 3),
        'sa_score': round(sa_val, 2),
        'mw': round(mw, 1),
        'scaffold': scaffold,
    })

# Sort by score, keep top N
accepted = sorted(accepted, key=lambda r: -r['score'])[: 50]
stats["final_selected"] = len(accepted)

# Write CSV
with open('top_compounds.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['rank','smiles','score','qed','sa_score','mw','scaffold'])
    for i, r in enumerate(accepted, 1):
        writer.writerow([i, r['smiles'], r['score'], r['qed'], r['sa_score'], r['mw'], r['scaffold']])

# Write SDF with 3D conformers (ETKDG)
writer_sdf = Chem.SDWriter('top_compounds.sdf')
for i, r in enumerate(accepted, 1):
    mol = Chem.MolFromSmiles(r['smiles'])
    mol = Chem.AddHs(mol)
    try:
        AllChem.EmbedMolecule(mol, AllChem.ETKDGv3())
        AllChem.MMFFOptimizeMolecule(mol)
        mol = Chem.RemoveHs(mol)
    except Exception:
        mol = Chem.RemoveHs(mol)
    mol.SetProp('_Name', f'Compound_{i}')
    for k, v in r.items():
        mol.SetProp(k, str(v))
    mol.SetProp('Rank', str(i))
    writer_sdf.write(mol)
writer_sdf.close()

with open('filter_stats.json', 'w') as f:
    json.dump(stats, f, indent=2)
print(json.dumps(stats, indent=2))
PYEOF
