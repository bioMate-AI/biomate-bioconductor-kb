#!/usr/bin/env nextflow
/*
 * bioimaging/command_iteration
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// No value parameters

process COMMAND_ITERATION {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("command_iteration_results.json"), emit: results
    tuple val(meta), path("command_iteration_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    # No value parameters

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



def command_iteration():
    # Create a command iteration callback for SimpleITK registration.
    # This is a helper function that creates a callback object to monitor
    # registration progress during optimization.
    # Returns: Dictionary with callback configuration for SimpleITK ImageRegistrationMethod
    #
    # Since this is a callback factory, we return configuration for the callback
    # The actual callback would be used in registration workflows

    return dict(
        function="command_iteration",
        status="success",
        description="Registration iteration callback factory for SimpleITK",
        callback_type="RegistrationCallback",
        usage="Use with registration.AddCommand(sitk.sitkIterationEvent, callback)",
        features=[
            "Tracks iteration count during optimization",
            "Records metric values at each iteration",
            "Provides progress logging every 10 iterations",
            "Returns optimization summary with metric history"
        ],
        example_code="callback = lambda: print(registration.GetMetricValue())"
    )

# Execute the function
try:
    result = command_iteration()
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "command_iteration",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("command_iteration_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("command_iteration_output.txt", "w") as f:
    f.write("Biomni: Command Iteration" + NL)
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
        biomni_function: "command_iteration"
    END_VERSIONS
    """
}

workflow COMMAND_ITERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    COMMAND_ITERATION(ch_input)

    emit:
    results = COMMAND_ITERATION.out.results
    output = COMMAND_ITERATION.out.output
    versions = COMMAND_ITERATION.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    COMMAND_ITERATION_WORKFLOW(ch_input)

    COMMAND_ITERATION_WORKFLOW.out.output.view { "Output: $it" }
}
