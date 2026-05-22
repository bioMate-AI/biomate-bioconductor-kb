#!/usr/bin/env nextflow
/*
 * synthetic_biology/gene_circuit_odes
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: IPTG-inducible gene expression system
params.protein_level = '1.0'
params.production_rate = '10.0'
params.degradation_rate = '0.5'
params.inducer = '1.0'
params.hill_coef = '2.0'
params.k_half = '1.0'

process GENE_CIRCUIT_ODES {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("gene_circuit_odes_results.json"), emit: results
    tuple val(meta), path("gene_circuit_odes_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_PROTEIN_LEVEL="${params.protein_level?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PRODUCTION_RATE="${params.production_rate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DEGRADATION_RATE="${params.degradation_rate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_INDUCER="${params.inducer?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_HILL_COEF="${params.hill_coef?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_K_HALF="${params.k_half?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def gene_circuit_odes(protein_level, production_rate, degradation_rate, inducer=0, hill_coef=2, k_half=1):
    '''Gene circuit: dP/dt = production * (inducer^n / (K^n + inducer^n)) - degradation * P
    Args: protein_level: current level, production_rate, degradation_rate, inducer: inducer conc, hill_coef: cooperativity
    '''
    # Validate inputs - use defaults if None
    if protein_level is None:
        protein_level = 1.0
    if production_rate is None:
        production_rate = 10.0
    if degradation_rate is None:
        degradation_rate = 0.5
    if inducer is None:
        inducer = 1.0
    if hill_coef is None:
        hill_coef = 2.0
    if k_half is None:
        k_half = 1.0
    protein_level = float(protein_level)
    production_rate = float(production_rate)
    degradation_rate = float(degradation_rate)
    inducer = float(inducer)
    hill_coef = float(hill_coef)
    k_half = float(k_half)

    if inducer > 0:
        activation = (inducer ** hill_coef) / (k_half ** hill_coef + inducer ** hill_coef)
    else:
        activation = 0
    dpdt = production_rate * activation - degradation_rate * protein_level
    return {"dP_dt": float(dpdt), "protein_level": protein_level, "activation": float(activation)}

# Execute the function
try:
    result = gene_circuit_odes(
        protein_level=auto_convert(os.environ.get("PARAM_PROTEIN_LEVEL", "")),
        production_rate=auto_convert(os.environ.get("PARAM_PRODUCTION_RATE", "")),
        degradation_rate=auto_convert(os.environ.get("PARAM_DEGRADATION_RATE", "")),
        inducer=auto_convert(os.environ.get("PARAM_INDUCER", "")),
        hill_coef=auto_convert(os.environ.get("PARAM_HILL_COEF", "")),
        k_half=auto_convert(os.environ.get("PARAM_K_HALF", "")),
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
    "function": "gene_circuit_odes",
    "domain": "synthetic_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("gene_circuit_odes_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("gene_circuit_odes_output.txt", "w") as f:
    f.write("Biomni: Gene Circuit Odes" + NL)
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
        biomni_function: "gene_circuit_odes"
    END_VERSIONS
    """
}

workflow GENE_CIRCUIT_ODES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GENE_CIRCUIT_ODES(ch_input)

    emit:
    results = GENE_CIRCUIT_ODES.out.results
    output = GENE_CIRCUIT_ODES.out.output
    versions = GENE_CIRCUIT_ODES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GENE_CIRCUIT_ODES_WORKFLOW(ch_input)

    GENE_CIRCUIT_ODES_WORKFLOW.out.output.view { "Output: $it" }
}
