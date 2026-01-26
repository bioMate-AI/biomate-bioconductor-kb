#!/usr/bin/env nextflow
/*
 * bioimaging/segment_with_nn_unet
 * Segment images using nnUNet with proper environment setup and automatic model downloading
 *
 * nf-core style module generated from tested Galaxy wrapper
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

process SEGMENT_WITH_NN_UNET {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("segment_with_nn_unet_results.json"), emit: results
    tuple val(meta), path("segment_with_nn_unet_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_PATH="${params.image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TASK_ID="${params.task_id?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MODEL_TYPE="${params.model_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FOLDS="${params.folds?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_USE_TTA="${params.use_tta?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NUM_THREADS="${params.num_threads?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MIXED_PRECISION="${params.mixed_precision?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_VERBOSE="${params.verbose?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_AUTO_PREPARE_INPUT="${params.auto_prepare_input?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_RESULTS_FOLDER="${params.results_folder?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_AUTO_DOWNLOAD="${params.auto_download?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os

def auto_convert(val):
    # Auto-convert string to appropriate type
    if val is None or val == '' or val == 'null':
        return None
    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    # Try float
    try:
        return float(val)
    except ValueError:
        pass
    # Return as string
    return val



def segment_with_nn_unet(
    image_path,
    output_dir,
    task_id,
    model_type="3d_fullres",
    folds=None,
    use_tta=False,
    num_threads=1,
    mixed_precision=True,
    verbose=True,
    auto_prepare_input=True,
    results_folder=None,
):
    '''Convenience function for nnUNet segmentation'''
    tool = SegmentationTool()
    return tool.segment_with_nn_unet(
        image_path,
        output_dir,
        task_id,
        model_type,
        folds,
        use_tta,
        num_threads,
        mixed_precision,
        verbose,
        auto_prepare_input,
        results_folder,
    )

# Execute the function
try:
    result = segment_with_nn_unet(
        image_path=auto_convert(os.environ.get("PARAM_IMAGE_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "")),
        task_id=auto_convert(os.environ.get("PARAM_TASK_ID", "")),
        model_type=auto_convert(os.environ.get("PARAM_MODEL_TYPE", "3d_fullres")),
        folds=auto_convert(os.environ.get("PARAM_FOLDS", "")),
        use_tta=auto_convert(os.environ.get("PARAM_USE_TTA", "False")),
        num_threads=auto_convert(os.environ.get("PARAM_NUM_THREADS", "1")),
        mixed_precision=auto_convert(os.environ.get("PARAM_MIXED_PRECISION", "True")),
        verbose=auto_convert(os.environ.get("PARAM_VERBOSE", "True")),
        auto_prepare_input=auto_convert(os.environ.get("PARAM_AUTO_PREPARE_INPUT", "True")),
        results_folder=auto_convert(os.environ.get("PARAM_RESULTS_FOLDER", "")),
        auto_download=auto_convert(os.environ.get("PARAM_AUTO_DOWNLOAD", "True")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "segment_with_nn_unet",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("segment_with_nn_unet_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("segment_with_nn_unet_output.txt", "w") as f:
    f.write("Biomni: Segment With Nn Unet" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "segment_with_nn_unet"
    END_VERSIONS
    """
}

workflow SEGMENT_WITH_NN_UNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SEGMENT_WITH_NN_UNET(ch_input)

    emit:
    results = SEGMENT_WITH_NN_UNET.out.results
    output = SEGMENT_WITH_NN_UNET.out.output
    versions = SEGMENT_WITH_NN_UNET.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SEGMENT_WITH_NN_UNET_WORKFLOW(ch_input)

    SEGMENT_WITH_NN_UNET_WORKFLOW.out.output.view { "Output: $it" }
}
