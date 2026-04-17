#!/usr/bin/env nextflow
/*
 * microbiology/vfa_production_model
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: VFA production kinetics (Monod model)
params.substrate = '10.0'
params.max_rate = '5.0'
params.ks = '2.0'

process VFA_PRODUCTION_MODEL {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("vfa_production_model_results.json"), emit: results
    tuple val(meta), path("vfa_production_model_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_SUBSTRATE="${params.substrate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MAX_RATE="${params.max_rate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_KS="${params.ks?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def vfa_production_model(substrate, max_rate, ks):
    '''VFA production: rate = Vmax * S / (Ks + S)
    Args: substrate: concentration, max_rate: Vmax, ks: half-saturation constant
    '''
    # Validate inputs - use defaults if None
    if substrate is None:
        substrate = 10.0
    if max_rate is None:
        max_rate = 5.0  # max VFA production rate
    if ks is None:
        ks = 2.0  # half-saturation constant
    substrate, max_rate, ks = float(substrate), float(max_rate), float(ks)

    rate = max_rate * substrate / (ks + substrate) if (ks + substrate) != 0 else 0
    return {"vfa_rate": float(rate), "substrate": substrate}

# Execute the function
try:
    result = vfa_production_model(
        substrate=auto_convert(os.environ.get("PARAM_SUBSTRATE", "")),
        max_rate=auto_convert(os.environ.get("PARAM_MAX_RATE", "")),
        ks=auto_convert(os.environ.get("PARAM_KS", "")),
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
    "function": "vfa_production_model",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("vfa_production_model_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("vfa_production_model_output.txt", "w") as f:
    f.write("Biomni: Vfa Production Model" + NL)
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
        biomni_function: "vfa_production_model"
    END_VERSIONS
    """
}

workflow VFA_PRODUCTION_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    VFA_PRODUCTION_MODEL(ch_input)

    emit:
    results = VFA_PRODUCTION_MODEL.out.results
    output = VFA_PRODUCTION_MODEL.out.output
    versions = VFA_PRODUCTION_MODEL.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    VFA_PRODUCTION_MODEL_WORKFLOW(ch_input)

    VFA_PRODUCTION_MODEL_WORKFLOW.out.output.view { "Output: $it" }
}
