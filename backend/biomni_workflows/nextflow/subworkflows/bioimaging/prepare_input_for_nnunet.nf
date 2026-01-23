#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_prepare_input_for_nnunet
 * Prepare input data for nnUNet by handling both 4D and pre-split modality files
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.input_path = null
params.output_dir = null
params.case_name = 'BRAT'

// Main process
process PREPARE_INPUT_FOR_NNUNET {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("prepare_input_for_nnunet_results.json"), emit: results
    path("prepare_input_for_nnunet_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.bioimaging import prepare_input_for_nnunet

# Run the tool
try:
    result = prepare_input_for_nnunet(
    input_path="${params.input_path}",
    output_dir="${params.output_dir}",
    case_name="${params.case_name}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("prepare_input_for_nnunet_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("prepare_input_for_nnunet_output.txt", "w") as f:
    f.write("Biomni: Prepare Input For Nnunet Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("prepare_input_for_nnunet completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_PREPARE_INPUT_FOR_NNUNET {
    take:
    // No file inputs

    main:
    PREPARE_INPUT_FOR_NNUNET()

    emit:
    results = PREPARE_INPUT_FOR_NNUNET.out.results
    output = PREPARE_INPUT_FOR_NNUNET.out.output
}

// Entry workflow
workflow {
    if (!params.input_path) {
        error "Please provide --input_path parameter"
    }
    if (!params.output_dir) {
        error "Please provide --output_dir parameter"
    }


    BIOMNI_BIOIMAGING_PREPARE_INPUT_FOR_NNUNET()
}
