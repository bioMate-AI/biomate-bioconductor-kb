#!/usr/bin/env nextflow
/*
 * bioengineering/default_whole_cell_model
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.y = null
params.params = null

process DEFAULT_WHOLE_CELL_MODEL {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("default_whole_cell_model_results.json"), emit: results
    tuple val(meta), path("default_whole_cell_model_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_T="${params.t?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_Y="${params.y?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PARAMS="${params.params?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def default_whole_cell_model():
    '''Return default whole cell model parameters.
    '''
    return {
        "cell_volume": 1e-15,  # L (1 fL)
        "membrane_area": 1e-12,  # m^2
        "cytoplasm_viscosity": 1e-3,  # Pa.s
        "temperature": 310.15,  # K (37C)
        "ph": 7.2,
        "ionic_strength": 0.15,  # M
        "atp_concentration": 1e-3,  # M
        "note": "Default E. coli whole cell parameters"
    }

# Execute the function
try:
    result = default_whole_cell_model()
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "default_whole_cell_model",
    "domain": "bioengineering",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("default_whole_cell_model_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("default_whole_cell_model_output.txt", "w") as f:
    f.write("Biomni: Default Whole Cell Model" + NL)
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
        biomni_function: "default_whole_cell_model"
    END_VERSIONS
    """
}

workflow DEFAULT_WHOLE_CELL_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    DEFAULT_WHOLE_CELL_MODEL(ch_input)

    emit:
    results = DEFAULT_WHOLE_CELL_MODEL.out.results
    output = DEFAULT_WHOLE_CELL_MODEL.out.output
    versions = DEFAULT_WHOLE_CELL_MODEL.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    DEFAULT_WHOLE_CELL_MODEL_WORKFLOW(ch_input)

    DEFAULT_WHOLE_CELL_MODEL_WORKFLOW.out.output.view { "Output: $it" }
}
