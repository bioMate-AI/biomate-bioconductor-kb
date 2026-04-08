#!/usr/bin/env nextflow
/*
 * bioengineering/zero_order
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Zero-order drug release kinetics parameters
params.t = '5.0'
params.k0 = '10.0'

process ZERO_ORDER {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("zero_order_results.json"), emit: results
    tuple val(meta), path("zero_order_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_T="${params.t?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_K0="${params.k0?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def zero_order(t, k0):
    '''Zero-order drug release kinetics: Q = k0 * t
    Args: t: time, k0: zero-order rate constant
    '''
    # Validate inputs - use defaults if None
    if t is None:
        t = 1.0
    if k0 is None:
        k0 = 10.0  # zero-order rate constant
    t, k0 = float(t), float(k0)

    return {"release": float(k0 * t), "t": t, "k0": k0}

# Execute the function
try:
    result = zero_order(
        t=auto_convert(os.environ.get("PARAM_T", "")),
        k0=auto_convert(os.environ.get("PARAM_K0", "")),
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
    "function": "zero_order",
    "domain": "bioengineering",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("zero_order_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("zero_order_output.txt", "w") as f:
    f.write("Biomni: Zero Order" + NL)
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
        biomni_function: "zero_order"
    END_VERSIONS
    """
}

workflow ZERO_ORDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ZERO_ORDER(ch_input)

    emit:
    results = ZERO_ORDER.out.results
    output = ZERO_ORDER.out.output
    versions = ZERO_ORDER.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ZERO_ORDER_WORKFLOW(ch_input)

    ZERO_ORDER_WORKFLOW.out.output.view { "Output: $it" }
}
