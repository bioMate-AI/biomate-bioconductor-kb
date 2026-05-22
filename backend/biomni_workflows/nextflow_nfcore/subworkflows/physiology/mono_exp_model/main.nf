#!/usr/bin/env nextflow
/*
 * physiology/mono_exp_model
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Mono-exponential decay model parameters
params.t = '1.0'
params.a = '100.0'
params.k = '0.1'

process MONO_EXP_MODEL {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("mono_exp_model_results.json"), emit: results
    tuple val(meta), path("mono_exp_model_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_T="${params.t?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_A="${params.a?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_K="${params.k?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def mono_exp_model(t, a, k):
    '''Mono-exponential: y = A * exp(-k*t)
    Args: t: time, a: initial value, k: rate constant
    '''
    # Validate inputs - use defaults if None
    if t is None:
        t = 1.0
    if a is None:
        a = 100.0
    if k is None:
        k = 0.1
    t, a, k = float(t), float(a), float(k)

    y = a * np.exp(-k * t)
    return {"value": float(y), "t": t, "a": a, "k": k}

# Execute the function
try:
    result = mono_exp_model(
        t=auto_convert(os.environ.get("PARAM_T", "")),
        a=auto_convert(os.environ.get("PARAM_A", "")),
        k=auto_convert(os.environ.get("PARAM_K", "")),
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
    "function": "mono_exp_model",
    "domain": "physiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("mono_exp_model_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("mono_exp_model_output.txt", "w") as f:
    f.write("Biomni: Mono Exp Model" + NL)
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
        biomni_function: "mono_exp_model"
    END_VERSIONS
    """
}

workflow MONO_EXP_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    MONO_EXP_MODEL(ch_input)

    emit:
    results = MONO_EXP_MODEL.out.results
    output = MONO_EXP_MODEL.out.output
    versions = MONO_EXP_MODEL.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    MONO_EXP_MODEL_WORKFLOW(ch_input)

    MONO_EXP_MODEL_WORKFLOW.out.output.view { "Output: $it" }
}
