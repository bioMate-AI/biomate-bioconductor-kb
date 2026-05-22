#!/usr/bin/env nextflow
/*
 * biochemistry/dose_response
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.x = null
params.ic50 = null
params.hill = null

process DOSE_RESPONSE {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("dose_response_results.json"), emit: results
    tuple val(meta), path("dose_response_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_X="${params.x?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_IC50="${params.ic50?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_HILL="${params.hill?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def dose_response(x, ic50, hill):
    '''Dose-response curve (Hill equation).

    Args:
        x: Concentration/dose
        ic50: Half-maximal inhibitory concentration
        hill: Hill coefficient (slope)

    Returns:
        Response value (0-1 scale, 1 = no inhibition, 0 = full inhibition)
    '''
    # Validate inputs - use defaults if None
    if x is None:
        x = 1.0
    if ic50 is None:
        ic50 = 50.0
    if hill is None:
        hill = 1.0
    x, ic50, hill = float(x), float(ic50), float(hill)

    response = 1 / (1 + (x / ic50) ** hill) if ic50 != 0 else 0
    return {"response": float(response), "x": x, "ic50": ic50, "hill": hill}

# Execute the function
try:
    result = dose_response(
        x=auto_convert(os.environ.get("PARAM_X", "")),
        ic50=auto_convert(os.environ.get("PARAM_IC50", "")),
        hill=auto_convert(os.environ.get("PARAM_HILL", "")),
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
    "function": "dose_response",
    "domain": "biochemistry",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("dose_response_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("dose_response_output.txt", "w") as f:
    f.write("Biomni: Dose Response" + NL)
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
        biomni_function: "dose_response"
    END_VERSIONS
    """
}

workflow DOSE_RESPONSE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    DOSE_RESPONSE(ch_input)

    emit:
    results = DOSE_RESPONSE.out.results
    output = DOSE_RESPONSE.out.output
    versions = DOSE_RESPONSE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    DOSE_RESPONSE_WORKFLOW(ch_input)

    DOSE_RESPONSE_WORKFLOW.out.output.view { "Output: $it" }
}
