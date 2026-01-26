#!/usr/bin/env nextflow
/*
 * microbiology/glv_equations
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.abundances = null
params.t = null
params.growth_rates = null
params.interaction_matrix = null

process GLV_EQUATIONS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("glv_equations_results.json"), emit: results
    tuple val(meta), path("glv_equations_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_ABUNDANCES="${params.abundances?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_T="${params.t?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GROWTH_RATES="${params.growth_rates?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_INTERACTION_MATRIX="${params.interaction_matrix?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import numpy as np
import json
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



def glv_equations(populations, growth_rates, interaction_matrix):
    '''GLV: dxi/dt = xi * (ri + sum_j(aij * xj))
    Args: populations: list, growth_rates: list, interaction_matrix: 2D list (as JSON string)
    '''
    if isinstance(populations, str):
        populations = [float(x.strip()) for x in populations.split(',')]
    if isinstance(growth_rates, str):
        growth_rates = [float(x.strip()) for x in growth_rates.split(',')]
    if isinstance(interaction_matrix, str):
        interaction_matrix = json.loads(interaction_matrix)
    
    populations = np.array(populations)
    growth_rates = np.array(growth_rates)
    interaction_matrix = np.array(interaction_matrix)
    
    derivatives = populations * (growth_rates + interaction_matrix @ populations)
    return {"derivatives": derivatives.tolist(), "populations": populations.tolist()}

# Execute the function
try:
    result = glv_equations(
        abundances=auto_convert(os.environ.get("PARAM_ABUNDANCES", "")),
        t=auto_convert(os.environ.get("PARAM_T", "")),
        growth_rates=auto_convert(os.environ.get("PARAM_GROWTH_RATES", "")),
        interaction_matrix=auto_convert(os.environ.get("PARAM_INTERACTION_MATRIX", "")),
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
    "function": "glv_equations",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("glv_equations_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("glv_equations_output.txt", "w") as f:
    f.write("Biomni: Glv Equations" + NL)
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
        biomni_function: "glv_equations"
    END_VERSIONS
    """
}

workflow GLV_EQUATIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GLV_EQUATIONS(ch_input)

    emit:
    results = GLV_EQUATIONS.out.results
    output = GLV_EQUATIONS.out.output
    versions = GLV_EQUATIONS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GLV_EQUATIONS_WORKFLOW(ch_input)

    GLV_EQUATIONS_WORKFLOW.out.output.view { "Output: $it" }
}
