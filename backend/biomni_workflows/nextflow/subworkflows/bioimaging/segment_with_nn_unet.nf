#!/usr/bin/env nextflow
/*
 * biomni_bioimaging_segment_with_nn_unet
 * Segment images using nnUNet with proper environment setup and automatic model downloading
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.output_dir = null
params.task_id = null
params.model_type = '3d_fullres'
params.folds = null
params.use_tta = 'False'
params.num_threads = '1'
params.mixed_precision = 'True'
params.verbose = 'True'
params.auto_prepare_input = 'True'
params.results_folder = null
params.auto_download = 'True'

// Main process
process SEGMENT_WITH_NN_UNET {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("segment_with_nn_unet_results.json"), emit: results
    path("segment_with_nn_unet_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.bioimaging import segment_with_nn_unet

# Run the tool
try:
    result = segment_with_nn_unet(
    image_path="${params.image_path}",
    output_dir="${params.output_dir}",
    task_id="${params.task_id}",
    model_type="${params.model_type}",
    folds="${params.folds}",
    use_tta="${params.use_tta}",
    num_threads="${params.num_threads}",
    mixed_precision="${params.mixed_precision}",
    verbose="${params.verbose}",
    auto_prepare_input="${params.auto_prepare_input}",
    results_folder="${params.results_folder}",
    auto_download="${params.auto_download}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("segment_with_nn_unet_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("segment_with_nn_unet_output.txt", "w") as f:
    f.write("Biomni: Segment With Nn Unet Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("segment_with_nn_unet completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOIMAGING_SEGMENT_WITH_NN_UNET {
    take:
    // No file inputs

    main:
    SEGMENT_WITH_NN_UNET()

    emit:
    results = SEGMENT_WITH_NN_UNET.out.results
    output = SEGMENT_WITH_NN_UNET.out.output
}

// Entry workflow
workflow {
    if (!params.image_path) {
        error "Please provide --image_path parameter"
    }
    if (!params.output_dir) {
        error "Please provide --output_dir parameter"
    }
    if (!params.task_id) {
        error "Please provide --task_id parameter"
    }


    BIOMNI_BIOIMAGING_SEGMENT_WITH_NN_UNET()
}
