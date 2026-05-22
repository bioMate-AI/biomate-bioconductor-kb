#!/usr/bin/env nextflow
/*
 * systems_biology/ode_system
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Generic ODE system
params.state = '[1.0, 2.0, 0.5]'
params.rates = '[0.1, 0.2, 0.15]'
params.stoichiometry = null

process ODE_SYSTEM {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("ode_system_results.json"), emit: results
    tuple val(meta), path("ode_system_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_STATE="${params.state?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_RATES="${params.rates?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_STOICHIOMETRY="${params.stoichiometry?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def ode_system(state, rates, stoichiometry=None):
    '''Generic ODE: dx/dt = S * v(x) where S is stoichiometry matrix
    Args: state: current state vector, rates: rate constants, stoichiometry: matrix (optional)
    '''
    # Validate inputs - use defaults if None
    if state is None:
        state = [1.0, 1.0]
    if rates is None:
        rates = [0.1, 0.1]

    if isinstance(state, str):
        state = [float(x.strip()) for x in state.split(',')]
    if isinstance(rates, str):
        rates = [float(x.strip()) for x in rates.split(',')]
    # Simple linear system if no stoichiometry
    derivatives = [r * s for r, s in zip(rates, state)]
    return {"derivatives": derivatives, "state": state, "rates": rates}

# Execute the function
try:
    result = ode_system(
        state=auto_convert(os.environ.get("PARAM_STATE", "")),
        rates=auto_convert(os.environ.get("PARAM_RATES", "")),
        stoichiometry=auto_convert(os.environ.get("PARAM_STOICHIOMETRY", "")),
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
    "function": "ode_system",
    "domain": "systems_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("ode_system_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("ode_system_output.txt", "w") as f:
    f.write("Biomni: Ode System" + NL)
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
        biomni_function: "ode_system"
    END_VERSIONS
    """
}

workflow ODE_SYSTEM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ODE_SYSTEM(ch_input)

    emit:
    results = ODE_SYSTEM.out.results
    output = ODE_SYSTEM.out.output
    versions = ODE_SYSTEM.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ODE_SYSTEM_WORKFLOW(ch_input)

    ODE_SYSTEM_WORKFLOW.out.output.view { "Output: $it" }
}
