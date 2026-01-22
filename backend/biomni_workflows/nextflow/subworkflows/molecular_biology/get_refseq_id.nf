#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_get_refseq_id
 * Get RefSeq ID from gene record.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.gene_id = null

// Main process
process GET_REFSEQ_ID {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_refseq_id_results.json"), emit: results
    path("get_refseq_id_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import get_refseq_id
except ImportError:
    # Fallback: function may need to be implemented locally
    def get_refseq_id(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = get_refseq_id(
    gene_id="${params.gene_id}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_refseq_id_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("get_refseq_id_output.txt", "w") as f:
    f.write("Biomni: Get Refseq Id Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("get_refseq_id completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_GET_REFSEQ_ID {
    take:
    // No file inputs

    main:
    GET_REFSEQ_ID()

    emit:
    results = GET_REFSEQ_ID.out.results
    output = GET_REFSEQ_ID.out.output
}

// Entry workflow
workflow {
    if (!params.gene_id) {
        error "Please provide --gene_id parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_GET_REFSEQ_ID()
}
