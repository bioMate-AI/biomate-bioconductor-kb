#!/usr/bin/env nextflow
/*
 * microbiology/bacterial_dynamics
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.N = null

process BACTERIAL_DYNAMICS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("bacterial_dynamics_results.json"), emit: results
    tuple val(meta), path("bacterial_dynamics_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_T="${params.t?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_N="${params.N?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def bacterial_dynamics(n, r, k, d):
    '''Bacterial dynamics: dN/dt = r*N*(1-N/K) - d*N
    Args: n: population, r: growth rate, k: carrying capacity, d: death rate
    '''
    dndt = r * n * (1 - n / k) - d * n
    return {"dN_dt": float(dndt), "N": n, "r": r, "K": k, "d": d}

# Execute the function
try:
    result = bacterial_dynamics(
        t=auto_convert(os.environ.get("PARAM_T", "")),
        N=auto_convert(os.environ.get("PARAM_N", "")),
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
    "function": "bacterial_dynamics",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("bacterial_dynamics_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("bacterial_dynamics_output.txt", "w") as f:
    f.write("Biomni: Bacterial Dynamics" + NL)
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
        biomni_function: "bacterial_dynamics"
    END_VERSIONS
    """
}

workflow BACTERIAL_DYNAMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    BACTERIAL_DYNAMICS(ch_input)

    emit:
    results = BACTERIAL_DYNAMICS.out.results
    output = BACTERIAL_DYNAMICS.out.output
    versions = BACTERIAL_DYNAMICS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    BACTERIAL_DYNAMICS_WORKFLOW(ch_input)

    BACTERIAL_DYNAMICS_WORKFLOW.out.output.view { "Output: $it" }
}
