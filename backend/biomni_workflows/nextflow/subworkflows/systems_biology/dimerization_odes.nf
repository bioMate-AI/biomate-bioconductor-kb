#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_dimerization_odes
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.y = null

// Main process
process DIMERIZATION_ODES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("dimerization_odes_results.json"), emit: results
    path("dimerization_odes_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.systems_biology import dimerization_odes

# Run the tool
try:
    result = dimerization_odes(
    t="${params.t}",
    y="${params.y}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("dimerization_odes_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("dimerization_odes_output.txt", "w") as f:
    f.write("Biomni: Dimerization Odes Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("dimerization_odes completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYSTEMS_BIOLOGY_DIMERIZATION_ODES {
    take:
    // No file inputs

    main:
    DIMERIZATION_ODES()

    emit:
    results = DIMERIZATION_ODES.out.results
    output = DIMERIZATION_ODES.out.output
}

// Entry workflow
workflow {
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.y) {
        error "Please provide --y parameter"
    }


    BIOMNI_SYSTEMS_BIOLOGY_DIMERIZATION_ODES()
}
