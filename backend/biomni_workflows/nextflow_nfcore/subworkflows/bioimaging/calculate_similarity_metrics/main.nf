#!/usr/bin/env nextflow
/*
 * bioimaging/calculate_similarity_metrics
 * Calculate similarity metrics between two images.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image1_path = null
params.image2_path = null

process CALCULATE_SIMILARITY_METRICS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("calculate_similarity_metrics_results.json"), emit: results
    tuple val(meta), path("calculate_similarity_metrics_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_IMAGE1_PATH="${params.image1_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_IMAGE2_PATH="${params.image2_path?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def calculate_similarity_metrics(image1_path: str, image2_path: str) -> dict[str, float]:
    '''
    Calculate similarity metrics between two images.

    Args:
        image1_path: Path to first image
        image2_path: Path to second image

    Returns:
        Dictionary of similarity metrics
    '''
    tool = ImageRegistrationTool()
    image1 = tool.load_image(image1_path)
    image2 = tool.load_image(image2_path)
    return tool.calculate_similarity_metrics(image1, image2)

# Execute the function
try:
    result = calculate_similarity_metrics(
        image1_path=auto_convert(os.environ.get("PARAM_IMAGE1_PATH", "")),
        image2_path=auto_convert(os.environ.get("PARAM_IMAGE2_PATH", "")),
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
    "function": "calculate_similarity_metrics",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("calculate_similarity_metrics_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("calculate_similarity_metrics_output.txt", "w") as f:
    f.write("Biomni: Calculate Similarity Metrics" + NL)
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
        biomni_function: "calculate_similarity_metrics"
    END_VERSIONS
    """
}

workflow CALCULATE_SIMILARITY_METRICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CALCULATE_SIMILARITY_METRICS(ch_input)

    emit:
    results = CALCULATE_SIMILARITY_METRICS.out.results
    output = CALCULATE_SIMILARITY_METRICS.out.output
    versions = CALCULATE_SIMILARITY_METRICS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CALCULATE_SIMILARITY_METRICS_WORKFLOW(ch_input)

    CALCULATE_SIMILARITY_METRICS_WORKFLOW.out.output.view { "Output: $it" }
}
