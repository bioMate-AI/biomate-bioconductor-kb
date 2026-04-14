#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_setup_registration_method
 * Setup the registration method with specified parameters.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.transform = null
params.metric = 'mutual_information'
params.optimizer = 'gradient_descent'
params.learning_rate = 0.01
params.number_of_iterations = 100
params.gradient_convergence_tolerance = 1e-06

// Main process
process SETUP_REGISTRATION_METHOD {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("setup_registration_method_results.json"), emit: results
    path("setup_registration_method_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.bioimaging import setup_registration_method

# Run the tool
try:
    result = setup_registration_method(
    transform="${params.transform}",
    metric="${params.metric}",
    optimizer="${params.optimizer}",
    learning_rate=${params.learning_rate},
    number_of_iterations=${params.number_of_iterations},
    gradient_convergence_tolerance=${params.gradient_convergence_tolerance}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("setup_registration_method_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("setup_registration_method_output.txt", "w") as f:
    f.write("Biomni: Setup Registration Method Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("setup_registration_method completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_SETUP_REGISTRATION_METHOD {
    take:
    // No file inputs

    main:
    SETUP_REGISTRATION_METHOD()

    emit:
    results = SETUP_REGISTRATION_METHOD.out.results
    output = SETUP_REGISTRATION_METHOD.out.output
}

// Entry workflow
workflow {
    if (!params.transform) {
        error "Please provide --transform parameter"
    }


    BIOMNI_BIOIMAGING_SETUP_REGISTRATION_METHOD()
}
