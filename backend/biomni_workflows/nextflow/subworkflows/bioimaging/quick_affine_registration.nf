#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_quick_affine_registration
 * Quick affine registration function for Biomni integration.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.fixed_image_path = null
params.moving_image_path = null
params.output_dir = null
params.metric = 'mutual_information'
params.optimizer = 'gradient_descent'
params.preprocess = false
params.create_visualizations = false
params.learning_rate = 0.01
params.number_of_iterations = 100
params.gradient_convergence_tolerance = 1e-06

// Main process
process QUICK_AFFINE_REGISTRATION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("quick_affine_registration_results.json"), emit: results
    path("quick_affine_registration_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.bioimaging import quick_affine_registration

# Run the tool
try:
    result = quick_affine_registration(
    fixed_image_path="${params.fixed_image_path}",
    moving_image_path="${params.moving_image_path}",
    output_dir="${params.output_dir}",
    metric="${params.metric}",
    optimizer="${params.optimizer}",
    preprocess=${params.preprocess ? "True" : "False"},
    create_visualizations=${params.create_visualizations ? "True" : "False"},
    learning_rate=${params.learning_rate},
    number_of_iterations=${params.number_of_iterations},
    gradient_convergence_tolerance=${params.gradient_convergence_tolerance}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("quick_affine_registration_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("quick_affine_registration_output.txt", "w") as f:
    f.write("Biomni: Quick Affine Registration Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("quick_affine_registration completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_QUICK_AFFINE_REGISTRATION {
    take:
    // No file inputs

    main:
    QUICK_AFFINE_REGISTRATION()

    emit:
    results = QUICK_AFFINE_REGISTRATION.out.results
    output = QUICK_AFFINE_REGISTRATION.out.output
}

// Entry workflow
workflow {
    if (!params.fixed_image_path) {
        error "Please provide --fixed_image_path parameter"
    }
    if (!params.moving_image_path) {
        error "Please provide --moving_image_path parameter"
    }
    if (!params.output_dir) {
        error "Please provide --output_dir parameter"
    }


    BIOMNI_BIOIMAGING_QUICK_AFFINE_REGISTRATION()
}
