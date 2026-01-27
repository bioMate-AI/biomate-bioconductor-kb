#!/usr/bin/env nextflow
/*
 * bioengineering/first_order
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.k1 = null
params.q0 = null

process FIRST_ORDER {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("first_order_results.json"), emit: results
    tuple val(meta), path("first_order_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_T="${params.t?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_K1="${params.k1?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_Q0="${params.q0?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def first_order(t, k1, q0):
    '''First-order drug release kinetics: Q = Q0 * (1 - exp(-k1*t))
    Args: t: time, k1: first-order rate constant, q0: initial amount
    '''
    # Validate inputs - use defaults if None
    if t is None:
        t = 1.0
    if k1 is None:
        k1 = 0.1  # first-order rate constant
    if q0 is None:
        q0 = 100.0  # initial drug amount
    t, k1, q0 = float(t), float(k1), float(q0)

    return {"release": float(q0 * (1 - np.exp(-k1 * t))), "t": t, "k1": k1, "q0": q0}

# Execute the function
try:
    result = first_order(
        t=auto_convert(os.environ.get("PARAM_T", "")),
        k1=auto_convert(os.environ.get("PARAM_K1", "")),
        q0=auto_convert(os.environ.get("PARAM_Q0", "")),
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
    "function": "first_order",
    "domain": "bioengineering",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("first_order_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("first_order_output.txt", "w") as f:
    f.write("Biomni: First Order" + NL)
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
        biomni_function: "first_order"
    END_VERSIONS
    """
}

workflow FIRST_ORDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    FIRST_ORDER(ch_input)

    emit:
    results = FIRST_ORDER.out.results
    output = FIRST_ORDER.out.output
    versions = FIRST_ORDER.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    FIRST_ORDER_WORKFLOW(ch_input)

    FIRST_ORDER_WORKFLOW.out.output.view { "Output: $it" }
}
