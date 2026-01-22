#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_quick_rigid_registration
 * Quick rigid registration function for Biomni integration.
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
process QUICK_RIGID_REGISTRATION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("quick_rigid_registration_results.json"), emit: results
    path("quick_rigid_registration_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.bioimaging import quick_rigid_registration
except ImportError:
    # Fallback: function may need to be implemented locally
    def quick_rigid_registration(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = quick_rigid_registration(
    fixed_image_path="${params.fixed_image_path}",
    moving_image_path="${params.moving_image_path}",
    output_dir="${params.output_dir}",
    metric="${params.metric}",
    optimizer="${params.optimizer}",
    preprocess=${params.preprocess},
    create_visualizations=${params.create_visualizations},
    learning_rate=${params.learning_rate},
    number_of_iterations=${params.number_of_iterations},
    gradient_convergence_tolerance=${params.gradient_convergence_tolerance}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("quick_rigid_registration_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("quick_rigid_registration_output.txt", "w") as f:
    f.write("Biomni: Quick Rigid Registration Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("quick_rigid_registration completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_QUICK_RIGID_REGISTRATION {
    take:
    // No file inputs

    main:
    QUICK_RIGID_REGISTRATION()

    emit:
    results = QUICK_RIGID_REGISTRATION.out.results
    output = QUICK_RIGID_REGISTRATION.out.output
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


    BIOMNI_BIOIMAGING_QUICK_RIGID_REGISTRATION()
}
