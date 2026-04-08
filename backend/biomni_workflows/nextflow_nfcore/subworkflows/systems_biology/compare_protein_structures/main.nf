#!/usr/bin/env nextflow
/*
 * systems_biology/compare_protein_structures
 * Compares two protein structures to identify structural differences and conformational changes.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.pdb_file1 = null
params.pdb_file2 = null
params.chain_id1 = 'A'
params.chain_id2 = 'A'
params.output_prefix = 'protein_comparison'

process COMPARE_PROTEIN_STRUCTURES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("compare_protein_structures_results.json"), emit: results
    tuple val(meta), path("compare_protein_structures_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_PDB_FILE1="${params.pdb_file1?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PDB_FILE2="${params.pdb_file2?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CHAIN_ID1="${params.chain_id1?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CHAIN_ID2="${params.chain_id2?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_PREFIX="${params.output_prefix?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os

def auto_convert(val):
    # Auto-convert string to appropriate type
    if val is None or val == '' or val == 'null':
        return None
    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    # Try float
    try:
        return float(val)
    except ValueError:
        pass
    # Return as string
    return val



def compare_protein_structures(pdb_file1, pdb_file2, chain_id1="A", chain_id2="A", output_prefix="protein_comparison"):
    '''
    Compares two protein structures to identify structural differences and conformational changes.

    Parameters:
    -----------
    pdb_file1 : str
        Path to the first PDB file
    pdb_file2 : str
        Path to the second PDB file
    chain_id1 : str, optional
        Chain ID to analyze in the first structure (default: 'A')
    chain_id2 : str, optional
        Chain ID to analyze in the second structure (default: 'A')
    output_prefix : str, optional
        Prefix for output files (default: "protein_comparison")

    Returns:
    --------
    str
        A research log summarizing the structural comparison analysis
    '''
    import warnings

    import numpy as np
    from Bio.PDB import PDBIO, PDBParser, Select, Superimposer
    from Bio.PDB.PDBExceptions import PDBConstructionWarning

    # Suppress PDB parsing warnings
    warnings.filterwarnings("ignore", category=PDBConstructionWarning)

    research_log = []
    research_log.append("# Protein Structure Comparison Analysis\\n")
    research_log.append(f"Comparing structures from {pdb_file1} and {pdb_file2}\\n")

    if pdb_file1 is None:
        raise ValueError("pdb_file1 is required: path to the first PDB file")
    if pdb_file2 is None:
        raise ValueError("pdb_file2 is required: path to the second PDB file")

    # Initialize parser
    parser = PDBParser()

    # Parse structures
    research_log.append("## Loading PDB structures")
    structure1 = parser.get_structure("structure1", pdb_file1)
    structure2 = parser.get_structure("structure2", pdb_file2)

    # Get specified chains
    try:
        chain1 = structure1[0][chain_id1]
        chain2 = structure2[0][chain_id2]
        research_log.append(f"Successfully loaded chain {chain_id1} from {pdb_file1}")
        research_log.append(f"Successfully loaded chain {chain_id2} from {pdb_file2}")
    except KeyError as e:
        return f"Error: Chain not found: {str(e)}"

    # Get CA atoms for alignment
    ca_atoms1 = []
    ca_atoms2 = []

    # Create residue mappings based on residue ID
    residues1 = {residue.id[1]: residue for residue in chain1 if residue.has_id("CA")}
    residues2 = {residue.id[1]: residue for residue in chain2 if residue.has_id("CA")}

    # Find common residues
    common_residues = sorted(set(residues1.keys()) & set(residues2.keys()))

    if len(common_residues) == 0:
        return "Error: No common residues with CA atoms found between the structures"

    research_log.append(f"Found {len(common_residues)} common residues for alignment\\n")

    # Get paired atoms for alignment
    for res_id in common_residues:
        ca_atoms1.append(residues1[res_id]["CA"])
        ca_atoms2.append(residues2[res_id]["CA"])

    # Perform structural alignment
    research_log.append("## Structural Alignment")
    super_imposer = Superimposer()
    super_imposer.set_atoms(ca_atoms1, ca_atoms2)
    super_imposer.apply(structure2.get_atoms())

    # Calculate RMSD
    rmsd = super_imposer.rms
    research_log.append(f"Overall RMSD: {rmsd:.4f} Å\\n")

    # Calculate per-residue distance after alignment
    research_log.append("## Conformational Differences Analysis")

    # Find regions with significant differences
    distance_data = []
    significant_changes = []
    threshold = 2.0  # Angstroms threshold for significant difference

    for res_id in common_residues:
        res1 = residues1[res_id]
        res2 = residues2[res_id]

        # Calculate distance between CA atoms
        ca1 = res1["CA"]
        ca2 = res2["CA"]
        distance = np.linalg.norm(ca1.coord - ca2.coord)

        distance_data.append((res_id, distance))

        if distance > threshold:
            significant_changes.append((res_id, res1.get_resname(), distance))

    # Save alignment as PDB files
    aligned_file1 = f"{output_prefix}_ref.pdb"
    aligned_file2 = f"{output_prefix}_aligned.pdb"

    io = PDBIO()
    io.set_structure(structure1)
    io.save(aligned_file1, select=Select())

    io.set_structure(structure2)
    io.save(aligned_file2, select=Select())

    research_log.append(f"Aligned structures saved as {aligned_file1} and {aligned_file2}")

    # Report on significant differences
    if significant_changes:
        research_log.append(
            f"\\nIdentified {len(significant_changes)} residues with significant conformational changes:"
        )
        for res_id, res_name, distance in significant_changes:
            research_log.append(f"  - Residue {res_name}{res_id}: {distance:.2f} Å displacement")
    else:
        research_log.append("\\nNo significant conformational changes detected (threshold: 2.0 Å)")

    # Save per-residue distance data
    distance_file = f"{output_prefix}_residue_distances.csv"
    with open(distance_file, "w") as f:
        f.write("Residue_ID,Distance(Å)\\n")
        for res_id, distance in distance_data:
            f.write(f"{res_id},{distance:.4f}\\n")

    research_log.append(f"\\nPer-residue distance data saved to {distance_file}")

    # Identify regions with continuous changes
    regions = []
    current_region = []

    for res_id, _, distance in significant_changes:
        if not current_region or res_id == current_region[-1][0] + 1:
            current_region.append((res_id, distance))
        else:
            if len(current_region) >= 3:  # Consider regions with at least 3 consecutive residues
                regions.append(current_region)
            current_region = [(res_id, distance)]

    if current_region and len(current_region) >= 3:
        regions.append(current_region)

    if regions:
        research_log.append("\\n## Continuous Regions with Conformational Changes")
        for i, region in enumerate(regions, 1):
            start_res = region[0][0]
            end_res = region[-1][0]
            avg_dist = sum(r[1] for r in region) / len(region)
            research_log.append(f"Region {i}: Residues {start_res}-{end_res} (Average displacement: {avg_dist:.2f} Å)")

    research_log.append("\\n## Summary")
    research_log.append(f"- Compared structures from {pdb_file1} and {pdb_file2}")
    research_log.append(f"- Overall RMSD: {rmsd:.4f} Å")
    research_log.append(f"- {len(significant_changes)} residues with significant conformational changes")
    research_log.append(f"- {len(regions)} continuous regions of conformational change")
    research_log.append(f"- Files generated: {aligned_file1}, {aligned_file2}, {distance_file}")

    return "\\n".join(research_log)

# Execute the function
try:
    result = compare_protein_structures(
        pdb_file1=auto_convert(os.environ.get("PARAM_PDB_FILE1", "")),
        pdb_file2=auto_convert(os.environ.get("PARAM_PDB_FILE2", "")),
        chain_id1=auto_convert(os.environ.get("PARAM_CHAIN_ID1", "A")),
        chain_id2=auto_convert(os.environ.get("PARAM_CHAIN_ID2", "A")),
        output_prefix=auto_convert(os.environ.get("PARAM_OUTPUT_PREFIX", "protein_comparison")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "compare_protein_structures",
    "domain": "systems_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("compare_protein_structures_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("compare_protein_structures_output.txt", "w") as f:
    f.write("Biomni: Compare Protein Structures" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "compare_protein_structures"
    END_VERSIONS
    """
}

workflow COMPARE_PROTEIN_STRUCTURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    COMPARE_PROTEIN_STRUCTURES(ch_input)

    emit:
    results = COMPARE_PROTEIN_STRUCTURES.out.results
    output = COMPARE_PROTEIN_STRUCTURES.out.output
    versions = COMPARE_PROTEIN_STRUCTURES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    COMPARE_PROTEIN_STRUCTURES_WORKFLOW(ch_input)

    COMPARE_PROTEIN_STRUCTURES_WORKFLOW.out.output.view { "Output: $it" }
}
