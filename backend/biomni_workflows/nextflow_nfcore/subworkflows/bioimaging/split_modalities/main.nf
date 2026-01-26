#!/usr/bin/env nextflow
/*
 * bioimaging/split_modalities
 * Split a 4D NIfTI file into separate modality files for nnUNet
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.input_file = null
params.output_dir = null
params.case_name = 'BRAT'

process SPLIT_MODALITIES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("split_modalities_results.json"), emit: results
    tuple val(meta), path("split_modalities_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_INPUT_FILE="${params.input_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CASE_NAME="${params.case_name?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def split_modalities(input_file, output_dir, case_name="BRAT"):
    '''Convenience function for splitting modalities'''
    tool = SegmentationTool()
    return tool.split_modalities(input_file, output_dir, case_name)

# Execute the function
try:
    result = split_modalities(
        input_file=auto_convert(os.environ.get("PARAM_INPUT_FILE", "")),
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
    "function": "split_modalities",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("split_modalities_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("split_modalities_output.txt", "w") as f:
    f.write("Biomni: Split Modalities" + NL)
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
        biomni_function: "split_modalities"
    END_VERSIONS
    """
}

workflow SPLIT_MODALITIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SPLIT_MODALITIES(ch_input)

    emit:
    results = SPLIT_MODALITIES.out.results
    output = SPLIT_MODALITIES.out.output
    versions = SPLIT_MODALITIES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SPLIT_MODALITIES_WORKFLOW(ch_input)

    SPLIT_MODALITIES_WORKFLOW.out.output.view { "Output: $it" }
}
