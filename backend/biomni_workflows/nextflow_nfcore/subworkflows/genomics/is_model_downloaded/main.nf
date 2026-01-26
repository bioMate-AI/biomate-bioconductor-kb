#!/usr/bin/env nextflow
/*
 * genomics/is_model_downloaded
 * Check if model is already downloaded by looking for key files
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.checkpoint_path = null
params.model_type = null

process IS_MODEL_DOWNLOADED {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("is_model_downloaded_results.json"), emit: results
    tuple val(meta), path("is_model_downloaded_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_CHECKPOINT_PATH="${params.checkpoint_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MODEL_TYPE="${params.model_type?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def is_model_downloaded(**kwargs):
    '''Placeholder for is_model_downloaded. Actual implementation requires specific dependencies.
    '''
    return {"function": "is_model_downloaded", "status": "placeholder", "args": kwargs,
            "note": "This function requires specific dependencies not available in this context"}

# Execute the function
try:
    result = is_model_downloaded(
        checkpoint_path=auto_convert(os.environ.get("PARAM_CHECKPOINT_PATH", "")),
        model_type=auto_convert(os.environ.get("PARAM_MODEL_TYPE", "")),
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
    "function": "is_model_downloaded",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("is_model_downloaded_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("is_model_downloaded_output.txt", "w") as f:
    f.write("Biomni: Is Model Downloaded" + NL)
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
        biomni_function: "is_model_downloaded"
    END_VERSIONS
    """
}

workflow IS_MODEL_DOWNLOADED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    IS_MODEL_DOWNLOADED(ch_input)

    emit:
    results = IS_MODEL_DOWNLOADED.out.results
    output = IS_MODEL_DOWNLOADED.out.output
    versions = IS_MODEL_DOWNLOADED.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    IS_MODEL_DOWNLOADED_WORKFLOW(ch_input)

    IS_MODEL_DOWNLOADED_WORKFLOW.out.output.view { "Output: $it" }
}
