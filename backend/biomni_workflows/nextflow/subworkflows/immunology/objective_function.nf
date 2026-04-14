#!/usr/bin/env nextflow
/*
 * biomni_immunology_objective_function
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.params = null

// Main process
process OBJECTIVE_FUNCTION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("objective_function_results.json"), emit: results
    path("objective_function_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.immunology import objective_function

# Run the tool
try:
    result = objective_function(
    params="${params.params}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("objective_function_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("objective_function_output.txt", "w") as f:
    f.write("Biomni: Objective Function Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("objective_function completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_IMMUNOLOGY_OBJECTIVE_FUNCTION {
    take:
    // No file inputs

    main:
    OBJECTIVE_FUNCTION()

    emit:
    results = OBJECTIVE_FUNCTION.out.results
    output = OBJECTIVE_FUNCTION.out.output
}

// Entry workflow
workflow {
    if (!params.params) {
        error "Please provide --params parameter"
    }


    BIOMNI_IMMUNOLOGY_OBJECTIVE_FUNCTION()
}
