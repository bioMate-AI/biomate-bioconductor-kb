#!/usr/bin/env nextflow
/*
 * microbiology/methane_yield_model
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Anaerobic digestion methane yield calculation
params.substrate = '10.0'
params.yield_coefficient = '0.35'
params.inhibition_constant = '5.0'

process METHANE_YIELD_MODEL {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("methane_yield_model_results.json"), emit: results
    tuple val(meta), path("methane_yield_model_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_SUBSTRATE="${params.substrate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_YIELD_COEFFICIENT="${params.yield_coefficient?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_INHIBITION_CONSTANT="${params.inhibition_constant?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def methane_yield_model(substrate, yield_coefficient, inhibition_constant=None):
    '''Methane yield: Y = Ymax * S / (Ks + S) with optional inhibition
    Args: substrate: concentration, yield_coefficient: max yield, inhibition_constant: optional Ki
    '''
    # Validate inputs - use defaults if None
    if substrate is None:
        substrate = 10.0  # substrate concentration
    if yield_coefficient is None:
        yield_coefficient = 0.35  # typical methane yield
    substrate = float(substrate)
    yield_coefficient = float(yield_coefficient)

    if inhibition_constant:
        inhibition_constant = float(inhibition_constant)
        yield_val = yield_coefficient * substrate / (substrate + inhibition_constant)
    else:
        yield_val = yield_coefficient * substrate
    return {"methane_yield": float(yield_val), "substrate": substrate}

# Execute the function
try:
    result = methane_yield_model(
        substrate=auto_convert(os.environ.get("PARAM_SUBSTRATE", "")),
        yield_coefficient=auto_convert(os.environ.get("PARAM_YIELD_COEFFICIENT", "")),
        inhibition_constant=auto_convert(os.environ.get("PARAM_INHIBITION_CONSTANT", "")),
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
    "function": "methane_yield_model",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("methane_yield_model_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("methane_yield_model_output.txt", "w") as f:
    f.write("Biomni: Methane Yield Model" + NL)
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
        biomni_function: "methane_yield_model"
    END_VERSIONS
    """
}

workflow METHANE_YIELD_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    METHANE_YIELD_MODEL(ch_input)

    emit:
    results = METHANE_YIELD_MODEL.out.results
    output = METHANE_YIELD_MODEL.out.output
    versions = METHANE_YIELD_MODEL.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    METHANE_YIELD_MODEL_WORKFLOW(ch_input)

    METHANE_YIELD_MODEL_WORKFLOW.out.output.view { "Output: $it" }
}
