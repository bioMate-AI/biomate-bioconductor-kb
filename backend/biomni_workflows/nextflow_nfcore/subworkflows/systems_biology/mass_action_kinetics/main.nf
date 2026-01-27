#!/usr/bin/env nextflow
/*
 * systems_biology/mass_action_kinetics
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.k = null
params.concentrations = null

process MASS_ACTION_KINETICS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("mass_action_kinetics_results.json"), emit: results
    tuple val(meta), path("mass_action_kinetics_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_K="${params.k?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CONCENTRATIONS="${params.concentrations?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def mass_action_kinetics(k, concentrations):
    '''Mass action kinetics: rate = k * product(concentrations)
    Args: k: rate constant, concentrations: list of reactant concentrations
    '''
    import numpy as np
    # Validate inputs - use defaults if None
    if k is None:
        k = 1.0
    if concentrations is None:
        concentrations = [1.0, 1.0]
    k = float(k)
    if isinstance(concentrations, str):
        concentrations = [float(x.strip()) for x in concentrations.split(',')]
    elif not isinstance(concentrations, list):
        concentrations = [float(concentrations)]

    rate = k * np.prod(concentrations)
    return {"rate": float(rate), "k": k, "concentrations": concentrations}

# Execute the function
try:
    result = mass_action_kinetics(
        k=auto_convert(os.environ.get("PARAM_K", "")),
        concentrations=auto_convert(os.environ.get("PARAM_CONCENTRATIONS", "")),
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
    "function": "mass_action_kinetics",
    "domain": "systems_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("mass_action_kinetics_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("mass_action_kinetics_output.txt", "w") as f:
    f.write("Biomni: Mass Action Kinetics" + NL)
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
        biomni_function: "mass_action_kinetics"
    END_VERSIONS
    """
}

workflow MASS_ACTION_KINETICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    MASS_ACTION_KINETICS(ch_input)

    emit:
    results = MASS_ACTION_KINETICS.out.results
    output = MASS_ACTION_KINETICS.out.output
    versions = MASS_ACTION_KINETICS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    MASS_ACTION_KINETICS_WORKFLOW(ch_input)

    MASS_ACTION_KINETICS_WORKFLOW.out.output.view { "Output: $it" }
}
