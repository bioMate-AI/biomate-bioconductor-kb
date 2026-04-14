#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_reverse_complement
 * Get the reverse complement of a DNA sequence.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.seq = null

// Main process
process REVERSE_COMPLEMENT {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("reverse_complement_results.json"), emit: results
    path("reverse_complement_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.molecular_biology import reverse_complement

# Run the tool
try:
    result = reverse_complement(
    seq="${params.seq}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("reverse_complement_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("reverse_complement_output.txt", "w") as f:
    f.write("Biomni: Reverse Complement Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("reverse_complement completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_REVERSE_COMPLEMENT {
    take:
    // No file inputs

    main:
    REVERSE_COMPLEMENT()

    emit:
    results = REVERSE_COMPLEMENT.out.results
    output = REVERSE_COMPLEMENT.out.output
}

// Entry workflow
workflow {
    if (!params.seq) {
        error "Please provide --seq parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_REVERSE_COMPLEMENT()
}
