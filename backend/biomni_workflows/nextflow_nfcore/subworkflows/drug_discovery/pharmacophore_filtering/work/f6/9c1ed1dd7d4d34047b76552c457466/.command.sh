#!/bin/bash -ue
if [ "true" = "true" ]; then
        python3 << 'EOF'
import json
import random
from datetime import datetime

random.seed(42)

model = json.load(open("pharmacophore_model.json"))
n_model_features = model["n_features"]

# ---------------------------------------------------------------------------
# Mock compound library: 10 aspirin-inspired SMILES with simulated feature
# counts (seeded random — reproducible).
# ---------------------------------------------------------------------------
library = [
    ("CPND001", "CC(=O)Oc1ccccc1C(=O)O"),     # aspirin
    ("CPND002", "CC(=O)Oc1ccccc1C(=O)N"),     # aspirin amide
    ("CPND003", "OC(=O)c1ccccc1O"),            # salicylic acid
    ("CPND004", "CC(=O)Nc1ccc(O)cc1"),         # paracetamol
    ("CPND005", "c1ccc(cc1)C(=O)O"),           # benzoic acid
    ("CPND006", "CCCC"),                       # butane (no features)
    ("CPND007", "CC(=O)Oc1cccc(c1)C(=O)O"),   # 3-acetoxybenzoic acid
    ("CPND008", "c1ccc2c(c1)cccc2"),           # naphthalene
    ("CPND009", "CC(=O)Oc1ccc(cc1)C(=O)O"),   # 4-acetoxybenzoic acid
    ("CPND010", "NC(=O)c1ccccc1N"),            # 2-aminobenzamide
]

# Assign seeded random feature match counts in range [0, n_model_features]
results = []
for cid, smi in library:
    n_matched = random.randint(0, n_model_features)
    # Choose which feature types are matched (random subset of model features)
    all_feature_types = [ft["type"] for ft in model["features"]]
    matched_types = random.sample(all_feature_types, min(n_matched, len(all_feature_types)))
    passes = n_matched >= int("3")
    results.append({
        "compound_id":         cid,
        "smiles":              smi,
        "features_matched":    n_matched,
        "feature_types":       matched_types,
        "pass":                passes,
    })

# Write TSV report
with open("match_report.tsv", "w") as f:
    f.write("compound_id\tsmiles\tfeatures_matched\tfeature_types_matched\tpass\n")
    for r in results:
        f.write(
            f"{r['compound_id']}\t{r['smiles']}\t{r['features_matched']}\t"
            f"{','.join(r['feature_types'])}\t{'PASS' if r['pass'] else 'FAIL'}\n"
        )

# Write full scores JSON
scores = {
    "pharmacophore_model": "pharmacophore_model.json",
    "library":             "mock_library.smi",
    "n_screened":          len(results),
    "n_passed":            sum(1 for r in results if r["pass"]),
    "min_features":        int("3"),
    "results":             results,
    "timestamp":           datetime.utcnow().isoformat() + "Z",
    "mock_mode":           True,
}
with open("screened_scores.json", "w") as f:
    json.dump(scores, f, indent=2)

n_pass = scores["n_passed"]
n_total = scores["n_screened"]
print(f"Pharmacophore screening (mock): {n_pass}/{n_total} compounds passed (min_features={int('3')})")
for r in results:
    tag = "PASS" if r["pass"] else "FAIL"
    print(f"  [{tag}] {r['compound_id']}  matched={r['features_matched']}  types={r['feature_types']}")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: screen library with RDKit SMARTS-based pharmacophore matching
        # ---------------------------------------------------------------------------
        python3 << 'EOF'
import json
import sys
from datetime import datetime

from rdkit import Chem
from rdkit.Chem import MolFromSmiles, MolFromSmarts, SDMolSupplier

model = json.load(open("pharmacophore_model.json"))
features = model["features"]

# Build compiled SMARTS patterns (skip features without SMARTS)
compiled = []
for ft in features:
    smarts = ft.get("smarts", "")
    if smarts:
        pat = MolFromSmarts(smarts)
        if pat is not None:
            compiled.append((ft["type"], ft["label"], pat))

# Determine input format (SDF or SMILES)
lib_path = "mock_library.smi"
library_mols = []

if lib_path.endswith(".sdf"):
    suppl = SDMolSupplier(lib_path, removeHs=True)
    for i, mol in enumerate(suppl):
        if mol is not None:
            name = mol.GetProp("_Name") if mol.HasProp("_Name") else f"MOL{i+1:04d}"
            smi  = Chem.MolToSmiles(mol)
            library_mols.append((name, smi, mol))
else:
    with open(lib_path) as f:
        for i, line in enumerate(f, 1):
            parts = line.strip().split()
            if not parts:
                continue
            smi = parts[0]
            cid = parts[1] if len(parts) > 1 else f"CPND{i:04d}"
            mol = MolFromSmiles(smi)
            if mol is not None:
                library_mols.append((cid, smi, mol))

if not library_mols:
    print("ERROR: no valid molecules loaded from library", file=sys.stderr)
    sys.exit(1)

min_features = int("3")

results = []
for cid, smi, mol in library_mols:
    matched_types = []
    seen_types = set()
    for ftype, flabel, pat in compiled:
        if ftype not in seen_types and mol.HasSubstructMatch(pat):
            matched_types.append(ftype)
            seen_types.add(ftype)

    n_matched = len(matched_types)
    passes = n_matched >= min_features
    results.append({
        "compound_id":      cid,
        "smiles":           smi,
        "features_matched": n_matched,
        "feature_types":    matched_types,
        "pass":             passes,
    })

with open("match_report.tsv", "w") as f:
    f.write("compound_id\tsmiles\tfeatures_matched\tfeature_types_matched\tpass\n")
    for r in results:
        f.write(
            f"{r['compound_id']}\t{r['smiles']}\t{r['features_matched']}\t"
            f"{','.join(r['feature_types'])}\t{'PASS' if r['pass'] else 'FAIL'}\n"
        )

scores = {
    "pharmacophore_model": "pharmacophore_model.json",
    "library":             "mock_library.smi",
    "n_screened":          len(results),
    "n_passed":            sum(1 for r in results if r["pass"]),
    "min_features":        min_features,
    "results":             results,
    "timestamp":           datetime.utcnow().isoformat() + "Z",
    "mock_mode":           False,
}
with open("screened_scores.json", "w") as f:
    json.dump(scores, f, indent=2)

n_pass = scores["n_passed"]
n_total = scores["n_screened"]
print(f"Pharmacophore screening (RDKit): {n_pass}/{n_total} passed (min_features={min_features})")
for r in results:
    tag = "PASS" if r["pass"] else "FAIL"
    print(f"  [{tag}] {r['compound_id']}  matched={r['features_matched']}")
EOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "PHARMACOPHORE_FILTERING:PHARMACOPHORE_SCREEN":
        rdkit: $(python3 -c "import rdkit; print(rdkit.__version__)" 2>/dev/null || echo "mock")
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "true"
        min_features: "3"
    END_VERSIONS
