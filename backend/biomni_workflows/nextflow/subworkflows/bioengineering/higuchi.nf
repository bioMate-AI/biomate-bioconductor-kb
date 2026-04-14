#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_higuchi
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.k = null

// Main process
process HIGUCHI {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("higuchi_results.json"), emit: results
    path("higuchi_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.bioengineering import higuchi

# Run the tool
try:
    result = higuchi(
    t="${params.t}",
    k="${params.k}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("higuchi_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("higuchi_output.txt", "w") as f:
    f.write("Biomni: Higuchi Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("higuchi completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOENGINEERING_HIGUCHI {
    take:
    // No file inputs

    main:
    HIGUCHI()

    emit:
    results = HIGUCHI.out.results
    output = HIGUCHI.out.output
}

// Entry workflow
workflow {
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.k) {
        error "Please provide --k parameter"
    }


    BIOMNI_BIOENGINEERING_HIGUCHI()
}
