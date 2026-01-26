#!/usr/bin/env nextflow
/*
 * bioimaging/prepare_input_for_nnunet
 * Prepare input data for nnUNet by handling both 4D and pre-split modality files
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.input_path = null
params.output_dir = null
params.case_name = 'BRAT'

process PREPARE_INPUT_FOR_NNUNET {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("prepare_input_for_nnunet_results.json"), emit: results
    tuple val(meta), path("prepare_input_for_nnunet_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_INPUT_PATH="${params.input_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CASE_NAME="${params.case_name?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os


class SegmentationTool:
    """Stub for SegmentationTool - requires nnU-Net."""
    def __init__(self):
        raise NotImplementedError("SegmentationTool requires nnU-Net and full biomni installation")


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



def prepare_input_for_nnunet(input_path, output_dir, case_name="BRAT"):
    '''Convenience function for preparing nnUNet input'''
    tool = SegmentationTool()
    return tool.prepare_input_for_nnunet(input_path, output_dir, case_name)

# Execute the function
try:
    result = prepare_input_for_nnunet(
        input_path=auto_convert(os.environ.get("PARAM_INPUT_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "")),
        case_name=auto_convert(os.environ.get("PARAM_CASE_NAME", "BRAT")),
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
    "function": "prepare_input_for_nnunet",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("prepare_input_for_nnunet_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("prepare_input_for_nnunet_output.txt", "w") as f:
    f.write("Biomni: Prepare Input For Nnunet" + NL)
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
        biomni_function: "prepare_input_for_nnunet"
    END_VERSIONS
    """
}

workflow PREPARE_INPUT_FOR_NNUNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PREPARE_INPUT_FOR_NNUNET(ch_input)

    emit:
    results = PREPARE_INPUT_FOR_NNUNET.out.results
    output = PREPARE_INPUT_FOR_NNUNET.out.output
    versions = PREPARE_INPUT_FOR_NNUNET.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PREPARE_INPUT_FOR_NNUNET_WORKFLOW(ch_input)

    PREPARE_INPUT_FOR_NNUNET_WORKFLOW.out.output.view { "Output: $it" }
}
