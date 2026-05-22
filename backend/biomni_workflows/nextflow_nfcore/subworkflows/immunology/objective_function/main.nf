#!/usr/bin/env nextflow
/*
 * immunology/objective_function
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: objective function parameters for model fitting
params.params = '[1.0, 2.0, 3.0]'
params.data = '[1.0, 2.0, 3.0]'
params.model_type = 'sum_squared'

process OBJECTIVE_FUNCTION {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("objective_function_results.json"), emit: results
    tuple val(meta), path("objective_function_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_PARAMS="${params.params?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA="${params.data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MODEL_TYPE="${params.model_type?.toString()?.replace('"', '\\"') ?: 'null'}"


    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import numpy as np
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



def objective_function(params, data, model_type="sum_squared"):
    '''Objective function for fitting.
    Args: params: model parameters, data: observed values, model_type: SSE or other
    '''
    # Validate inputs - use defaults if None
    if params is None:
        params = [1.0, 2.0, 3.0]
    if data is None:
        data = [1.0, 2.0, 3.0]
    if model_type is None:
        model_type = "sum_squared"

    if isinstance(params, str):
        params = [float(x.strip()) for x in params.split(',')]
    if isinstance(data, str):
        data = [float(x.strip()) for x in data.split(',')]
    # Simple SSE
    residuals = np.array(data) - np.array(params[:len(data)])
    sse = np.sum(residuals**2)
    return {"objective": float(sse), "residuals": residuals.tolist()}

# Execute the function
try:
    result = objective_function(
        params=auto_convert(os.environ.get("PARAM_PARAMS", "")),
        data=auto_convert(os.environ.get("PARAM_DATA", "")),
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
    "function": "objective_function",
    "domain": "immunology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("objective_function_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("objective_function_output.txt", "w") as f:
    f.write("Biomni: Objective Function" + NL)
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
        biomni_function: "objective_function"
    END_VERSIONS
    """
}

workflow OBJECTIVE_FUNCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    OBJECTIVE_FUNCTION(ch_input)

    emit:
    results = OBJECTIVE_FUNCTION.out.results
    output = OBJECTIVE_FUNCTION.out.output
    versions = OBJECTIVE_FUNCTION.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    OBJECTIVE_FUNCTION_WORKFLOW(ch_input)

    OBJECTIVE_FUNCTION_WORKFLOW.out.output.view { "Output: $it" }
}
