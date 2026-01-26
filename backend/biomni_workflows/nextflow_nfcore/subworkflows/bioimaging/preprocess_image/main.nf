#!/usr/bin/env nextflow
/*
 * bioimaging/preprocess_image
 * Preprocess an image with denoising and normalization.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.output_path = null
params.denoise = null
params.normalize = null

process PREPROCESS_IMAGE {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("preprocess_image_results.json"), emit: results
    tuple val(meta), path("preprocess_image_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_IMAGE_PATH="${params.image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_PATH="${params.output_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DENOISE="${params.denoise?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NORMALIZE="${params.normalize?.toString()?.replace('"', '\\"') ?: 'null'}"


    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os


class ImageRegistrationTool:
    """Stub for ImageRegistrationTool - requires SimpleITK."""
    def __init__(self):
        raise NotImplementedError("ImageRegistrationTool requires SimpleITK and full biomni installation")
    def load_image(self, path):
        pass
    def calculate_similarity_metrics(self, img1, img2):
        return {"error": "ImageRegistrationTool not available"}


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



def preprocess_image(image_path: str, output_path: str, denoise: bool = True, normalize: bool = True) -> str:
    '''
    Standalone image preprocessing function for Biomni integration.

    Args:
        image_path: Path to input image
        output_path: Path to save preprocessed image
        denoise: Whether to apply denoising (default: True)
        normalize: Whether to apply normalization (default: True)

    Returns:
        Path to the saved preprocessed image
    '''
    tool = ImageRegistrationTool()
    image = tool.load_image(image_path)
    preprocessed_image = tool.preprocess_image(image, denoise, normalize)
    tool.save_image(preprocessed_image, output_path)
    return output_path

# Execute the function
try:
    result = preprocess_image(
        image_path=auto_convert(os.environ.get("PARAM_IMAGE_PATH", "")),
        output_path=auto_convert(os.environ.get("PARAM_OUTPUT_PATH", "")),
        denoise=auto_convert(os.environ.get("PARAM_DENOISE", "")),
        normalize=auto_convert(os.environ.get("PARAM_NORMALIZE", "")),
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
    "function": "preprocess_image",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("preprocess_image_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("preprocess_image_output.txt", "w") as f:
    f.write("Biomni: Preprocess Image" + NL)
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
        biomni_function: "preprocess_image"
    END_VERSIONS
    """
}

workflow PREPROCESS_IMAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PREPROCESS_IMAGE(ch_input)

    emit:
    results = PREPROCESS_IMAGE.out.results
    output = PREPROCESS_IMAGE.out.output
    versions = PREPROCESS_IMAGE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PREPROCESS_IMAGE_WORKFLOW(ch_input)

    PREPROCESS_IMAGE_WORKFLOW.out.output.view { "Output: $it" }
}
