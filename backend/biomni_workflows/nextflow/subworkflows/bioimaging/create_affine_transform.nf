#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_create_affine_transform
 * Create an affine transform for image registration.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.fixed_image = null
params.moving_image = null
params.initial_transform = null

// Main process
process CREATE_AFFINE_TRANSFORM {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("create_affine_transform_results.json"), emit: results
    path("create_affine_transform_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.bioimaging import create_affine_transform

# Run the tool
try:
    result = create_affine_transform(
    fixed_image="${params.fixed_image}",
    moving_image="${params.moving_image}",
    initial_transform="${params.initial_transform}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("create_affine_transform_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("create_affine_transform_output.txt", "w") as f:
    f.write("Biomni: Create Affine Transform Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("create_affine_transform completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_CREATE_AFFINE_TRANSFORM {
    take:
    // No file inputs

    main:
    CREATE_AFFINE_TRANSFORM()

    emit:
    results = CREATE_AFFINE_TRANSFORM.out.results
    output = CREATE_AFFINE_TRANSFORM.out.output
}

// Entry workflow
workflow {
    if (!params.fixed_image) {
        error "Please provide --fixed_image parameter"
    }
    if (!params.moving_image) {
        error "Please provide --moving_image parameter"
    }


    BIOMNI_BIOIMAGING_CREATE_AFFINE_TRANSFORM()
}
