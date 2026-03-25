#!/bin/bash -ue
if [ "false" = "true" ]; then
        python3 << 'EOF'
import json
from datetime import datetime

# ---------------------------------------------------------------------------
# Mock pharmacophore model derived from aspirin-like reference actives.
# Hardcoded consensus features without importing RDKit.
# Reference set (3 compounds):
#   CC(=O)Oc1ccccc1C(=O)O   (aspirin)
#   CC(=O)Oc1ccccc1C(=O)N   (aspirin amide analogue)
#   OC(=O)c1ccccc1O          (salicylic acid)
# ---------------------------------------------------------------------------

ref_smiles = [
    "CC(=O)Oc1ccccc1C(=O)O",
    "CC(=O)Oc1ccccc1C(=O)N",
    "OC(=O)c1ccccc1O",
]

# Consensus features observed across the reference set
features = [
    {
        "type":                 "Donor",
        "label":                "D",
        "description":          "Hydroxyl or NH hydrogen-bond donor",
        "count_in_references":  3,
        "fraction":             1.0,
        "smarts":               "[OX2H,NX3H2,NX3H1]",
    },
    {
        "type":                 "Acceptor",
        "label":                "A1",
        "description":          "Carbonyl C=O acceptor (ester/acid/amide)",
        "count_in_references":  3,
        "fraction":             1.0,
        "smarts":               "[CX3](=[OX1])",
    },
    {
        "type":                 "Acceptor",
        "label":                "A2",
        "description":          "Ester or hydroxyl oxygen acceptor",
        "count_in_references":  3,
        "fraction":             1.0,
        "smarts":               "[OX2][CX3](=[OX1])",
    },
    {
        "type":                 "Aromatic",
        "label":                "Ar",
        "description":          "Aromatic benzene ring",
        "count_in_references":  3,
        "fraction":             1.0,
        "smarts":               "c1ccccc1",
    },
]

model = {
    "source":           "mock",
    "n_references":     len(ref_smiles),
    "reference_smiles": ref_smiles,
    "n_features":       len(features),
    "features":         features,
    "timestamp":        datetime.utcnow().isoformat() + "Z",
    "mock_mode":        True,
}

with open("pharmacophore_model.json", "w") as f:
    json.dump(model, f, indent=2)

print(f"Pharmacophore model generated (mock): {len(features)} features from {len(ref_smiles)} references")
for ft in features:
    print(f"  [{ft['label']}] {ft['type']}: {ft['description']}  (frac={ft['fraction']})")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: derive pharmacophore model from reference actives using RDKit
        # ---------------------------------------------------------------------------
        python3 << 'EOF'
import json
import sys
from datetime import datetime
from collections import defaultdict

import os
from rdkit import Chem, RDConfig
from rdkit.Chem import MolFromSmiles
from rdkit.Chem.rdMolDescriptors import CalcNumHBD, CalcNumHBA, CalcNumAromaticRings
from rdkit.Chem import ChemicalFeatures

# Load the RDKit built-in BaseFeatures factory (supports GetFeaturesForMol)
_fdef_candidates = [
    os.path.join(RDConfig.RDDataDir, 'BaseFeatures.fdef'),
    '/usr/share/rdkit/Data/BaseFeatures.fdef',
    '/usr/local/share/rdkit/Data/BaseFeatures.fdef',
]
factory = None
for _fdef in _fdef_candidates:
    if os.path.exists(_fdef):
        factory = ChemicalFeatures.BuildFeatureFactory(_fdef)
        break
if factory is None:
    raise RuntimeError("Could not locate BaseFeatures.fdef in RDKit data directory")

ref_smiles = []
with open("abl1_reference_actives.smi") as f:
    for line in f:
        smi = line.strip().split()[0]
        if smi:
            ref_smiles.append(smi)

if not ref_smiles:
    print("ERROR: no SMILES found in reference file", file=sys.stderr)
    sys.exit(1)

# Count feature types across reference actives
feature_counts = defaultdict(int)
n_valid = 0

for smi in ref_smiles:
    mol = MolFromSmiles(smi)
    if mol is None:
        print(f"  WARNING: could not parse SMILES: {smi}", file=sys.stderr)
        continue
    n_valid += 1
    feats = factory.GetFeaturesForMol(mol)
    seen_types = set()
    for feat in feats:
        ft = feat.GetFamily()
        if ft not in seen_types:
            feature_counts[ft] += 1
            seen_types.add(ft)

if n_valid == 0:
    print("ERROR: no valid molecules in reference set", file=sys.stderr)
    sys.exit(1)

# Build consensus feature list (include all feature types seen in ≥50% of actives)
SMARTS_MAP = {
    "Donor":        "[OX2H,NX3H2,NX3H1]",
    "Acceptor":     "[OX1,NX3;!$(NC=O)]",
    "Aromatic":     "c1ccccc1",
    "Hydrophobe":   "[c,s,S&H0&v2,Br,I,$(C(F)(F)F),$(CC(F)(F)F)]",
    "PosIonizable": "[+!H0,$(N-[CX3]=[NH]),$(NC(=N)N),$(n1ccnc1)]",
    "NegIonizable": "[$([CX3](=O)[OX1H0-,OX2H1]),$([SX4](=[OX1])(=[OX1])([OX2H,OX1H0-])[OX2H,OX1H0-])]",
}

features = []
for label_idx, (ftype, count) in enumerate(sorted(feature_counts.items(), key=lambda x: -x[1])):
    fraction = round(count / n_valid, 3)
    features.append({
        "type":                 ftype,
        "label":                f"{ftype[0]}{label_idx}",
        "description":          ftype,
        "count_in_references":  count,
        "fraction":             fraction,
        "smarts":               SMARTS_MAP.get(ftype, ""),
    })

model = {
    "source":           "rdkit",
    "n_references":     n_valid,
    "reference_smiles": ref_smiles,
    "n_features":       len(features),
    "features":         features,
    "generate_3d":      bool("false" == "true"),
    "timestamp":        datetime.utcnow().isoformat() + "Z",
    "mock_mode":        False,
}

with open("pharmacophore_model.json", "w") as f:
    json.dump(model, f, indent=2)

print(f"Pharmacophore model (RDKit): {len(features)} features from {n_valid} valid references")
for ft in features:
    print(f"  [{ft['label']}] {ft['type']}: fraction={ft['fraction']}")
EOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "PHARMACOPHORE_FILTERING:PHARMACOPHORE_GENERATE":
        rdkit: $(python3 -c "import rdkit; print(rdkit.__version__)" 2>/dev/null || echo "mock")
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "false"
    END_VERSIONS
