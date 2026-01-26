#!/usr/bin/env nextflow
/*
 * pharmacology/ADMET_pred
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.smiles = null

process ADMET_PRED {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("ADMET_pred_results.json"), emit: results
    tuple val(meta), path("ADMET_pred_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_SMILES="${params.smiles?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def ADMET_pred(smiles):
    '''Predict ADMET properties. Returns placeholder - actual prediction requires ML models.
    Args: smiles: SMILES string
    '''
    return {"smiles": smiles, "predictions": {
        "absorption": "predicted", "distribution": "predicted", 
        "metabolism": "predicted", "excretion": "predicted", "toxicity": "predicted"},
        "note": "Actual ADMET prediction requires specialized ML models"}

# Execute the function
try:
    result = ADMET_pred(
        smiles=auto_convert(os.environ.get("PARAM_SMILES", "")),
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
    "function": "ADMET_pred",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("ADMET_pred_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("ADMET_pred_output.txt", "w") as f:
    f.write("Biomni: Admet Pred" + NL)
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
        biomni_function: "ADMET_pred"
    END_VERSIONS
    """
}

workflow ADMET_PRED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ADMET_PRED(ch_input)

    emit:
    results = ADMET_PRED.out.results
    output = ADMET_PRED.out.output
    versions = ADMET_PRED.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ADMET_PRED_WORKFLOW(ch_input)

    ADMET_PRED_WORKFLOW.out.output.view { "Output: $it" }
}
