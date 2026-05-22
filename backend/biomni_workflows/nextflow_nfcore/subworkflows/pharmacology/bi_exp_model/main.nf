#!/usr/bin/env nextflow
/*
 * pharmacology/bi_exp_model
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Pharmacokinetic bi-exponential model parameters
params.t = '2.0'
params.A = '50.0'
params.alpha = '0.5'
params.B = '50.0'
params.beta = '0.05'

process BI_EXP_MODEL {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("bi_exp_model_results.json"), emit: results
    tuple val(meta), path("bi_exp_model_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_T="${params.t?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_A="${params.A?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ALPHA="${params.alpha?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_B="${params.B?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BETA="${params.beta?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def bi_exp_model(t, a, alpha, b, beta):
    '''Bi-exponential: y = A*exp(-alpha*t) + B*exp(-beta*t)
    Args: t: time, a,alpha: fast phase params, b,beta: slow phase params
    '''
    # Validate inputs - use defaults if None
    if t is None:
        t = 1.0
    if a is None:
        a = 50.0  # fast phase amplitude
    if alpha is None:
        alpha = 0.5  # fast phase rate
    if b is None:
        b = 50.0  # slow phase amplitude
    if beta is None:
        beta = 0.05  # slow phase rate
    t, a, alpha, b, beta = float(t), float(a), float(alpha), float(b), float(beta)

    y = a * np.exp(-alpha * t) + b * np.exp(-beta * t)
    return {"value": float(y), "t": t, "a": a, "alpha": alpha, "b": b, "beta": beta}

# Execute the function
try:
    result = bi_exp_model(
        t=auto_convert(os.environ.get("PARAM_T", "")),
        a=auto_convert(os.environ.get("PARAM_A", "")),
        alpha=auto_convert(os.environ.get("PARAM_ALPHA", "")),
        b=auto_convert(os.environ.get("PARAM_B", "")),
        beta=auto_convert(os.environ.get("PARAM_BETA", "")),
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
    "function": "bi_exp_model",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("bi_exp_model_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("bi_exp_model_output.txt", "w") as f:
    f.write("Biomni: Bi Exp Model" + NL)
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
        biomni_function: "bi_exp_model"
    END_VERSIONS
    """
}

workflow BI_EXP_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    BI_EXP_MODEL(ch_input)

    emit:
    results = BI_EXP_MODEL.out.results
    output = BI_EXP_MODEL.out.output
    versions = BI_EXP_MODEL.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    BI_EXP_MODEL_WORKFLOW(ch_input)

    BI_EXP_MODEL_WORKFLOW.out.output.view { "Output: $it" }
}
