#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_find_restriction_enzymes
 * Finds common restriction enzyme sites in a DNA sequence.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sequence = null
params.is_circular = false

// Main process
process FIND_RESTRICTION_ENZYMES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("find_restriction_enzymes_results.json"), emit: results
    path("find_restriction_enzymes_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.molecular_biology import find_restriction_enzymes

# Run the tool
try:
    result = find_restriction_enzymes(
    sequence="${params.sequence}",
    is_circular=${params.is_circular ? "True" : "False"}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("find_restriction_enzymes_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("find_restriction_enzymes_output.txt", "w") as f:
    f.write("Biomni: Find Restriction Enzymes Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("find_restriction_enzymes completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_FIND_RESTRICTION_ENZYMES {
    take:
    // No file inputs

    main:
    FIND_RESTRICTION_ENZYMES()

    emit:
    results = FIND_RESTRICTION_ENZYMES.out.results
    output = FIND_RESTRICTION_ENZYMES.out.output
}

// Entry workflow
workflow {
    if (!params.sequence) {
        error "Please provide --sequence parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_FIND_RESTRICTION_ENZYMES()
}
