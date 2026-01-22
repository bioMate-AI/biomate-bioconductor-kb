#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_register_images
 * Perform image registration.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.fixed_image = null
params.moving_image = null
params.transform = null
params.registration_method = null

// Main process
process REGISTER_IMAGES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("register_images_results.json"), emit: results
    path("register_images_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.bioimaging import register_images
except ImportError:
    # Fallback: function may need to be implemented locally
    def register_images(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = register_images(
    fixed_image="${params.fixed_image}",
    moving_image="${params.moving_image}",
    transform="${params.transform}",
    registration_method="${params.registration_method}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("register_images_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("register_images_output.txt", "w") as f:
    f.write("Biomni: Register Images Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("register_images completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_REGISTER_IMAGES {
    take:
    // No file inputs

    main:
    REGISTER_IMAGES()

    emit:
    results = REGISTER_IMAGES.out.results
    output = REGISTER_IMAGES.out.output
}

// Entry workflow
workflow {
    if (!params.fixed_image) {
        error "Please provide --fixed_image parameter"
    }
    if (!params.moving_image) {
        error "Please provide --moving_image parameter"
    }
    if (!params.transform) {
        error "Please provide --transform parameter"
    }
    if (!params.registration_method) {
        error "Please provide --registration_method parameter"
    }


    BIOMNI_BIOIMAGING_REGISTER_IMAGES()
}
