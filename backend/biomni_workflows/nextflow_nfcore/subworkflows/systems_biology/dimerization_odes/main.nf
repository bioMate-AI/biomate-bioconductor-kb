#!/usr/bin/env nextflow
/*
 * systems_biology/dimerization_odes
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Dimerization kinetics (2M <-> D)
params.monomer = '10.0'
params.dimer = '0.0'
params.kon = '0.1'
params.koff = '0.01'
params.t = null  // optional time point (ignored for instantaneous rate computation)

process DIMERIZATION_ODES {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("dimerization_odes_results.json"), emit: results
    tuple val(meta), path("dimerization_odes_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_MONOMER="${params.monomer?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DIMER="${params.dimer?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_KON="${params.kon?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_KOFF="${params.koff?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_T="${params.t?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def dimerization_odes(monomer, dimer, kon, koff, t=None):
    '''Dimerization: 2M <-> D with kon, koff. Returns instantaneous rates dM/dt and dD/dt.
    Args: monomer: M conc, dimer: D conc, kon: association rate, koff: dissociation rate,
          t: time point (accepted but not used for instantaneous rate computation)
    '''
    # Validate inputs - use defaults if None
    if monomer is None:
        monomer = 10.0  # initial monomer concentration
    if dimer is None:
        dimer = 0.0  # initial dimer concentration
    if kon is None:
        kon = 0.1  # association rate
    if koff is None:
        koff = 0.01  # dissociation rate
    monomer, dimer = float(monomer), float(dimer)
    kon, koff = float(kon), float(koff)

    dm_dt = -2 * kon * monomer**2 + 2 * koff * dimer
    dd_dt = kon * monomer**2 - koff * dimer
    return {"dM_dt": float(dm_dt), "dD_dt": float(dd_dt), "M": monomer, "D": dimer}

# Execute the function
try:
    result = dimerization_odes(
        monomer=auto_convert(os.environ.get("PARAM_MONOMER", "")),
        dimer=auto_convert(os.environ.get("PARAM_DIMER", "")),
        kon=auto_convert(os.environ.get("PARAM_KON", "")),
        koff=auto_convert(os.environ.get("PARAM_KOFF", "")),
        t=auto_convert(os.environ.get("PARAM_T", "")),
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
    "function": "dimerization_odes",
    "domain": "systems_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("dimerization_odes_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("dimerization_odes_output.txt", "w") as f:
    f.write("Biomni: Dimerization Odes" + NL)
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
        biomni_function: "dimerization_odes"
    END_VERSIONS
    """
}

workflow DIMERIZATION_ODES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    DIMERIZATION_ODES(ch_input)

    emit:
    results = DIMERIZATION_ODES.out.results
    output = DIMERIZATION_ODES.out.output
    versions = DIMERIZATION_ODES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    DIMERIZATION_ODES_WORKFLOW(ch_input)

    DIMERIZATION_ODES_WORKFLOW.out.output.view { "Output: $it" }
}
