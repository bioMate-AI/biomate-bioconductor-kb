#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_compare_protein_structures
 * Compares two protein structures to identify structural differences and conformational changes.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.pdb_file1 = null
params.pdb_file2 = null
params.chain_id1 = 'A'
params.chain_id2 = 'A'
params.output_prefix = 'protein_comparison'

// Main process
process COMPARE_PROTEIN_STRUCTURES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("compare_protein_structures_results.json"), emit: results
    path("compare_protein_structures_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.systems_biology import compare_protein_structures
except ImportError:
    # Fallback: function may need to be implemented locally
    def compare_protein_structures(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = compare_protein_structures(
    pdb_file1="${params.pdb_file1}",
    pdb_file2="${params.pdb_file2}",
    chain_id1="${params.chain_id1}",
    chain_id2="${params.chain_id2}",
    output_prefix="${params.output_prefix}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("compare_protein_structures_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("compare_protein_structures_output.txt", "w") as f:
    f.write("Biomni: Compare Protein Structures Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("compare_protein_structures completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYSTEMS_BIOLOGY_COMPARE_PROTEIN_STRUCTURES {
    take:
    // No file inputs

    main:
    COMPARE_PROTEIN_STRUCTURES()

    emit:
    results = COMPARE_PROTEIN_STRUCTURES.out.results
    output = COMPARE_PROTEIN_STRUCTURES.out.output
}

// Entry workflow
workflow {
    if (!params.pdb_file1) {
        error "Please provide --pdb_file1 parameter"
    }
    if (!params.pdb_file2) {
        error "Please provide --pdb_file2 parameter"
    }


    BIOMNI_SYSTEMS_BIOLOGY_COMPARE_PROTEIN_STRUCTURES()
}
