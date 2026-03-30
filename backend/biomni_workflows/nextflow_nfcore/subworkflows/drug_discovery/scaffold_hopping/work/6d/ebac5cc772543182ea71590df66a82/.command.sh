#!/bin/bash -ue
if [ "false" = "true" ]; then
        python3 << 'EOF'
import json
import csv
import random
from datetime import datetime

random.seed(42)

meta_id = "test_actives"

# ---------------------------------------------------------------------------
# Mock RECAP output: 8 fragments from acetaminophen (CC(=O)Nc1ccc(O)cc1)
#
# RECAP bond types (Lewell et al. 1998):
#   amide, ester, amine, urea, ether, olefin, quaternary N, aromatic N-aliphatic C,
#   lactam N-aliphatic C, aromatic C-aromatic C
#
# Scaffold = core retained after fragmentation
# R-groups = leaving fragments at attachment points (marked with [*])
# ---------------------------------------------------------------------------
fragments = [
    {
        "compound_id":        "REF_001",
        "parent_smiles":      "CC(=O)Nc1ccc(O)cc1",
        "fragment_id":        "FRAG_001_amide_scaffold",
        "scaffold_smiles":    "[*]Nc1ccc(O)cc1",
        "rgroup_smiles":      "[*]C(=O)C",
        "bond_type":          "amide",
        "attachment_points":  1,
        "scaffold_mw":        109.13,
        "rgroup_mw":          43.04,
        "scaffold_heavy_atoms": 8,
        "fragment_frequency": 6,
    },
    {
        "compound_id":        "REF_001",
        "parent_smiles":      "CC(=O)Nc1ccc(O)cc1",
        "fragment_id":        "FRAG_001_phenol_core",
        "scaffold_smiles":    "Oc1ccc([*])cc1",
        "rgroup_smiles":      "[*]NC(=O)C",
        "bond_type":          "amide",
        "attachment_points":  1,
        "scaffold_mw":        94.11,
        "rgroup_mw":          57.07,
        "scaffold_heavy_atoms": 7,
        "fragment_frequency": 9,
    },
    {
        "compound_id":        "ANA_002",
        "parent_smiles":      "CC(=O)Nc1ccc(OC)cc1",
        "fragment_id":        "FRAG_002_methoxyphenyl",
        "scaffold_smiles":    "COc1ccc([*])cc1",
        "rgroup_smiles":      "[*]NC(=O)C",
        "bond_type":          "amide",
        "attachment_points":  1,
        "scaffold_mw":        108.14,
        "rgroup_mw":          57.07,
        "scaffold_heavy_atoms": 8,
        "fragment_frequency": 7,
    },
    {
        "compound_id":        "ANA_003",
        "parent_smiles":      "CC(=O)Nc1ccc(F)cc1",
        "fragment_id":        "FRAG_003_fluorophenyl",
        "scaffold_smiles":    "Fc1ccc([*])cc1",
        "rgroup_smiles":      "[*]NC(=O)C",
        "bond_type":          "amide",
        "attachment_points":  1,
        "scaffold_mw":        96.10,
        "rgroup_mw":          57.07,
        "scaffold_heavy_atoms": 7,
        "fragment_frequency": 5,
    },
    {
        "compound_id":        "ANA_005",
        "parent_smiles":      "CCC(=O)Nc1ccc(O)cc1",
        "fragment_id":        "FRAG_005_propanoyl",
        "scaffold_smiles":    "[*]Nc1ccc(O)cc1",
        "rgroup_smiles":      "[*]C(=O)CC",
        "bond_type":          "amide",
        "attachment_points":  1,
        "scaffold_mw":        109.13,
        "rgroup_mw":          57.07,
        "scaffold_heavy_atoms": 8,
        "fragment_frequency": 3,
    },
    {
        "compound_id":        "ANA_009",
        "parent_smiles":      "O=C(Nc1ccc(O)cc1)c1ccccc1",
        "fragment_id":        "FRAG_009_benzoyl",
        "scaffold_smiles":    "[*]Nc1ccc(O)cc1",
        "rgroup_smiles":      "[*]C(=O)c1ccccc1",
        "bond_type":          "amide",
        "attachment_points":  1,
        "scaffold_mw":        109.13,
        "rgroup_mw":          105.11,
        "scaffold_heavy_atoms": 8,
        "fragment_frequency": 4,
    },
    {
        "compound_id":        "ANA_009",
        "parent_smiles":      "O=C(Nc1ccc(O)cc1)c1ccccc1",
        "fragment_id":        "FRAG_009_phenyl_rgroup",
        "scaffold_smiles":    "O=C([*])c1ccccc1",
        "rgroup_smiles":      "[*]Nc1ccc(O)cc1",
        "bond_type":          "amide",
        "attachment_points":  1,
        "scaffold_mw":        105.11,
        "rgroup_mw":          109.13,
        "scaffold_heavy_atoms": 8,
        "fragment_frequency": 4,
    },
    {
        "compound_id":        "ANA_010",
        "parent_smiles":      "CC(=O)Nc1ccc(O)cc1C",
        "fragment_id":        "FRAG_010_methylphenol",
        "scaffold_smiles":    "Cc1cc([*])ccc1O",
        "rgroup_smiles":      "[*]NC(=O)C",
        "bond_type":          "amide",
        "attachment_points":  1,
        "scaffold_mw":        108.14,
        "rgroup_mw":          57.07,
        "scaffold_heavy_atoms": 8,
        "fragment_frequency": 2,
    },
]

with open(f"{meta_id}_recap_fragments.csv", "w", newline="") as csvf:
    if fragments:
        writer = csv.DictWriter(csvf, fieldnames=list(fragments[0].keys()))
        writer.writeheader()
        writer.writerows(fragments)

# Scaffold frequency table (unique scaffolds across all compounds)
scaffold_freq = {}
for frag in fragments:
    sc = frag["scaffold_smiles"]
    scaffold_freq[sc] = scaffold_freq.get(sc, 0) + frag["fragment_frequency"]

summary = {
    "meta_id":               meta_id,
    "input_file":            "test_actives_validated.csv",
    "total_compounds_processed": 10,
    "total_fragments":       len(fragments),
    "unique_scaffolds":      len(set(f["scaffold_smiles"] for f in fragments)),
    "bond_type_counts": {
        "amide":  len(fragments),
    },
    "top_scaffolds_by_frequency": sorted(
        [{"scaffold": sc, "frequency": freq}
         for sc, freq in scaffold_freq.items()],
        key=lambda x: -x["frequency"]
    )[:5],
    "tool":      "RDKit RECAP",
    "timestamp": datetime.utcnow().isoformat() + "Z",
    "mock_mode": True,
}

with open(f"{meta_id}_recap_summary.json", "w") as jf:
    json.dump(summary, jf, indent=2)

print(f"RECAP mock complete: {len(fragments)} fragments from 10 compounds")
print(f"  Unique scaffolds: {summary['unique_scaffolds']}")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: RDKit RECAP decomposition
        # ---------------------------------------------------------------------------
        python3 << 'PYEOF'
import json
import csv
import sys
from datetime import datetime

try:
    from rdkit import Chem
    from rdkit.Chem import BRICS, Descriptors
except ImportError:
    print("ERROR: RDKit is required for live BRICS fragmentation", file=sys.stderr)
    sys.exit(1)

meta_id    = "test_actives"
input_file = "test_actives_validated.csv"

compounds = []
with open(input_file, newline="") as csvf:
    reader = csv.DictReader(csvf)
    for row in reader:
        if row.get("valid", "").lower() == "true":
            compounds.append(row)

all_fragments = []
scaffold_freq = {}

for cmpd in compounds:
    cid = cmpd["compound_id"]
    smi = cmpd["canonical_smiles"] or cmpd["smiles"]
    mol = Chem.MolFromSmiles(smi)
    if mol is None:
        continue

    try:
        frags = list(BRICS.BRICSDecompose(mol))
    except Exception as e:
        print(f"  WARNING: BRICS failed for {cid}: {e}", file=sys.stderr)
        continue

    for leaf_smi in frags:
        try:
            leaf_mol = Chem.MolFromSmiles(leaf_smi)
            if leaf_mol is None:
                continue
            mw = round(Descriptors.MolWt(leaf_mol), 3)
            ha = leaf_mol.GetNumHeavyAtoms()
        except Exception:
            mw, ha = 0.0, 0

        n_attach = leaf_smi.count("[*]")
        frag_id = f"FRAG_{cid}_{len(all_fragments):04d}"
        all_fragments.append({
            "compound_id":        cid,
            "parent_smiles":      smi,
            "fragment_id":        frag_id,
            "scaffold_smiles":    leaf_smi,
            "rgroup_smiles":      "",
            "bond_type":          "brics",
            "attachment_points":  n_attach,
            "scaffold_mw":        mw,
            "rgroup_mw":          0.0,
            "scaffold_heavy_atoms": ha,
            "fragment_frequency": 1,
        })
        scaffold_freq[leaf_smi] = scaffold_freq.get(leaf_smi, 0) + 1

# Update frequencies
for frag in all_fragments:
    frag["fragment_frequency"] = scaffold_freq.get(frag["scaffold_smiles"], 1)

with open(f"{meta_id}_recap_fragments.csv", "w", newline="") as csvf:
    if all_fragments:
        writer = csv.DictWriter(csvf, fieldnames=list(all_fragments[0].keys()))
        writer.writeheader()
        writer.writerows(all_fragments)
    else:
        csvf.write("compound_id,scaffold_smiles,fragment_frequency\n")

unique_scaffolds = len(set(f["scaffold_smiles"] for f in all_fragments))
summary = {
    "meta_id":               meta_id,
    "input_file":            input_file,
    "total_compounds_processed": len(compounds),
    "total_fragments":       len(all_fragments),
    "unique_scaffolds":      unique_scaffolds,
    "top_scaffolds_by_frequency": sorted(
        [{"scaffold": sc, "frequency": freq}
         for sc, freq in scaffold_freq.items()],
        key=lambda x: -x["frequency"]
    )[:10],
    "tool":      "RDKit RECAP",
    "timestamp": datetime.utcnow().isoformat() + "Z",
    "mock_mode": False,
}
with open(f"{meta_id}_recap_summary.json", "w") as jf:
    json.dump(summary, jf, indent=2)

print(f"RECAP live complete: {len(all_fragments)} fragments, {unique_scaffolds} unique scaffolds")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "SCAFFOLD_HOPPING:RECAP_FRAGMENTATION":
        rdkit: $(python3 -c "from rdkit import __version__; print(__version__)" 2>/dev/null || echo "N/A")
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "false"
    END_VERSIONS
