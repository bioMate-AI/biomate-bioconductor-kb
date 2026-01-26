#!/usr/bin/env nextflow
/*
 * systems_biology/ras_ode_system
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.ras_gdp = null
params.ras_gtp = null
params.gef_rate = null
params.gap_rate = null

process RAS_ODE_SYSTEM {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("ras_ode_system_results.json"), emit: results
    tuple val(meta), path("ras_ode_system_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_RAS_GDP="${params.ras_gdp?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_RAS_GTP="${params.ras_gtp?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GEF_RATE="${params.gef_rate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GAP_RATE="${params.gap_rate?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def ras_ode_system(ras_gdp, ras_gtp, gef_rate, gap_rate):
    '''RAS cycle: RAS-GDP <-> RAS-GTP with GEF activation and GAP inactivation
    Args: ras_gdp, ras_gtp: concentrations, gef_rate: activation, gap_rate: inactivation
    '''
    d_gdp = -gef_rate * ras_gdp + gap_rate * ras_gtp
    d_gtp = gef_rate * ras_gdp - gap_rate * ras_gtp
    return {"dRAS_GDP_dt": float(d_gdp), "dRAS_GTP_dt": float(d_gtp), "RAS_GDP": ras_gdp, "RAS_GTP": ras_gtp}

# Execute the function
try:
    result = ras_ode_system(
        ras_gdp=auto_convert(os.environ.get("PARAM_RAS_GDP", "")),
        ras_gtp=auto_convert(os.environ.get("PARAM_RAS_GTP", "")),
        gef_rate=auto_convert(os.environ.get("PARAM_GEF_RATE", "")),
        gap_rate=auto_convert(os.environ.get("PARAM_GAP_RATE", "")),
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
    "function": "ras_ode_system",
    "domain": "systems_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("ras_ode_system_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("ras_ode_system_output.txt", "w") as f:
    f.write("Biomni: Ras Ode System" + NL)
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
        biomni_function: "ras_ode_system"
    END_VERSIONS
    """
}

workflow RAS_ODE_SYSTEM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    RAS_ODE_SYSTEM(ch_input)

    emit:
    results = RAS_ODE_SYSTEM.out.results
    output = RAS_ODE_SYSTEM.out.output
    versions = RAS_ODE_SYSTEM.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    RAS_ODE_SYSTEM_WORKFLOW(ch_input)

    RAS_ODE_SYSTEM_WORKFLOW.out.output.view { "Output: $it" }
}
