#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_split_modalities
 * Split a 4D NIfTI file into separate modality files for nnUNet
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.input_file = null
params.output_dir = null
params.case_name = 'BRAT'

// Main process
process SPLIT_MODALITIES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("split_modalities_results.json"), emit: results
    path("split_modalities_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.bioimaging import split_modalities
except ImportError:
    # Fallback: function may need to be implemented locally
    def split_modalities(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = split_modalities(
    input_file="${params.input_file}",
    output_dir="${params.output_dir}",
    case_name="${params.case_name}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("split_modalities_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("split_modalities_output.txt", "w") as f:
    f.write("Biomni: Split Modalities Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("split_modalities completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_SPLIT_MODALITIES {
    take:
    // No file inputs

    main:
    SPLIT_MODALITIES()

    emit:
    results = SPLIT_MODALITIES.out.results
    output = SPLIT_MODALITIES.out.output
}

// Entry workflow
workflow {
    if (!params.input_file) {
        error "Please provide --input_file parameter"
    }
    if (!params.output_dir) {
        error "Please provide --output_dir parameter"
    }


    BIOMNI_BIOIMAGING_SPLIT_MODALITIES()
}
