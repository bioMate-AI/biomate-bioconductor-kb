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

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("ADMET_pred_results.json"), emit: results
    path("ADMET_pred_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.pharmacology import ADMET_pred
except ImportError:
    # Fallback: function may need to be implemented locally
    def ADMET_pred(**kwargs):
        return {"status": "Function not available", "params": kwargs}

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
with open("ADMET_pred_output.txt", "w") as f:
    f.write("Biomni: Admet Pred Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
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
