#!/bin/bash -ue
if [ "false" = "true" ]; then
        python3 << 'EOF'
import json
import csv
import random
from datetime import datetime

random.seed(42)

meta_id    = "test_actives"
ref_smiles = "CC(=O)Nc1ccc(O)cc1"

# ---------------------------------------------------------------------------
# Mock MMP output: 15 matched molecular pairs
#
# Each MMP = two compounds that differ by a single RECAP fragment swap
# (the "matched" bond is at the same attachment point in both molecules).
#
# Property deltas computed relative to the reference compound:
#   logP_delta:  positive = more lipophilic
#   mw_delta:    Da difference (positive = heavier)
#   qed_delta:   quantitative estimate of drug-likeness change
# ---------------------------------------------------------------------------
pairs = [
    # Format: (pair_id, query_smi, match_smi, transformation, logP_q, logP_m,
    #          mw_q, mw_m, qed_q, qed_m)
    ("MMP_001", "CC(=O)Nc1ccc(O)cc1",  "CC(=O)Nc1ccc(OC)cc1",
     "OH>>OC",        0.91, 1.35, 151.16, 165.19, 0.70, 0.67),
    ("MMP_002", "CC(=O)Nc1ccc(O)cc1",  "CC(=O)Nc1ccc(F)cc1",
     "OH>>F",         0.91, 1.77, 151.16, 153.15, 0.70, 0.72),
    ("MMP_003", "CC(=O)Nc1ccc(O)cc1",  "CC(=O)Nc1ccc(Cl)cc1",
     "OH>>Cl",        0.91, 2.39, 151.16, 169.61, 0.70, 0.65),
    ("MMP_004", "CC(=O)Nc1ccc(O)cc1",  "CCC(=O)Nc1ccc(O)cc1",
     "CC(=O)>>CCC(=O)",0.91,1.14, 151.16, 165.19, 0.70, 0.68),
    ("MMP_005", "CC(=O)Nc1ccc(O)cc1",  "O=C(Nc1ccc(O)cc1)c1ccccc1",
     "CC(=O)>>O=C(c1ccccc1)",
                      0.91, 2.12, 151.16, 213.23, 0.70, 0.61),
    ("MMP_006", "CC(=O)Nc1ccc(OC)cc1", "CC(=O)Nc1ccc(F)cc1",
     "OC>>F",         1.35, 1.77, 165.19, 153.15, 0.67, 0.72),
    ("MMP_007", "CC(=O)Nc1ccc(OC)cc1", "CC(=O)Nc1ccc(Cl)cc1",
     "OC>>Cl",        1.35, 2.39, 165.19, 169.61, 0.67, 0.65),
    ("MMP_008", "CC(=O)Nc1ccc(F)cc1",  "CC(=O)Nc1ccc(Cl)cc1",
     "F>>Cl",         1.77, 2.39, 153.15, 169.61, 0.72, 0.65),
    ("MMP_009", "CC(=O)Nc1ccc(O)cc1",  "CC(=O)Nc1cc(O)ccc1",
     "para-OH>>meta-OH",
                      0.91, 0.88, 151.16, 151.16, 0.70, 0.69),
    ("MMP_010", "CC(=O)Nc1ccc(O)c(F)c1","CC(=O)Nc1ccc(O)cc1",
     "2-F,4-OH>>4-OH",1.47, 0.91, 169.15, 151.16, 0.68, 0.70),
    ("MMP_011", "CC(=O)Nc1ccc(O)c(C)c1","CC(=O)Nc1ccc(O)cc1",
     "2-Me,4-OH>>4-OH",
                      1.22, 0.91, 165.19, 151.16, 0.67, 0.70),
    ("MMP_012", "CCC(=O)Nc1ccc(O)cc1", "O=C(Nc1ccc(O)cc1)c1ccccc1",
     "CCC(=O)>>O=C(c1ccccc1)",
                      1.14, 2.12, 165.19, 213.23, 0.68, 0.61),
    ("MMP_013", "CC(=O)Nc1ccc(O)cc1C", "CC(=O)Nc1ccc(O)cc1",
     "2-Me>>H",       1.35, 0.91, 165.19, 151.16, 0.66, 0.70),
    ("MMP_014", "CC(=O)Nc1ccc(O)cc1",  "CC(=O)Nc1ccc(O)cc1C",
     "H>>2-Me",       0.91, 1.35, 151.16, 165.19, 0.70, 0.66),
    ("MMP_015", "CC(=O)Nc1ccc(OC)cc1", "CCC(=O)Nc1ccc(OC)cc1",
     "CC(=O)>>CCC(=O)",1.35,1.58, 165.19, 179.22, 0.67, 0.64),
]

rows = []
for (pid, q_smi, m_smi, transform,
     logp_q, logp_m, mw_q, mw_m, qed_q, qed_m) in pairs:
    rows.append({
        "pair_id":          pid,
        "query_smiles":     q_smi,
        "match_smiles":     m_smi,
        "transformation":   transform,
        "logP_query":       logp_q,
        "logP_match":       logp_m,
        "logP_delta":       round(logp_m - logp_q, 3),
        "mw_query_da":      mw_q,
        "mw_match_da":      mw_m,
        "mw_delta_da":      round(mw_m - mw_q, 3),
        "qed_query":        qed_q,
        "qed_match":        qed_m,
        "qed_delta":        round(qed_m - qed_q, 3),
        "is_reference_pair": str(q_smi == ref_smiles or m_smi == ref_smiles),
    })

with open(f"{meta_id}_mmp_pairs.csv", "w", newline="") as csvf:
    writer = csv.DictWriter(csvf, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)

# Summarise transformation rules
transform_counts = {}
for row in rows:
    t = row["transformation"]
    transform_counts[t] = transform_counts.get(t, 0) + 1

logp_deltas = [r["logP_delta"] for r in rows]
mw_deltas   = [r["mw_delta_da"] for r in rows]

summary = {
    "meta_id":           meta_id,
    "reference_smiles":  ref_smiles,
    "total_pairs":       len(rows),
    "reference_pairs":   sum(1 for r in rows if r["is_reference_pair"] == "True"),
    "logP_delta_range":  [min(logp_deltas), max(logp_deltas)],
    "mw_delta_range_da": [min(mw_deltas), max(mw_deltas)],
    "unique_transformations": len(transform_counts),
    "top_transformations": sorted(
        [{"transformation": t, "count": c} for t, c in transform_counts.items()],
        key=lambda x: -x["count"]
    )[:5],
    "tool":      "mmpdb 3.1 (mock)",
    "timestamp": datetime.utcnow().isoformat() + "Z",
    "mock_mode": True,
}

with open(f"{meta_id}_mmp_summary.json", "w") as jf:
    json.dump(summary, jf, indent=2)

print(f"MMP mock complete: {len(rows)} pairs, {len(transform_counts)} unique transformations")
print(f"  logP delta range: {min(logp_deltas):.3f} to {max(logp_deltas):.3f}")
print(f"  MW delta range:   {min(mw_deltas):.1f} to {max(mw_deltas):.1f} Da")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: RDKit BRICS-based scaffold pair analysis (mmpdb-free)
        # ---------------------------------------------------------------------------
        python3 << 'PYEOF'
import json
import csv
import sys
from datetime import datetime
from rdkit import Chem
from rdkit.Chem import BRICS, Descriptors, QED, rdMolDescriptors

meta_id      = "test_actives"
input_csv    = "test_actives_validated.csv"
ref_smiles   = "CC(=O)Nc1ccc(O)cc1"

ref_mol = Chem.MolFromSmiles(ref_smiles)
ref_frags = set(BRICS.BRICSDecompose(ref_mol)) if ref_mol else set()

compounds = []
with open(input_csv, newline="") as csvf:
    reader = csv.DictReader(csvf)
    for row in reader:
        if row.get("valid", "").lower() == "true":
            compounds.append(row)

rows = []
for i, cmpd in enumerate(compounds):
    smi = cmpd.get("canonical_smiles") or cmpd.get("smiles", "")
    mol = Chem.MolFromSmiles(smi)
    if mol is None:
        continue
    mol_frags = set(BRICS.BRICSDecompose(mol))
    shared = ref_frags & mol_frags
    if not shared:
        continue
    try:
        qed_q = round(QED.qed(ref_mol), 3) if ref_mol else 0.0
        qed_m = round(QED.qed(mol), 3)
        lp_q  = round(Descriptors.MolLogP(ref_mol), 3) if ref_mol else 0.0
        lp_m  = round(Descriptors.MolLogP(mol), 3)
        mw_q  = round(Descriptors.MolWt(ref_mol), 1) if ref_mol else 0.0
        mw_m  = round(Descriptors.MolWt(mol), 1)
    except Exception:
        qed_q = qed_m = lp_q = lp_m = mw_q = mw_m = 0.0
    rows.append({
        "pair_id":           f"MMP_{i+1:03d}",
        "query_smiles":      ref_smiles,
        "match_smiles":      smi,
        "transformation":    f"shared_brics_frags:{len(shared)}",
        "logP_query":        lp_q,
        "logP_match":        lp_m,
        "logP_delta":        round(lp_m - lp_q, 3),
        "mw_query_da":       mw_q,
        "mw_match_da":       mw_m,
        "mw_delta_da":       round(mw_m - mw_q, 1),
        "qed_query":         qed_q,
        "qed_match":         qed_m,
        "qed_delta":         round(qed_m - qed_q, 3),
        "is_reference_pair": "True",
    })

with open(f"{meta_id}_mmp_pairs.csv", "w", newline="") as csvf:
    if rows:
        writer = csv.DictWriter(csvf, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    else:
        csvf.write("pair_id,query_smiles,match_smiles,transformation\n")

summary = {
    "meta_id":          meta_id,
    "reference_smiles": ref_smiles,
    "total_pairs":      len(rows),
    "tool":             "rdkit_brics",
    "timestamp":        datetime.utcnow().isoformat() + "Z",
    "mock_mode":        False,
}
with open(f"{meta_id}_mmp_summary.json", "w") as jf:
    json.dump(summary, jf, indent=2)

print(f"MMP (BRICS-based) complete: {len(rows)} pairs from {len(compounds)} compounds")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "SCAFFOLD_HOPPING:MMP_ANALYSIS":
        mmpdb: $(mmpdb --version 2>&1 | head -1 || echo "N/A")
        rdkit: $(python3 -c "from rdkit import __version__; print(__version__)" 2>/dev/null || echo "N/A")
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "false"
    END_VERSIONS
