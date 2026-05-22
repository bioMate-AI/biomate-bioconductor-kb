#!/usr/bin/env nextflow
/*
 * genetics/forward
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Simple neural network forward pass for genetics feature prediction
params.x = '[1.0, 2.0, 3.0]'
params.weights = '[[0.5, 0.3, 0.2], [0.1, 0.4, 0.5]]'
params.bias = '[0.1, 0.2]'
params.activation = 'relu'

process FORWARD {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("forward_results.json"), emit: results
    tuple val(meta), path("forward_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_X="${params.x?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_WEIGHTS="${params.weights?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BIAS="${params.bias?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ACTIVATION="${params.activation?.toString()?.replace('"', '\\"') ?: 'null'}"


    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import numpy as np
import json
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



def forward(x, weights, bias, activation="relu"):
    '''Simple forward pass: y = activation(W*x + b)
    Args: x: input (comma-sep), weights: matrix (JSON), bias: vector (comma-sep), activation: relu/sigmoid/tanh
    '''
    # Validate inputs - use defaults if None
    if x is None:
        x = [1.0, 1.0]
    if weights is None:
        weights = [[1.0, 0.0], [0.0, 1.0]]  # identity matrix
    if bias is None:
        bias = [0.0, 0.0]
    if activation is None:
        activation = "relu"

    if isinstance(x, str):
        x = np.array([float(v.strip()) for v in x.split(',')])
    elif isinstance(x, list):
        x = np.array(x)
    if isinstance(weights, str):
        weights = np.array(json.loads(weights))
    elif isinstance(weights, list):
        weights = np.array(weights)
    if isinstance(bias, str):
        bias = np.array([float(v.strip()) for v in bias.split(',')])
    elif isinstance(bias, list):
        bias = np.array(bias)
    
    z = np.dot(weights, x) + bias
    if activation == "relu":
        y = np.maximum(0, z)
    elif activation == "sigmoid":
        y = 1 / (1 + np.exp(-z))
    elif activation == "tanh":
        y = np.tanh(z)
    else:
        y = z
    return {"output": y.tolist(), "pre_activation": z.tolist()}

# Execute the function
try:
    result = forward(
        x=auto_convert(os.environ.get("PARAM_X", "")),
        weights=auto_convert(os.environ.get("PARAM_WEIGHTS", "")),
        bias=auto_convert(os.environ.get("PARAM_BIAS", "")),
        activation=auto_convert(os.environ.get("PARAM_ACTIVATION", "")),
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
    "function": "forward",
    "domain": "genetics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("forward_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("forward_output.txt", "w") as f:
    f.write("Biomni: Forward" + NL)
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
        biomni_function: "forward"
    END_VERSIONS
    """
}

workflow FORWARD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    FORWARD(ch_input)

    emit:
    results = FORWARD.out.results
    output = FORWARD.out.output
    versions = FORWARD.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    FORWARD_WORKFLOW(ch_input)

    FORWARD_WORKFLOW.out.output.view { "Output: $it" }
}
