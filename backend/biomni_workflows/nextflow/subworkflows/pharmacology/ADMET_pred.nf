#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_ADMET_pred
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.drug = null
params.task = null
params.unit = null

// Main process
process ADMET_PRED {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("ADMET_pred_results.json"), emit: results
    path("ADMET_pred_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pharmacology import ADMET_pred

# Run the tool
try:
    result = ADMET_pred(
    drug="${params.drug}",
    task="${params.task}",
    unit="${params.unit}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("ADMET_pred_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("ADMET_pred_output.txt", "w") as f:
    f.write("Biomni: Admet Pred Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("ADMET_pred completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_ADMET_PRED {
    take:
    // No file inputs

    main:
    ADMET_PRED()

    emit:
    results = ADMET_PRED.out.results
    output = ADMET_PRED.out.output
}

// Entry workflow
workflow {
    if (!params.drug) {
        error "Please provide --drug parameter"
    }
    if (!params.task) {
        error "Please provide --task parameter"
    }
    if (!params.unit) {
        error "Please provide --unit parameter"
    }


    BIOMNI_PHARMACOLOGY_ADMET_PRED()
}
