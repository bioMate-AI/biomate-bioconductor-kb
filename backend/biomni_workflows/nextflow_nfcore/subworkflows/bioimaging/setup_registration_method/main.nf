#!/usr/bin/env nextflow
/*
 * bioimaging/setup_registration_method
 * Setup the registration method with specified parameters.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.transform = null
params.metric = 'mutual_information'
params.optimizer = 'gradient_descent'
params.learning_rate = 0.01
params.number_of_iterations = 100
params.gradient_convergence_tolerance = 1e-06

process SETUP_REGISTRATION_METHOD {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("setup_registration_method_results.json"), emit: results
    tuple val(meta), path("setup_registration_method_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TRANSFORM="${params.transform?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_METRIC="${params.metric?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OPTIMIZER="${params.optimizer?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_LEARNING_RATE="${params.learning_rate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NUMBER_OF_ITERATIONS="${params.number_of_iterations?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GRADIENT_CONVERGENCE_TOLERANCE="${params.gradient_convergence_tolerance?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def setup_registration_method(**kwargs):
    '''Bioimaging helper: setup_registration_method
    Note: Actual implementation requires SimpleITK, nnUNet, or other imaging libraries.
    '''
    return {"function": "setup_registration_method", "status": "placeholder", "args": {k: str(v)[:100] for k, v in kwargs.items()},
            "note": "Requires imaging libraries (SimpleITK, nnUNet) for actual implementation"}

# Execute the function
try:
    result = setup_registration_method(
        transform=auto_convert(os.environ.get("PARAM_TRANSFORM", "")),
        metric=auto_convert(os.environ.get("PARAM_METRIC", "mutual_information")),
        optimizer=auto_convert(os.environ.get("PARAM_OPTIMIZER", "gradient_descent")),
        learning_rate=auto_convert(os.environ.get("PARAM_LEARNING_RATE", "0.01")),
        number_of_iterations=auto_convert(os.environ.get("PARAM_NUMBER_OF_ITERATIONS", "100")),
        gradient_convergence_tolerance=auto_convert(os.environ.get("PARAM_GRADIENT_CONVERGENCE_TOLERANCE", "1e-06")),
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
    "function": "setup_registration_method",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("setup_registration_method_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("setup_registration_method_output.txt", "w") as f:
    f.write("Biomni: Setup Registration Method" + NL)
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
        biomni_function: "setup_registration_method"
    END_VERSIONS
    """
}

workflow SETUP_REGISTRATION_METHOD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SETUP_REGISTRATION_METHOD(ch_input)

    emit:
    results = SETUP_REGISTRATION_METHOD.out.results
    output = SETUP_REGISTRATION_METHOD.out.output
    versions = SETUP_REGISTRATION_METHOD.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SETUP_REGISTRATION_METHOD_WORKFLOW(ch_input)

    SETUP_REGISTRATION_METHOD_WORKFLOW.out.output.view { "Output: $it" }
}
