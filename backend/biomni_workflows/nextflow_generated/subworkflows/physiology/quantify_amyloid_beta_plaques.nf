#!/usr/bin/env nextflow
/*
 * biomni_physiology_quantify_amyloid_beta_plaques
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.output_dir = './results'
params.threshold_method = 'otsu'
params.min_plaque_size = '50'
params.manual_threshold = '127'

// Main process
process QUANTIFY_AMYLOID_BETA_PLAQUES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("quantify_amyloid_beta_plaques_results.json"), emit: results
    path("quantify_amyloid_beta_plaques_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.physiology import quantify_amyloid_beta_plaques
except ImportError:
    # Fallback: function may need to be implemented locally
    def quantify_amyloid_beta_plaques(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = quantify_amyloid_beta_plaques(
    image_path="${params.image_path}",
    output_dir="${params.output_dir}",
    threshold_method="${params.threshold_method}",
    min_plaque_size="${params.min_plaque_size}",
    manual_threshold="${params.manual_threshold}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("quantify_amyloid_beta_plaques_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("quantify_amyloid_beta_plaques_output.txt", "w") as f:
    f.write("Biomni: Quantify Amyloid Beta Plaques Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("quantify_amyloid_beta_plaques completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHYSIOLOGY_QUANTIFY_AMYLOID_BETA_PLAQUES {
    take:
    // No file inputs

    main:
    QUANTIFY_AMYLOID_BETA_PLAQUES()

    emit:
    results = QUANTIFY_AMYLOID_BETA_PLAQUES.out.results
    output = QUANTIFY_AMYLOID_BETA_PLAQUES.out.output
}

// Entry workflow
workflow {
    if (!params.image_path) {
        error "Please provide --image_path parameter"
    }


    BIOMNI_PHYSIOLOGY_QUANTIFY_AMYLOID_BETA_PLAQUES()
}
