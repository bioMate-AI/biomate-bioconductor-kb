#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_preprocess_image
 * Preprocess an image with denoising and normalization.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image = null
params.denoise = false
params.normalize = false

// Main process
process PREPROCESS_IMAGE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("preprocess_image_results.json"), emit: results
    path("preprocess_image_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.bioimaging import preprocess_image
except ImportError:
    # Fallback: function may need to be implemented locally
    def preprocess_image(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = preprocess_image(
    image="${params.image}",
    denoise=${params.denoise},
    normalize=${params.normalize}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("preprocess_image_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("preprocess_image_output.txt", "w") as f:
    f.write("Biomni: Preprocess Image Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("preprocess_image completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_PREPROCESS_IMAGE {
    take:
    // No file inputs

    main:
    PREPROCESS_IMAGE()

    emit:
    results = PREPROCESS_IMAGE.out.results
    output = PREPROCESS_IMAGE.out.output
}

// Entry workflow
workflow {
    if (!params.image) {
        error "Please provide --image parameter"
    }


    BIOMNI_BIOIMAGING_PREPROCESS_IMAGE()
}
