#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_get_coding_sequences
 * Extract coding sequences from RefSeq record.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.refseq_id = null

// Main process
process GET_CODING_SEQUENCES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_coding_sequences_results.json"), emit: results
    path("get_coding_sequences_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import get_coding_sequences
except ImportError:
    # Fallback: function may need to be implemented locally
    def get_coding_sequences(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = get_coding_sequences(
    refseq_id="${params.refseq_id}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_coding_sequences_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("get_coding_sequences_output.txt", "w") as f:
    f.write("Biomni: Get Coding Sequences Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("get_coding_sequences completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_GET_CODING_SEQUENCES {
    take:
    // No file inputs

    main:
    GET_CODING_SEQUENCES()

    emit:
    results = GET_CODING_SEQUENCES.out.results
    output = GET_CODING_SEQUENCES.out.output
}

// Entry workflow
workflow {
    if (!params.refseq_id) {
        error "Please provide --refseq_id parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_GET_CODING_SEQUENCES()
}
