#!/usr/bin/env nextflow
/*
 * physiology/cosinor_model
 * Cosine function with baseline (mesor), amplitude, and phase shift.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Cosinor model for circadian rhythm analysis (body temperature)
params.t = '12.0'
params.mesor = '36.7'
params.amplitude = '0.5'
params.acrophase = '16.0'
params.period = '24.0'

process COSINOR_MODEL {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("cosinor_model_results.json"), emit: results
    tuple val(meta), path("cosinor_model_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_T="${params.t?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MESOR="${params.mesor?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_AMPLITUDE="${params.amplitude?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ACROPHASE="${params.acrophase?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PERIOD="${params.period?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def cosinor_model(t, mesor, amplitude, acrophase, period=24):
    '''Cosinor: y = mesor + amplitude * cos(2*pi*(t-acrophase)/period)
    Args: t: time, mesor: mean level, amplitude: oscillation amplitude, acrophase: peak time, period: cycle length
    '''
    # Validate inputs - use defaults if None
    if t is None:
        t = 0.0
    if mesor is None:
        mesor = 0.0
    if amplitude is None:
        amplitude = 1.0
    if acrophase is None:
        acrophase = 0.0
    if period is None:
        period = 24.0
    t, mesor, amplitude, acrophase, period = float(t), float(mesor), float(amplitude), float(acrophase), float(period)
    y = mesor + amplitude * np.cos(2 * np.pi * (t - acrophase) / period)
    return {"value": float(y), "t": t, "mesor": mesor, "amplitude": amplitude, "acrophase": acrophase, "period": period}

# Execute the function
try:
    result = cosinor_model(
        t=auto_convert(os.environ.get("PARAM_T", "")),
        mesor=auto_convert(os.environ.get("PARAM_MESOR", "")),
        amplitude=auto_convert(os.environ.get("PARAM_AMPLITUDE", "")),
        acrophase=auto_convert(os.environ.get("PARAM_ACROPHASE", "")),
        period=auto_convert(os.environ.get("PARAM_PERIOD", "")),
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
    "function": "cosinor_model",
    "domain": "physiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("cosinor_model_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("cosinor_model_output.txt", "w") as f:
    f.write("Biomni: Cosinor Model" + NL)
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
        biomni_function: "cosinor_model"
    END_VERSIONS
    """
}

workflow COSINOR_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    COSINOR_MODEL(ch_input)

    emit:
    results = COSINOR_MODEL.out.results
    output = COSINOR_MODEL.out.output
    versions = COSINOR_MODEL.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    COSINOR_MODEL_WORKFLOW(ch_input)

    COSINOR_MODEL_WORKFLOW.out.output.view { "Output: $it" }
}
