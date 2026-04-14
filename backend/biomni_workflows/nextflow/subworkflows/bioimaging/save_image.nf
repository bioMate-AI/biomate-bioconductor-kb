#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_save_image
 * Save a SimpleITK image to file.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image = null
params.output_path = null

// Main process
process SAVE_IMAGE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("save_image_results.json"), emit: results
    path("save_image_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.bioimaging import save_image

# Run the tool
try:
    result = save_image(
    image="${params.image}",
    output_path="${params.output_path}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("save_image_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("save_image_output.txt", "w") as f:
    f.write("Biomni: Save Image Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("save_image completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_SAVE_IMAGE {
    take:
    // No file inputs

    main:
    SAVE_IMAGE()

    emit:
    results = SAVE_IMAGE.out.results
    output = SAVE_IMAGE.out.output
}

// Entry workflow
workflow {
    if (!params.image) {
        error "Please provide --image parameter"
    }
    if (!params.output_path) {
        error "Please provide --output_path parameter"
    }


    BIOMNI_BIOIMAGING_SAVE_IMAGE()
}
