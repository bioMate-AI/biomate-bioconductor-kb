#!/bin/bash -ue
if [ "false" = "true" ]; then
        python3 << 'EOF'
import json
import csv
import random
from datetime import datetime

random.seed(42)

meta_id     = "test_actives"
ref_smiles  = "CC(=O)Nc1ccc(O)cc1"

# ---------------------------------------------------------------------------
# Mock: synthetic validated SMILES dataset (acetaminophen analogues)
# Includes reference compound and 9 structural analogues for MMP analysis
# ---------------------------------------------------------------------------
compounds = [
    # (compound_id, smiles, mw, valid)
    ("REF_001",  "CC(=O)Nc1ccc(O)cc1",             151.16, True),   # acetaminophen (reference)
    ("ANA_002",  "CC(=O)Nc1ccc(OC)cc1",            165.19, True),   # 4-methoxyacetanilide
    ("ANA_003",  "CC(=O)Nc1ccc(F)cc1",             153.15, True),   # 4-fluoroacetanilide
    ("ANA_004",  "CC(=O)Nc1ccc(Cl)cc1",            169.61, True),   # 4-chloroacetanilide
    ("ANA_005",  "CCC(=O)Nc1ccc(O)cc1",            165.19, True),   # propionamide analogue
    ("ANA_006",  "CC(=O)Nc1ccc(O)c(F)c1",          169.15, True),   # 2-fluoro variant
    ("ANA_007",  "CC(=O)Nc1ccc(O)c(C)c1",          165.19, True),   # 2-methyl variant
    ("ANA_008",  "CC(=O)Nc1cc(O)ccc1",             151.16, True),   # meta-OH regioisomer
    ("ANA_009",  "O=C(Nc1ccc(O)cc1)c1ccccc1",      213.23, True),   # benzamide variant
    ("ANA_010",  "CC(=O)Nc1ccc(O)cc1C",            165.19, True),   # 2-methyl-4-hydroxy
]

# Write validated CSV
with open(f"{meta_id}_validated.csv", "w", newline="") as csvf:
    writer = csv.DictWriter(csvf, fieldnames=[
        "compound_id", "smiles", "mw_da", "valid",
        "canonical_smiles", "inchi_key"
    ])
    writer.writeheader()
    for cid, smi, mw, valid in compounds:
        writer.writerow({
            "compound_id":       cid,
            "smiles":            smi,
            "mw_da":             mw,
            "valid":             str(valid),
            "canonical_smiles":  smi,    # mock: same as input (RDKit would canonicalise)
            "inchi_key":         f"MOCK_{cid}_INCHIKEY",
        })

valid_count   = sum(1 for _, _, _, v in compounds if v)
invalid_count = len(compounds) - valid_count

# Write validation report
report = {
    "meta_id":          meta_id,
    "input_file":       "test_actives.smi",
    "reference_smiles": ref_smiles,
    "total_compounds":  len(compounds),
    "valid_count":      valid_count,
    "invalid_count":    invalid_count,
    "validation_rules": [
        "RDKit SMILES parse",
        "Molecular weight 50–1000 Da",
        "Heavy atom count >= 5",
        "No disconnected fragments (salts stripped)",
    ],
    "timestamp":   datetime.utcnow().isoformat() + "Z",
    "mock_mode":   True,
}
with open(f"{meta_id}_validation_report.json", "w") as jf:
    json.dump(report, jf, indent=2)

print(f"Validation mock complete: {valid_count}/{len(compounds)} compounds passed")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: RDKit SMILES validation
        # ---------------------------------------------------------------------------
        python3 << 'PYEOF'
import json
import csv
import sys
from datetime import datetime

try:
    from rdkit import Chem
    from rdkit.Chem import Descriptors, rdMolDescriptors
    from rdkit.Chem.inchi import MolToInchi, InchiToInchiKey
    RDKIT_OK = True
except ImportError:
    RDKIT_OK = False
    print("WARNING: RDKit not found; falling back to syntax-only check.", file=sys.stderr)

meta_id    = "test_actives"
input_file = "test_actives.smi"
compounds  = []
errors     = []

with open(input_file) as fh:
    for lineno, line in enumerate(fh, 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 2:
            errors.append({"line": lineno, "reason": "missing compound_id"})
            continue
        smi, cid = parts[0], parts[1]

        if RDKIT_OK:
            mol = Chem.MolFromSmiles(smi)
            if mol is None:
                errors.append({"line": lineno, "compound_id": cid, "reason": "invalid SMILES"})
                continue
            # Strip salts: keep largest fragment
            frags = Chem.GetMolFrags(mol, asMols=True)
            mol   = max(frags, key=lambda m: m.GetNumHeavyAtoms())
            can   = Chem.MolToSmiles(mol)
            mw    = round(Descriptors.MolWt(mol), 3)
            ha    = mol.GetNumHeavyAtoms()
            if mw < 50 or mw > 1000 or ha < 5:
                errors.append({"line": lineno, "compound_id": cid,
                                "reason": f"out of range: mw={mw} ha={ha}"})
                continue
            try:
                inchi    = MolToInchi(mol) or ""
                inchi_key = InchiToInchiKey(inchi) if inchi else ""
            except Exception:
                inchi_key = ""
        else:
            can, mw, inchi_key = smi, 0.0, ""

        compounds.append({
            "compound_id":      cid,
            "smiles":           smi,
            "mw_da":            mw,
            "valid":            "True",
            "canonical_smiles": can,
            "inchi_key":        inchi_key,
        })

with open(f"{meta_id}_validated.csv", "w", newline="") as csvf:
    writer = csv.DictWriter(csvf, fieldnames=[
        "compound_id", "smiles", "mw_da", "valid", "canonical_smiles", "inchi_key"
    ])
    writer.writeheader()
    writer.writerows(compounds)

report = {
    "meta_id":         meta_id,
    "input_file":      input_file,
    "total_lines":     lineno if compounds or errors else 0,
    "valid_count":     len(compounds),
    "invalid_count":   len(errors),
    "errors":          errors[:20],   # cap at 20 for report
    "timestamp":       datetime.utcnow().isoformat() + "Z",
    "mock_mode":       False,
}
with open(f"{meta_id}_validation_report.json", "w") as jf:
    json.dump(report, jf, indent=2)

print(f"Validation complete: {len(compounds)} valid, {len(errors)} invalid")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "SCAFFOLD_HOPPING:SCAFFOLD_INPUT_VALIDATION":
        rdkit: $(python3 -c "from rdkit import __version__; print(__version__)" 2>/dev/null || echo "N/A")
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "false"
    END_VERSIONS
