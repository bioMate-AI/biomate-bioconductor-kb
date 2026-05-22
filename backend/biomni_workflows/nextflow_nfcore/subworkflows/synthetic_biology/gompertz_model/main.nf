#!/usr/bin/env nextflow
/*
 * synthetic_biology/gompertz_model
 * Gompertz growth model.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Bacterial growth at t=5 hours
params.t = '5.0'
params.a = '10.0'
params.b = '2.0'
params.c = '0.5'

process GOMPERTZ_MODEL {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("gompertz_model_results.json"), emit: results
    tuple val(meta), path("gompertz_model_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_T="${params.t?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_A="${params.a?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_B="${params.b?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_C="${params.c?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def gompertz_model(t, a, b, c):
    '''Gompertz: y = A * exp(-B * exp(-C*t))
    Args: t: time, a: asymptotic value, b: displacement, c: growth rate
    '''
    # Validate inputs - use defaults if None
    if t is None:
        t = 1.0
    if a is None:
        a = 10.0  # asymptotic max population
    if b is None:
        b = 2.0  # displacement
    if c is None:
        c = 0.5  # growth rate
    t, a, b, c = float(t), float(a), float(b), float(c)

    y = a * np.exp(-b * np.exp(-c * t))
    return {"value": float(y), "t": t, "a": a, "b": b, "c": c}

# Execute the function
try:
    result = gompertz_model(
        t=auto_convert(os.environ.get("PARAM_T", "")),
        a=auto_convert(os.environ.get("PARAM_A", "")),
        b=auto_convert(os.environ.get("PARAM_B", "")),
        c=auto_convert(os.environ.get("PARAM_C", "")),
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
    "function": "gompertz_model",
    "domain": "synthetic_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("gompertz_model_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("gompertz_model_output.txt", "w") as f:
    f.write("Biomni: Gompertz Model" + NL)
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
        biomni_function: "gompertz_model"
    END_VERSIONS
    """
}

workflow GOMPERTZ_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GOMPERTZ_MODEL(ch_input)

    emit:
    results = GOMPERTZ_MODEL.out.results
    output = GOMPERTZ_MODEL.out.output
    versions = GOMPERTZ_MODEL.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GOMPERTZ_MODEL_WORKFLOW(ch_input)

    GOMPERTZ_MODEL_WORKFLOW.out.output.view { "Output: $it" }
}
