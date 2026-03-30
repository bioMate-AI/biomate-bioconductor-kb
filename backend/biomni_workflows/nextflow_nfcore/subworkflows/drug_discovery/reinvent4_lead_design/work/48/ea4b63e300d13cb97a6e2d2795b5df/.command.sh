#!/bin/bash -ue
python3 << 'PYEOF'
import json, sys
from rdkit import Chem
from rdkit.Chem import Descriptors, QED
from rdkit.Chem.FilterCatalog import FilterCatalog, FilterCatalogParams

seed_smi = 'CCc1cc(Nc2ncnc3cc(OCC)c(OCC)cc23)no1'
mode = 'scaffold_decoration'

mol = Chem.MolFromSmiles(seed_smi)
if mol is None:
    print(f"ERROR: Invalid SMILES: {seed_smi}", file=sys.stderr)
    sys.exit(1)

# For scaffold decoration: ensure [*] attachment points
validated_smi = seed_smi
attachment_added = False
if mode == 'scaffold_decoration' and '[*]' not in seed_smi and '*' not in seed_smi:
    # Auto-detect likely attachment position (longest terminal chain atom)
    # Simple heuristic: annotate first terminal atom
    from rdkit.Chem import AllChem
    validated_smi = Chem.MolToSmiles(mol) + '[*]'
    attachment_added = True

# Compute properties
try:
    import sa_scorer  # optional, from RDKit contrib
    sa = sa_scorer.calculateScore(mol)
except Exception:
    sa = None

result = {
    "mock_mode": False,
    "seed_smiles": seed_smi,
    "mode": mode,
    "scoring_function": 'qed_sa',
    "validated_smiles": validated_smi,
    "seed_qed": round(QED.qed(mol), 3),
    "seed_sa_score": round(sa, 2) if sa else None,
    "seed_mw": round(Descriptors.MolWt(mol), 2),
    "attachment_points_added": attachment_added,
    "n_steps": 500,
    "batch_size": 128,
    "notes": "Validation passed"
}

with open('validated_input.json', 'w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF
