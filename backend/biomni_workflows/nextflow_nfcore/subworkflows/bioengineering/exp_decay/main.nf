#!/usr/bin/env nextflow
/*
 * bioengineering/exp_decay
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.a = null
params.k = null

process EXP_DECAY {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("exp_decay_results.json"), emit: results
    tuple val(meta), path("exp_decay_output.txt"), emit: output
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



def exp_decay(t, a, k):
    '''Exponential decay: y = A * exp(-k*t)
    Args: t: time, a: initial value, k: decay constant
    '''
    return {"value": float(a * np.exp(-k * t)), "t": t, "a": a, "k": k}

# Execute the function
try:
    result = exp_decay(
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
    "function": "exp_decay",
    "domain": "bioengineering",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("exp_decay_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("exp_decay_output.txt", "w") as f:
    f.write("Biomni: Exp Decay" + NL)
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
        biomni_function: "exp_decay"
    END_VERSIONS
    """
}

workflow EXP_DECAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    EXP_DECAY(ch_input)

    emit:
    results = EXP_DECAY.out.results
    output = EXP_DECAY.out.output
    versions = EXP_DECAY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    EXP_DECAY_WORKFLOW(ch_input)

    EXP_DECAY_WORKFLOW.out.output.view { "Output: $it" }
}
