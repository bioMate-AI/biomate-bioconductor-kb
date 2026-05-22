#!/usr/bin/env nextflow
/*
 * immunology/logistic_growth
 * Logistic growth model: N(t) = K / (1 + ((K - N0) / N0) * exp(-r*t)).
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: logistic growth model parameters
params.n = '100.0'
params.r = '0.1'
params.k = '1000.0'

process LOGISTIC_GROWTH {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("logistic_growth_results.json"), emit: results
    tuple val(meta), path("logistic_growth_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_N="${params.n?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_R="${params.r?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_K="${params.k?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def logistic_growth(n, r, k):
    '''Logistic growth: dN/dt = r * N * (1 - N/K)
    Args: n: population, r: growth rate, k: carrying capacity
    '''
    # Validate inputs - use defaults if None
    if n is None:
        n = 100.0  # initial population
    if r is None:
        r = 0.1  # growth rate
    if k is None:
        k = 1000.0  # carrying capacity
    n, r, k = float(n), float(r), float(k)

    dndt = r * n * (1 - n / k) if k != 0 else 0
    return {"dN_dt": float(dndt), "N": n, "r": r, "K": k}

# Execute the function
try:
    result = logistic_growth(
        n=auto_convert(os.environ.get("PARAM_N", "")),
        r=auto_convert(os.environ.get("PARAM_R", "")),
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
    "function": "logistic_growth",
    "domain": "immunology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("logistic_growth_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("logistic_growth_output.txt", "w") as f:
    f.write("Biomni: Logistic Growth" + NL)
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
        biomni_function: "logistic_growth"
    END_VERSIONS
    """
}

workflow LOGISTIC_GROWTH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    LOGISTIC_GROWTH(ch_input)

    emit:
    results = LOGISTIC_GROWTH.out.results
    output = LOGISTIC_GROWTH.out.output
    versions = LOGISTIC_GROWTH.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    LOGISTIC_GROWTH_WORKFLOW(ch_input)

    LOGISTIC_GROWTH_WORKFLOW.out.output.view { "Output: $it" }
}
