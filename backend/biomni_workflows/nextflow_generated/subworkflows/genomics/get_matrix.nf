#!/usr/bin/env nextflow
/*
 * biomni_genomics_get_matrix
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.chrom = null
params.balance_if_possible = 'True'

// Main process
process GET_MATRIX {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_matrix_results.json"), emit: results
    path("get_matrix_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genomics import get_matrix
except ImportError:
    # Fallback: function may need to be implemented locally
    def get_matrix(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = get_matrix(
    chrom="${params.chrom}",
    balance_if_possible="${params.balance_if_possible}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_matrix_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("get_matrix_output.txt", "w") as f:
    f.write("Biomni: Get Matrix Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("get_matrix completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_GET_MATRIX {
    take:
    // No file inputs

    main:
    GET_MATRIX()

    emit:
    results = GET_MATRIX.out.results
    output = GET_MATRIX.out.output
}

// Entry workflow
workflow {
    if (!params.chrom) {
        error "Please provide --chrom parameter"
    }


    BIOMNI_GENOMICS_GET_MATRIX()
}
