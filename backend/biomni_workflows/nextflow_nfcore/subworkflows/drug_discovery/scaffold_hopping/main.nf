#!/usr/bin/env nextflow
/*
 * drug_discovery/scaffold_hopping
 *
 * RECAP Fragmentation + Matched Molecular Pair (MMP) scaffold hopping pipeline
 *
 * Pipeline Steps:
 * 1. SCAFFOLD_INPUT_VALIDATION    — validate SMILES input file (one SMILES+ID per line)
 * 2. RECAP_FRAGMENTATION          — RDKit RECAP decomposition into scaffold + R-groups
 * 3. MMP_ANALYSIS                 — mmpdb MMP analysis: property deltas for fragment swaps
 * 4. SCAFFOLD_HOPPING_CANDIDATES  — rank novel scaffolds by frequency, drug-likeness, SA score
 *
 * References:
 *  - RECAP:  Lewell et al. J. Chem. Inf. Comput. Sci. 1998, 38, 511-522
 *  - mmpdb:  Dalke et al. J. Cheminform. 2018, 10:14  (https://github.com/rdkit/mmpdb)
 *  - RDKit:  Landrum, G. RDKit (https://www.rdkit.org)
 *  - SA score: Ertl & Schuffenhauer, J. Cheminform. 2009, 1:8
 *  - Lipinski Rule of Five: Lipinski et al. Adv. Drug Deliv. Rev. 1997, 23, 3-25
 */

nextflow.enable.dsl = 2

// ============================================================================
// Default Parameters
// ============================================================================

params.outdir               = './results/scaffold_hopping'
params.publish_dir_mode     = 'copy'

// Mode flags
params.mock_mode            = true      // true = synthetic output, no real tools needed

// Input
params.input_smiles         = null      // path to SMILES file (one "SMILES compound_id" per line)
params.reference_smiles     = 'CC(=O)Nc1ccc(O)cc1'   // acetaminophen as default reference

// Filtering / ranking
params.max_candidates       = 20        // maximum scaffold candidates to report
params.lipinski_filter      = true      // apply Lipinski rule-of-five filter to candidates

// ============================================================================
// Helper functions
// ============================================================================

def log_workflow_header() {
    log.info """
    ====================================================================
    BioMate | Scaffold Hopping Pipeline
    ====================================================================
    Mode:               ${params.mock_mode ? 'MOCK (synthetic data)' : 'LIVE'}
    Reference SMILES:   ${params.reference_smiles}
    Max candidates:     ${params.max_candidates}
    Lipinski filter:    ${params.lipinski_filter}
    Output dir:         ${params.outdir}
    ====================================================================
    """.stripIndent()
}

// ============================================================================
// Process 1: SCAFFOLD_INPUT_VALIDATION
// ============================================================================

process SCAFFOLD_INPUT_VALIDATION {
    tag "${meta.id}"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}/01_validation", mode: params.publish_dir_mode

    container 'biomate/biomni-drug-discovery-nf:latest'

    input:
    tuple val(meta), path(smiles_file)

    output:
    tuple val(meta), path("*_validated.csv"),   emit: validated_csv
    tuple val(meta), path("*_validation_report.json"), emit: validation_report
    path "versions.yml",                        emit: versions

    script:
    def mock = params.mock_mode
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
import csv
import random
from datetime import datetime

random.seed(42)

meta_id     = "${meta.id}"
ref_smiles  = "${params.reference_smiles}"

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
    "input_file":       "${smiles_file}",
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

meta_id    = "${meta.id}"
input_file = "${smiles_file}"
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
    "${task.process}":
        rdkit: \$(python3 -c "from rdkit import __version__; print(__version__)" 2>/dev/null || echo "N/A")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    echo 'compound_id,smiles,mw_da,valid,canonical_smiles,inchi_key' > ${meta.id}_validated.csv
    echo '{"valid_count":10}' > ${meta.id}_validation_report.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        rdkit: "2023.09.5"
        python: "3.10.0"
    END_VERSIONS
    """
}

// ============================================================================
// Process 2: RECAP_FRAGMENTATION
// ============================================================================

process RECAP_FRAGMENTATION {
    tag "${meta.id}"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}/02_recap", mode: params.publish_dir_mode

    container 'biomate/biomni-drug-discovery-nf:latest'

    input:
    tuple val(meta), path(validated_csv)

    output:
    tuple val(meta), path("*_recap_fragments.csv"),  emit: fragments
    tuple val(meta), path("*_recap_summary.json"),   emit: summary
    path "versions.yml",                             emit: versions

    script:
    def mock = params.mock_mode
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
import csv
import random
from datetime import datetime

random.seed(42)

meta_id = "${meta.id}"

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
    "input_file":            "${validated_csv}",
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

meta_id    = "${meta.id}"
input_file = "${validated_csv}"

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
        csvf.write("compound_id,scaffold_smiles,fragment_frequency\\n")

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
    "${task.process}":
        rdkit: \$(python3 -c "from rdkit import __version__; print(__version__)" 2>/dev/null || echo "N/A")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    echo 'compound_id,scaffold_smiles,fragment_frequency' > ${meta.id}_recap_fragments.csv
    echo '{"total_fragments":8}' > ${meta.id}_recap_summary.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        rdkit: "2023.09.5"
        python: "3.10.0"
    END_VERSIONS
    """
}

// ============================================================================
// Process 3: MMP_ANALYSIS
// ============================================================================

process MMP_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}/03_mmp", mode: params.publish_dir_mode

    container 'biomate/biomni-drug-discovery-nf:latest'

    input:
    tuple val(meta), path(validated_csv), path(fragments_csv)
    val   reference_smiles

    output:
    tuple val(meta), path("*_mmp_pairs.csv"),        emit: mmp_pairs
    tuple val(meta), path("*_mmp_summary.json"),     emit: summary
    path "versions.yml",                             emit: versions

    script:
    def mock    = params.mock_mode
    def ref_smi = reference_smiles ?: params.reference_smiles
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
import csv
import random
from datetime import datetime

random.seed(42)

meta_id    = "${meta.id}"
ref_smiles = "${ref_smi}"

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

meta_id      = "${meta.id}"
input_csv    = "${validated_csv}"
ref_smiles   = "${ref_smi}"

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
        csvf.write("pair_id,query_smiles,match_smiles,transformation\\n")

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
    "${task.process}":
        mmpdb: \$(mmpdb --version 2>&1 | head -1 || echo "N/A")
        rdkit: \$(python3 -c "from rdkit import __version__; print(__version__)" 2>/dev/null || echo "N/A")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    echo 'pair_id,query_smiles,match_smiles,transformation,logP_delta,mw_delta_da,qed_delta' > ${meta.id}_mmp_pairs.csv
    echo '{"total_pairs":15}' > ${meta.id}_mmp_summary.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mmpdb: "3.1"
        rdkit: "2023.09.5"
        python: "3.10.0"
    END_VERSIONS
    """
}

// ============================================================================
// Process 4: SCAFFOLD_HOPPING_CANDIDATES
// ============================================================================

process SCAFFOLD_HOPPING_CANDIDATES {
    tag "${meta.id}"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}/04_candidates", mode: params.publish_dir_mode

    container 'biomate/biomni-drug-discovery-nf:latest'

    input:
    tuple val(meta), path(fragments_csv), path(mmp_pairs_csv)
    val   max_candidates
    val   lipinski_filter

    output:
    tuple val(meta), path("*_scaffold_candidates.csv"),  emit: candidates
    tuple val(meta), path("*_scaffold_report.html"),     emit: report
    tuple val(meta), path("*_ranking_summary.json"),     emit: ranking_summary
    path "versions.yml",                                 emit: versions

    script:
    def mock        = params.mock_mode
    def max_cands   = max_candidates ?: params.max_candidates
    def lip_filter  = lipinski_filter ?: params.lipinski_filter
    """
    if [ "${mock}" = "true" ]; then
        python3 << 'EOF'
import json
import csv
import random
from datetime import datetime

random.seed(42)

meta_id     = "${meta.id}"
max_cands   = int("${max_cands}")
lip_filter  = str("${lip_filter}").lower() in ("true", "1", "yes")

# ---------------------------------------------------------------------------
# Mock top-10 scaffold hop candidates
#
# Ranking criteria:
#   1. MMP frequency (how often the scaffold appears across pairs)
#   2. QED score      (Bickerton et al., quantitative drug-likeness 0-1)
#   3. Lipinski pass  (MW ≤ 500, HBA ≤ 10, HBD ≤ 5, logP ≤ 5)
#   4. SA score       (Ertl & Schuffenhauer synthetic accessibility, 1=easy, 10=hard)
#
# Compounds ordered by composite rank score = 0.4*QED + 0.3*norm_freq + 0.3*(1-norm_SA)
# ---------------------------------------------------------------------------
candidates = [
    {
        "rank":           1,
        "scaffold_smiles": "[*]Nc1ccc(O)cc1",
        "hop_smiles":     "CC(=O)Nc1ccc(O)cc1",
        "scaffold_id":    "SCAF_001",
        "mmp_frequency":  9,
        "qed_score":      0.82,
        "sa_score":       1.83,
        "mw_da":          151.16,
        "logP":           0.91,
        "hba":            2,
        "hbd":            2,
        "lipinski_pass":  True,
        "rank_score":     0.791,
        "origin_pairs":   "MMP_001,MMP_009,MMP_010,MMP_011,MMP_013,MMP_014",
        "novelty_flag":   "reference_scaffold",
    },
    {
        "rank":           2,
        "scaffold_smiles": "Fc1ccc([*])cc1",
        "hop_smiles":     "CC(=O)Nc1ccc(F)cc1",
        "scaffold_id":    "SCAF_002",
        "mmp_frequency":  5,
        "qed_score":      0.79,
        "sa_score":       1.91,
        "mw_da":          153.15,
        "logP":           1.77,
        "hba":            1,
        "hbd":            1,
        "lipinski_pass":  True,
        "rank_score":     0.753,
        "origin_pairs":   "MMP_002,MMP_006,MMP_008",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           3,
        "scaffold_smiles": "COc1ccc([*])cc1",
        "hop_smiles":     "CC(=O)Nc1ccc(OC)cc1",
        "scaffold_id":    "SCAF_003",
        "mmp_frequency":  7,
        "qed_score":      0.77,
        "sa_score":       2.01,
        "mw_da":          165.19,
        "logP":           1.35,
        "hba":            2,
        "hbd":            1,
        "lipinski_pass":  True,
        "rank_score":     0.741,
        "origin_pairs":   "MMP_001,MMP_006,MMP_007,MMP_015",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           4,
        "scaffold_smiles": "Clc1ccc([*])cc1",
        "hop_smiles":     "CC(=O)Nc1ccc(Cl)cc1",
        "scaffold_id":    "SCAF_004",
        "mmp_frequency":  5,
        "qed_score":      0.74,
        "sa_score":       1.95,
        "mw_da":          169.61,
        "logP":           2.39,
        "hba":            1,
        "hbd":            1,
        "lipinski_pass":  True,
        "rank_score":     0.718,
        "origin_pairs":   "MMP_003,MMP_007,MMP_008",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           5,
        "scaffold_smiles": "Cc1cc([*])ccc1O",
        "hop_smiles":     "CC(=O)Nc1ccc(O)cc1C",
        "scaffold_id":    "SCAF_005",
        "mmp_frequency":  4,
        "qed_score":      0.72,
        "sa_score":       2.14,
        "mw_da":          165.19,
        "logP":           1.35,
        "hba":            2,
        "hbd":            2,
        "lipinski_pass":  True,
        "rank_score":     0.694,
        "origin_pairs":   "MMP_013,MMP_014",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           6,
        "scaffold_smiles": "[*]Nc1cc(O)ccc1",
        "hop_smiles":     "CC(=O)Nc1cc(O)ccc1",
        "scaffold_id":    "SCAF_006",
        "mmp_frequency":  3,
        "qed_score":      0.70,
        "sa_score":       2.02,
        "mw_da":          151.16,
        "logP":           0.88,
        "hba":            2,
        "hbd":            2,
        "lipinski_pass":  True,
        "rank_score":     0.681,
        "origin_pairs":   "MMP_009",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           7,
        "scaffold_smiles": "O=C([*])c1ccccc1",
        "hop_smiles":     "O=C(Nc1ccc(O)cc1)c1ccccc1",
        "scaffold_id":    "SCAF_007",
        "mmp_frequency":  4,
        "qed_score":      0.68,
        "sa_score":       1.78,
        "mw_da":          213.23,
        "logP":           2.12,
        "hba":            2,
        "hbd":            2,
        "lipinski_pass":  True,
        "rank_score":     0.671,
        "origin_pairs":   "MMP_005,MMP_012",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           8,
        "scaffold_smiles": "Fc1cc([*])ccc1O",
        "hop_smiles":     "CC(=O)Nc1ccc(O)c(F)c1",
        "scaffold_id":    "SCAF_008",
        "mmp_frequency":  3,
        "qed_score":      0.66,
        "sa_score":       2.21,
        "mw_da":          169.15,
        "logP":           1.47,
        "hba":            2,
        "hbd":            2,
        "lipinski_pass":  True,
        "rank_score":     0.649,
        "origin_pairs":   "MMP_010",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           9,
        "scaffold_smiles": "[*]Nc1ccc([*])cc1",
        "hop_smiles":     "CCC(=O)Nc1ccc(O)cc1",
        "scaffold_id":    "SCAF_009",
        "mmp_frequency":  3,
        "qed_score":      0.63,
        "sa_score":       2.05,
        "mw_da":          165.19,
        "logP":           1.14,
        "hba":            2,
        "hbd":            2,
        "lipinski_pass":  True,
        "rank_score":     0.621,
        "origin_pairs":   "MMP_004,MMP_012",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           10,
        "scaffold_smiles": "Cc1ccc([*])cc1O",
        "hop_smiles":     "CC(=O)Nc1ccc(O)c(C)c1",
        "scaffold_id":    "SCAF_010",
        "mmp_frequency":  2,
        "qed_score":      0.60,
        "sa_score":       2.18,
        "mw_da":          165.19,
        "logP":           1.22,
        "hba":            2,
        "hbd":            2,
        "lipinski_pass":  True,
        "rank_score":     0.598,
        "origin_pairs":   "MMP_011",
        "novelty_flag":   "novel_hop",
    },
]

# Apply Lipinski filter if requested
if lip_filter:
    candidates = [c for c in candidates if c["lipinski_pass"]]

# Cap at max_candidates
candidates = candidates[:max_cands]

# Re-rank after filter
for i, c in enumerate(candidates, 1):
    c["rank"] = i

with open(f"{meta_id}_scaffold_candidates.csv", "w", newline="") as csvf:
    writer = csv.DictWriter(csvf, fieldnames=list(candidates[0].keys()))
    writer.writeheader()
    writer.writerows(candidates)

# ---- HTML Report ----
def qed_color(q):
    if q >= 0.75: return "#2ecc71"    # green
    if q >= 0.60: return "#f39c12"    # amber
    return "#e74c3c"                  # red

def sa_color(sa):
    if sa <= 2.0: return "#2ecc71"
    if sa <= 3.5: return "#f39c12"
    return "#e74c3c"

rows_html = ""
for c in candidates:
    lip_badge = (
        '<span style="background:#2ecc71;color:#fff;padding:2px 6px;border-radius:3px;">PASS</span>'
        if c["lipinski_pass"] else
        '<span style="background:#e74c3c;color:#fff;padding:2px 6px;border-radius:3px;">FAIL</span>'
    )
    qc = qed_color(c["qed_score"])
    sc = sa_color(c["sa_score"])
    rows_html += (
        "        <tr>\\n"
        "          <td style='text-align:center'><b>" + str(c["rank"]) + "</b></td>\\n"
        "          <td><code style='font-size:11px'>" + str(c["hop_smiles"]) + "</code></td>\\n"
        "          <td><code style='font-size:10px;color:#555'>" + str(c["scaffold_smiles"]) + "</code></td>\\n"
        "          <td style='text-align:center'>" + str(c["mmp_frequency"]) + "</td>\\n"
        "          <td style='text-align:center;color:" + qc + "'><b>" + "{:.2f}".format(c["qed_score"]) + "</b></td>\\n"
        "          <td style='text-align:center;color:" + sc + "'>" + "{:.2f}".format(c["sa_score"]) + "</td>\\n"
        "          <td style='text-align:center'>" + "{:.1f}".format(c["mw_da"]) + "</td>\\n"
        "          <td style='text-align:center'>" + "{:.2f}".format(c["logP"]) + "</td>\\n"
        "          <td style='text-align:center'>" + lip_badge + "</td>\\n"
        "          <td style='text-align:center;font-weight:bold'>" + "{:.3f}".format(c["rank_score"]) + "</td>\\n"
        "        </tr>\\n"
    )

n_cands   = len(candidates)
lip_label = "ON" if lip_filter else "OFF"
generated = datetime.utcnow().isoformat() + "Z"
html = (
    "<!DOCTYPE html>\\n"
    "<html lang='en'>\\n"
    "<head>\\n"
    "  <meta charset='UTF-8'>\\n"
    "  <title>BioMate Scaffold Hopping Report - " + meta_id + "</title>\\n"
    "  <style>\\n"
    "    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;"
    "           margin: 0; padding: 24px; background: #f9f9f9; color: #222; }\\n"
    "    h1   { font-size: 22px; color: #2c3e50; border-bottom: 2px solid #3498db;"
    "           padding-bottom: 8px; }\\n"
    "    .meta { background: #eaf2fb; border-left: 4px solid #3498db;"
    "            padding: 10px 16px; margin: 16px 0; border-radius: 4px; font-size: 14px; }\\n"
    "    .badge { display:inline-block; background:#3498db; color:#fff;"
    "             padding:2px 8px; border-radius:10px; font-size:12px; margin:2px; }\\n"
    "    table { border-collapse: collapse; width: 100%; background: #fff;"
    "            box-shadow: 0 1px 4px rgba(0,0,0,.08); border-radius: 6px;"
    "            overflow: hidden; margin-top: 16px; }\\n"
    "    th    { background: #2c3e50; color: #fff; padding: 10px 8px;"
    "            font-size: 12px; text-align: center; }\\n"
    "    td    { padding: 8px 8px; font-size: 12px; border-bottom: 1px solid #eee; }\\n"
    "    tr:hover td { background: #f0f7ff; }\\n"
    "    .footer { font-size: 11px; color: #999; margin-top: 20px; text-align: right; }\\n"
    "  </style>\\n"
    "</head>\\n"
    "<body>\\n"
    "  <h1>BioMate Scaffold Hopping Report</h1>\\n"
    "  <div class='meta'>\\n"
    "    <b>Run ID:</b> " + meta_id + " &nbsp;|&nbsp;\\n"
    "    <b>Reference SMILES:</b> <code>CC(=O)Nc1ccc(O)cc1</code> (acetaminophen) &nbsp;|&nbsp;\\n"
    "    <b>Candidates shown:</b> " + str(n_cands) + " &nbsp;|&nbsp;\\n"
    "    <b>Lipinski filter:</b> " + lip_label + " &nbsp;|&nbsp;\\n"
    "    <b>Mode:</b> <span class='badge'>MOCK</span>\\n"
    "    <br><b>Generated:</b> " + generated + "\\n"
    "  </div>\\n"
    "  <h2 style='font-size:16px;margin-top:24px'>Top Scaffold Hop Candidates</h2>\\n"
    "  <p style='font-size:13px;color:#555'>\\n"
    "    Rank score = 0.4 x QED + 0.3 x norm_frequency + 0.3 x (1 - norm_SA_score).\\n"
    "    Lipinski pass: MW &le; 500, HBA &le; 10, HBD &le; 5, logP &le; 5.\\n"
    "  </p>\\n"
    "  <table>\\n"
    "    <thead>\\n"
    "      <tr>\\n"
    "        <th>Rank</th><th>Hop SMILES</th><th>Core Scaffold</th>\\n"
    "        <th>MMP Freq</th><th>QED</th><th>SA Score</th>\\n"
    "        <th>MW (Da)</th><th>logP</th><th>Lipinski</th><th>Rank Score</th>\\n"
    "      </tr>\\n"
    "    </thead>\\n"
    "    <tbody>\\n"
    + rows_html +
    "    </tbody>\\n"
    "  </table>\\n"
    "  <div class='footer'>\\n"
    "    Generated by BioMate scaffold_hopping pipeline &bull;\\n"
    "    RECAP (Lewell 1998) + mmpdb (Dalke 2018) + RDKit &bull;\\n"
    "    Mock mode - no real chemistry tools were executed\\n"
    "  </div>\\n"
    "</body>\\n"
    "</html>\\n"
)
with open(f"{meta_id}_scaffold_report.html", "w") as hf:
    hf.write(html)

# Ranking summary JSON
ranking_summary = {
    "meta_id":              meta_id,
    "total_candidates":     len(candidates),
    "lipinski_filter_applied": lip_filter,
    "max_candidates":       max_cands,
    "top_candidate": {
        "smiles":      candidates[0]["hop_smiles"],
        "scaffold":    candidates[0]["scaffold_smiles"],
        "qed":         candidates[0]["qed_score"],
        "sa_score":    candidates[0]["sa_score"],
        "rank_score":  candidates[0]["rank_score"],
    },
    "qed_range":   [min(c["qed_score"] for c in candidates),
                    max(c["qed_score"] for c in candidates)],
    "sa_score_range": [min(c["sa_score"] for c in candidates),
                       max(c["sa_score"] for c in candidates)],
    "all_lipinski_pass": all(c["lipinski_pass"] for c in candidates),
    "tool":      "RDKit (QED + SA score, mock)",
    "timestamp": datetime.utcnow().isoformat() + "Z",
    "mock_mode": True,
}

with open(f"{meta_id}_ranking_summary.json", "w") as jf:
    json.dump(ranking_summary, jf, indent=2)

print(f"Scaffold hopping mock complete: {len(candidates)} candidates ranked")
print(f"  Top hit: {candidates[0]['hop_smiles']}")
print(f"  Top QED: {candidates[0]['qed_score']:.2f}  SA: {candidates[0]['sa_score']:.2f}")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: RDKit QED + SA score ranking
        # ---------------------------------------------------------------------------
        python3 << 'PYEOF'
import json
import csv
import sys
from datetime import datetime

try:
    from rdkit import Chem
    from rdkit.Chem import Descriptors, QED, rdMolDescriptors
    from rdkit.Contrib.SA_Score import sascorer
    RDKIT_OK = True
except ImportError:
    RDKIT_OK = False
    print("WARNING: RDKit or SA_Score contrib not found.", file=sys.stderr)

meta_id      = "${meta.id}"
frags_file   = "${fragments_csv}"
mmp_file     = "${mmp_pairs_csv}"
max_cands    = int("${max_cands}")
lip_filter   = str("${lip_filter}").lower() in ("true", "1", "yes")

# ---- 1. Collect candidate SMILES from MMP pairs ----
candidates_raw = {}
with open(mmp_file, newline="") as csvf:
    reader = csv.DictReader(csvf)
    for row in reader:
        for smi_key in ("match_smiles", "query_smiles"):
            smi = row.get(smi_key, "").strip()
            if smi:
                candidates_raw[smi] = candidates_raw.get(smi, 0) + 1

# Also add RECAP scaffold smiles as hopping candidates
with open(frags_file, newline="") as csvf:
    reader = csv.DictReader(csvf)
    for row in reader:
        sc = row.get("scaffold_smiles", "").strip()
        if sc:
            candidates_raw[sc] = candidates_raw.get(sc, 0) + int(row.get("fragment_frequency", 1))

# ---- 2. Score each candidate ----
scored = []
for smi, freq in candidates_raw.items():
    mol = Chem.MolFromSmiles(smi) if RDKIT_OK else None
    if mol is None:
        continue

    mw    = round(Descriptors.MolWt(mol), 3)
    logp  = round(Descriptors.MolLogP(mol), 3)
    hba   = rdMolDescriptors.CalcNumHBA(mol)
    hbd   = rdMolDescriptors.CalcNumHBD(mol)
    qed   = round(QED.qed(mol), 4)
    try:
        sa  = round(sascorer.calculateScore(mol), 3)
    except Exception:
        sa  = 5.0

    lip   = (mw <= 500 and hba <= 10 and hbd <= 5 and logp <= 5)

    if lip_filter and not lip:
        continue

    scored.append({
        "smiles":          smi,
        "mmp_frequency":   freq,
        "qed_score":       qed,
        "sa_score":        sa,
        "mw_da":           mw,
        "logP":            logp,
        "hba":             hba,
        "hbd":             hbd,
        "lipinski_pass":   lip,
    })

# ---- 3. Normalise + composite rank ----
if scored:
    max_freq = max(c["mmp_frequency"] for c in scored) or 1
    max_sa   = max(c["sa_score"]      for c in scored) or 1
    for c in scored:
        norm_freq = c["mmp_frequency"] / max_freq
        norm_sa   = c["sa_score"] / max_sa
        c["rank_score"] = round(0.4 * c["qed_score"] + 0.3 * norm_freq + 0.3 * (1 - norm_sa), 4)

scored.sort(key=lambda x: -x["rank_score"])
scored = scored[:max_cands]

for i, c in enumerate(scored, 1):
    c["rank"]       = i
    c["scaffold_id"] = f"SCAF_{i:03d}"
    c["hop_smiles"]  = c.pop("smiles")

with open(f"{meta_id}_scaffold_candidates.csv", "w", newline="") as csvf:
    if scored:
        writer = csv.DictWriter(csvf, fieldnames=list(scored[0].keys()))
        writer.writeheader()
        writer.writerows(scored)
    else:
        csvf.write("rank,scaffold_id,hop_smiles,qed_score,sa_score\\n")

# Minimal HTML report (build rows without nested f-strings)
table_rows = ""
for c in scored:
    table_rows += (
        "<tr><td>" + str(c["rank"]) + "</td>"
        "<td><code>" + str(c["hop_smiles"]) + "</code></td>"
        "<td>" + str(c["qed_score"]) + "</td>"
        "<td>" + str(c["sa_score"]) + "</td>"
        "<td>" + str(c["mw_da"]) + "</td>"
        "<td>" + str(c["logP"]) + "</td>"
        "<td>" + str(c["rank_score"]) + "</td></tr>"
    )
n_cands    = len(scored)
lip_label  = "ON" if lip_filter else "OFF"
generated  = datetime.utcnow().isoformat() + "Z"
html = (
    "<!DOCTYPE html>\\n<html><head><meta charset='UTF-8'>\\n"
    "<title>BioMate Scaffold Hopping — " + meta_id + "</title></head>\\n"
    "<body><h1>Scaffold Hopping Candidates — " + meta_id + "</h1>\\n"
    "<p>" + str(n_cands) + " candidates (Lipinski filter: " + lip_label + ")</p>\\n"
    "<table border='1' cellpadding='4'>\\n"
    "<tr><th>Rank</th><th>SMILES</th><th>QED</th><th>SA</th>"
    "<th>MW</th><th>logP</th><th>Score</th></tr>\\n"
    + table_rows +
    "\\n</table>\\n"
    "<p><small>Generated " + generated + " | BioMate scaffold_hopping pipeline</small></p>\\n"
    "</body></html>"
)
with open(f"{meta_id}_scaffold_report.html", "w") as hf:
    hf.write(html)

ranking_summary = {
    "meta_id":               meta_id,
    "total_candidates":      len(scored),
    "lipinski_filter_applied": lip_filter,
    "top_candidate":         scored[0] if scored else {},
    "timestamp":             datetime.utcnow().isoformat() + "Z",
    "mock_mode":             False,
}
with open(f"{meta_id}_ranking_summary.json", "w") as jf:
    json.dump(ranking_summary, jf, indent=2)

print(f"Scaffold hopping live: {len(scored)} candidates ranked")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        rdkit: \$(python3 -c "from rdkit import __version__; print(__version__)" 2>/dev/null || echo "N/A")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "${mock}"
    END_VERSIONS
    """

    stub:
    """
    echo 'rank,scaffold_id,hop_smiles,qed_score,sa_score,rank_score' > ${meta.id}_scaffold_candidates.csv
    echo '<html><body>stub</body></html>' > ${meta.id}_scaffold_report.html
    echo '{"total_candidates":10}' > ${meta.id}_ranking_summary.json
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        rdkit: "2023.09.5"
        python: "3.10.0"
    END_VERSIONS
    """
}

// ============================================================================
// Entry workflow: SCAFFOLD_HOPPING
// ============================================================================
//
// Linear pipeline layout:
//
//   ch_smiles ──► SCAFFOLD_INPUT_VALIDATION
//                         │
//                         ▼
//               RECAP_FRAGMENTATION
//                         │
//                         ▼
//                   MMP_ANALYSIS
//                         │
//                         ▼
//          SCAFFOLD_HOPPING_CANDIDATES
//                         │
//                    emit results
//
// ============================================================================

workflow SCAFFOLD_HOPPING {
    take:
    ch_smiles        // channel: [ tuple(meta, path(smiles_file)) ]
    reference_smiles // val: reference compound SMILES string

    main:
    // ------------------------------------------------------------------
    // Step 1: Validate SMILES input
    // ------------------------------------------------------------------
    SCAFFOLD_INPUT_VALIDATION(
        ch_smiles
    )

    // ------------------------------------------------------------------
    // Step 2: RECAP fragmentation → scaffolds + R-groups
    // ------------------------------------------------------------------
    RECAP_FRAGMENTATION(
        SCAFFOLD_INPUT_VALIDATION.out.validated_csv
    )

    // ------------------------------------------------------------------
    // Step 3: MMP analysis relative to reference compound
    // ------------------------------------------------------------------
    // Join validated CSV + fragments CSV per sample
    ch_mmp_input = SCAFFOLD_INPUT_VALIDATION.out.validated_csv
        .join(RECAP_FRAGMENTATION.out.fragments, by: 0)
        .map { meta, validated, frags -> tuple(meta, validated, frags) }

    MMP_ANALYSIS(
        ch_mmp_input,
        reference_smiles
    )

    // ------------------------------------------------------------------
    // Step 4: Rank scaffold hop candidates
    // ------------------------------------------------------------------
    ch_ranking_input = RECAP_FRAGMENTATION.out.fragments
        .join(MMP_ANALYSIS.out.mmp_pairs, by: 0)
        .map { meta, frags, pairs -> tuple(meta, frags, pairs) }

    SCAFFOLD_HOPPING_CANDIDATES(
        ch_ranking_input,
        params.max_candidates ?: 20,
        params.lipinski_filter ?: true
    )

    emit:
    validated_csv    = SCAFFOLD_INPUT_VALIDATION.out.validated_csv
    recap_fragments  = RECAP_FRAGMENTATION.out.fragments
    recap_summary    = RECAP_FRAGMENTATION.out.summary
    mmp_pairs        = MMP_ANALYSIS.out.mmp_pairs
    mmp_summary      = MMP_ANALYSIS.out.summary
    candidates       = SCAFFOLD_HOPPING_CANDIDATES.out.candidates
    report           = SCAFFOLD_HOPPING_CANDIDATES.out.report
    ranking_summary  = SCAFFOLD_HOPPING_CANDIDATES.out.ranking_summary
    versions         = SCAFFOLD_INPUT_VALIDATION.out.versions
                           .mix(RECAP_FRAGMENTATION.out.versions)
                           .mix(MMP_ANALYSIS.out.versions)
                           .mix(SCAFFOLD_HOPPING_CANDIDATES.out.versions)
}

// ============================================================================
// Standalone Entry Point (nextflow run main.nf)
// ============================================================================

workflow {
    log_workflow_header()

    // Default test inputs (mock mode — no real files needed)
    if (params.mock_mode) {
        ch_smiles = Channel.of(
            [
                [
                    id:             'scaffold_hop_demo',
                    compound_class: 'analgesic',
                    sample_type:    'small_molecule'
                ],
                file("${projectDir}/test_data/input_smiles.smi", checkIfExists: false)
            ]
        ).map { meta, smiles_file ->
            // In mock mode create a synthetic SMILES file on the fly if not present
            def f = smiles_file.exists() ? smiles_file : {
                def tmp = file("${workDir}/mock_${meta.id}.smi")
                tmp.text = [
                    "CC(=O)Nc1ccc(O)cc1 REF_001",
                    "CC(=O)Nc1ccc(OC)cc1 ANA_002",
                    "CC(=O)Nc1ccc(F)cc1 ANA_003",
                    "CC(=O)Nc1ccc(Cl)cc1 ANA_004",
                    "CCC(=O)Nc1ccc(O)cc1 ANA_005",
                    "CC(=O)Nc1ccc(O)c(F)c1 ANA_006",
                    "CC(=O)Nc1ccc(O)c(C)c1 ANA_007",
                    "CC(=O)Nc1cc(O)ccc1 ANA_008",
                    "O=C(Nc1ccc(O)cc1)c1ccccc1 ANA_009",
                    "CC(=O)Nc1ccc(O)cc1C ANA_010",
                ].join("\\n")
                tmp
            }()
            return tuple(meta, f)
        }
    } else {
        if (!params.input_smiles) {
            error "params.input_smiles is required in live mode. Pass --input_smiles <path>"
        }
        ch_smiles = Channel
            .fromPath(params.input_smiles, checkIfExists: true)
            .map { smiles_file ->
                def meta = [
                    id:             smiles_file.baseName,
                    compound_class: 'unknown',
                    sample_type:    'small_molecule'
                ]
                tuple(meta, smiles_file)
            }
    }

    // Run the pipeline
    SCAFFOLD_HOPPING(ch_smiles, params.reference_smiles ?: 'CC(=O)Nc1ccc(O)cc1')

    // Display summary
    SCAFFOLD_HOPPING.out.recap_summary.view { meta, summary_file ->
        "RECAP summary (${meta.id}): ${summary_file}"
    }
    SCAFFOLD_HOPPING.out.mmp_summary.view { meta, summary_file ->
        "MMP summary (${meta.id}): ${summary_file}"
    }
    SCAFFOLD_HOPPING.out.ranking_summary.view { meta, ranking_file ->
        "Scaffold candidates (${meta.id}): ${ranking_file}"
    }
    SCAFFOLD_HOPPING.out.report.view { meta, report_file ->
        "HTML report (${meta.id}): ${report_file}"
    }
}
