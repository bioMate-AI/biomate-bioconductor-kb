#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_find_sequence_mutations
 * Compare query sequence against reference sequence to identify mutations.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.query_sequence = null
params.reference_sequence = null
params.query_start = '1'

// Main process
process FIND_SEQUENCE_MUTATIONS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("find_sequence_mutations_results.json"), emit: results
    path("find_sequence_mutations_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.molecular_biology import find_sequence_mutations

# Run the tool
try:
    result = find_sequence_mutations(
    query_sequence="${params.query_sequence}",
    reference_sequence="${params.reference_sequence}",
    query_start="${params.query_start}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("find_sequence_mutations_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("find_sequence_mutations_output.txt", "w") as f:
    f.write("Biomni: Find Sequence Mutations Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("find_sequence_mutations completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_FIND_SEQUENCE_MUTATIONS {
    take:
    // No file inputs

    main:
    FIND_SEQUENCE_MUTATIONS()

    emit:
    results = FIND_SEQUENCE_MUTATIONS.out.results
    output = FIND_SEQUENCE_MUTATIONS.out.output
}

// Entry workflow
workflow {
    if (!params.query_sequence) {
        error "Please provide --query_sequence parameter"
    }
    if (!params.reference_sequence) {
        error "Please provide --reference_sequence parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_FIND_SEQUENCE_MUTATIONS()
}
