#!/usr/bin/env nextflow
/*
 * bioengineering/korsmeyer_peppas
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.k = null
params.n = null

process KORSMEYER_PEPPAS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("korsmeyer_peppas_results.json"), emit: results
    tuple val(meta), path("korsmeyer_peppas_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_T="${params.t?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_K="${params.k?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_N="${params.n?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def korsmeyer_peppas(t, k, n):
    '''Korsmeyer-Peppas model: Q = k * t^n
    Args: t: time, k: rate constant, n: release exponent
    '''
    # Validate inputs - use defaults if None
    if t is None:
        t = 1.0
    if k is None:
        k = 1.0  # rate constant
    if n is None:
        n = 0.5  # release exponent (0.5 = Fickian diffusion)
    t, k, n = float(t), float(k), float(n)

    return {"release": float(k * (t ** n)), "t": t, "k": k, "n": n}

# Execute the function
try:
    result = korsmeyer_peppas(
        t=auto_convert(os.environ.get("PARAM_T", "")),
        k=auto_convert(os.environ.get("PARAM_K", "")),
        n=auto_convert(os.environ.get("PARAM_N", "")),
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
    "function": "korsmeyer_peppas",
    "domain": "bioengineering",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("korsmeyer_peppas_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("korsmeyer_peppas_output.txt", "w") as f:
    f.write("Biomni: Korsmeyer Peppas" + NL)
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
        biomni_function: "korsmeyer_peppas"
    END_VERSIONS
    """
}

workflow KORSMEYER_PEPPAS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    KORSMEYER_PEPPAS(ch_input)

    emit:
    results = KORSMEYER_PEPPAS.out.results
    output = KORSMEYER_PEPPAS.out.output
    versions = KORSMEYER_PEPPAS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    KORSMEYER_PEPPAS_WORKFLOW(ch_input)

    KORSMEYER_PEPPAS_WORKFLOW.out.output.view { "Output: $it" }
}
