#!/usr/bin/env nextflow
/*
 * bioimaging/register_images
 * Perform image registration.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.fixed_image = null
params.moving_image = null
params.transform = null
params.registration_method = null

process REGISTER_IMAGES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("register_images_results.json"), emit: results
    tuple val(meta), path("register_images_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_FIXED_IMAGE="${params.fixed_image?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MOVING_IMAGE="${params.moving_image?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TRANSFORM="${params.transform?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_REGISTRATION_METHOD="${params.registration_method?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def register_images(**kwargs):
    '''Bioimaging helper: register_images
    Note: Actual implementation requires SimpleITK, nnUNet, or other imaging libraries.
    '''
    return {"function": "register_images", "status": "placeholder", "args": {k: str(v)[:100] for k, v in kwargs.items()},
            "note": "Requires imaging libraries (SimpleITK, nnUNet) for actual implementation"}

# Execute the function
try:
    result = register_images(
        fixed_image=auto_convert(os.environ.get("PARAM_FIXED_IMAGE", "")),
        moving_image=auto_convert(os.environ.get("PARAM_MOVING_IMAGE", "")),
        transform=auto_convert(os.environ.get("PARAM_TRANSFORM", "")),
        registration_method=auto_convert(os.environ.get("PARAM_REGISTRATION_METHOD", "")),
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
    "function": "register_images",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("register_images_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("register_images_output.txt", "w") as f:
    f.write("Biomni: Register Images" + NL)
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
        biomni_function: "register_images"
    END_VERSIONS
    """
}

workflow REGISTER_IMAGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    REGISTER_IMAGES(ch_input)

    emit:
    results = REGISTER_IMAGES.out.results
    output = REGISTER_IMAGES.out.output
    versions = REGISTER_IMAGES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    REGISTER_IMAGES_WORKFLOW(ch_input)

    REGISTER_IMAGES_WORKFLOW.out.output.view { "Output: $it" }
}
