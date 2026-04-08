#!/usr/bin/env nextflow
/*
 * biochemistry/michaelis_menten
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.s = null
params.vmax = null
params.km = null

process MICHAELIS_MENTEN {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("michaelis_menten_results.json"), emit: results
    tuple val(meta), path("michaelis_menten_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_S="${params.s?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_VMAX="${params.vmax?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_KM="${params.km?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def michaelis_menten(s, vmax, km):
    '''Michaelis-Menten equation for enzyme kinetics.

    Args:
        s: Substrate concentration
        vmax: Maximum reaction velocity
        km: Michaelis constant

    Returns:
        Reaction velocity v = vmax * s / (km + s)
    '''
    # Validate inputs - use defaults if None
    if s is None:
        s = 1.0
    if vmax is None:
        vmax = 100.0
    if km is None:
        km = 10.0
    s, vmax, km = float(s), float(vmax), float(km)
    velocity = vmax * s / (km + s) if (km + s) != 0 else 0
    return {"velocity": velocity, "s": s, "vmax": vmax, "km": km}

# Execute the function
try:
    result = michaelis_menten(
        s=auto_convert(os.environ.get("PARAM_S", "")),
        vmax=auto_convert(os.environ.get("PARAM_VMAX", "")),
        km=auto_convert(os.environ.get("PARAM_KM", "")),
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
    "function": "michaelis_menten",
    "domain": "biochemistry",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("michaelis_menten_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("michaelis_menten_output.txt", "w") as f:
    f.write("Biomni: Michaelis Menten" + NL)
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
        biomni_function: "michaelis_menten"
    END_VERSIONS
    """
}

workflow MICHAELIS_MENTEN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    MICHAELIS_MENTEN(ch_input)

    emit:
    results = MICHAELIS_MENTEN.out.results
    output = MICHAELIS_MENTEN.out.output
    versions = MICHAELIS_MENTEN.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    MICHAELIS_MENTEN_WORKFLOW(ch_input)

    MICHAELIS_MENTEN_WORKFLOW.out.output.view { "Output: $it" }
}
