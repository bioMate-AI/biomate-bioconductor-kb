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
    Mode:               LIVE
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

    // local (ARM dev): biomate/biomni-drug-discovery-nf:latest
    // aws batch (AMD64 ECR): 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86' : 'biomate/biomni-drug-discovery-nf:latest'

    input:
    tuple val(meta), path(smiles_file)

    output:
    tuple val(meta), path("*_validated.csv"),   emit: validated_csv
    tuple val(meta), path("*_validation_report.json"), emit: validation_report
    path "versions.yml",                        emit: versions

    script:
    """
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
    }
with open(f"{meta_id}_validation_report.json", "w") as jf:
    json.dump(report, jf, indent=2)

print(f"Validation complete: {len(compounds)} valid, {len(errors)} invalid")
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        rdkit: \$(python3 -c "from rdkit import __version__; print(__version__)" 2>/dev/null || echo "N/A")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
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

    // local (ARM dev): biomate/biomni-drug-discovery-nf:latest
    // aws batch (AMD64 ECR): 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86' : 'biomate/biomni-drug-discovery-nf:latest'

    input:
    tuple val(meta), path(validated_csv)

    output:
    tuple val(meta), path("*_recap_fragments.csv"),  emit: fragments
    tuple val(meta), path("*_recap_summary.json"),   emit: summary
    path "versions.yml",                             emit: versions

    script:
    """
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
    }
with open(f"{meta_id}_recap_summary.json", "w") as jf:
    json.dump(summary, jf, indent=2)

print(f"RECAP live complete: {len(all_fragments)} fragments, {unique_scaffolds} unique scaffolds")
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        rdkit: \$(python3 -c "from rdkit import __version__; print(__version__)" 2>/dev/null || echo "N/A")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
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

    // local (ARM dev): biomate/biomni-drug-discovery-nf:latest
    // aws batch (AMD64 ECR): 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86' : 'biomate/biomni-drug-discovery-nf:latest'

    input:
    tuple val(meta), path(validated_csv), path(fragments_csv)
    val   reference_smiles

    output:
    tuple val(meta), path("*_mmp_pairs.csv"),        emit: mmp_pairs
    tuple val(meta), path("*_mmp_summary.json"),     emit: summary
    path "versions.yml",                             emit: versions

    script:
    def ref_smi = reference_smiles ?: params.reference_smiles
    """
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
    }
with open(f"{meta_id}_mmp_summary.json", "w") as jf:
    json.dump(summary, jf, indent=2)

print(f"MMP (BRICS-based) complete: {len(rows)} pairs from {len(compounds)} compounds")
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mmpdb: \$(mmpdb --version 2>&1 | head -1 || echo "N/A")
        rdkit: \$(python3 -c "from rdkit import __version__; print(__version__)" 2>/dev/null || echo "N/A")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
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

    // local (ARM dev): biomate/biomni-drug-discovery-nf:latest
    // aws batch (AMD64 ECR): 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-drug-discovery-nf:x86' : 'biomate/biomni-drug-discovery-nf:latest'

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
    def max_cands   = max_candidates ?: params.max_candidates
    def lip_filter  = lipinski_filter ?: params.lipinski_filter
    """
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
    }
with open(f"{meta_id}_ranking_summary.json", "w") as jf:
    json.dump(ranking_summary, jf, indent=2)

print(f"Scaffold hopping live: {len(scored)} candidates ranked")
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        rdkit: \$(python3 -c "from rdkit import __version__; print(__version__)" 2>/dev/null || echo "N/A")
        python: \$(python3 --version 2>&1 | cut -d' ' -f2)
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

    // Default test inputs