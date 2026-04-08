#!/usr/bin/env nextflow
/*
 * systems_biology/hill_function
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Hill function parameters
params.x = '1.0'
params.n = '2.0'
params.ec50 = '0.5'

process HILL_FUNCTION {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("hill_function_results.json"), emit: results
    tuple val(meta), path("hill_function_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_X="${params.x?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_N="${params.n?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_EC50="${params.ec50?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def hill_function(x, n, ec50):
    '''Hill function: x^n / (ec50^n + x^n)
    Args: x: concentration, n: Hill coefficient, ec50: half-maximal concentration
    '''
    # Validate inputs - use defaults if None
    if x is None:
        x = 1.0
    if n is None:
        n = 1.0  # Hill coefficient
    if ec50 is None:
        ec50 = 1.0
    x, n, ec50 = float(x), float(n), float(ec50)

    denom = ec50 ** n + x ** n
    response = (x ** n) / denom if denom != 0 else 0
    return {"response": float(response), "x": x, "n": n, "ec50": ec50}

# Execute the function
try:
    result = hill_function(
        x=auto_convert(os.environ.get("PARAM_X", "")),
        n=auto_convert(os.environ.get("PARAM_N", "")),
        ec50=auto_convert(os.environ.get("PARAM_EC50", "")),
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
    "function": "hill_function",
    "domain": "systems_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("hill_function_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("hill_function_output.txt", "w") as f:
    f.write("Biomni: Hill Function" + NL)
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
        biomni_function: "hill_function"
    END_VERSIONS
    """
}

workflow HILL_FUNCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    HILL_FUNCTION(ch_input)

    emit:
    results = HILL_FUNCTION.out.results
    output = HILL_FUNCTION.out.output
    versions = HILL_FUNCTION.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    HILL_FUNCTION_WORKFLOW(ch_input)

    HILL_FUNCTION_WORKFLOW.out.output.view { "Output: $it" }
}
