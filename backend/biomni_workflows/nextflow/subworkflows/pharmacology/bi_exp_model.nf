#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_bi_exp_model
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.A = null
params.alpha = null
params.B = null
params.beta = null

// Main process
process BI_EXP_MODEL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("bi_exp_model_results.json"), emit: results
    path("bi_exp_model_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pharmacology import bi_exp_model

# Run the tool
try:
    result = bi_exp_model(
    t="${params.t}",
    A="${params.A}",
    alpha="${params.alpha}",
    B="${params.B}",
    beta="${params.beta}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("bi_exp_model_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("bi_exp_model_output.txt", "w") as f:
    f.write("Biomni: Bi Exp Model Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("bi_exp_model completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_BI_EXP_MODEL {
    take:
    // No file inputs

    main:
    BI_EXP_MODEL()

    emit:
    results = BI_EXP_MODEL.out.results
    output = BI_EXP_MODEL.out.output
}

// Entry workflow
workflow {
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.A) {
        error "Please provide --A parameter"
    }
    if (!params.alpha) {
        error "Please provide --alpha parameter"
    }
    if (!params.B) {
        error "Please provide --B parameter"
    }
    if (!params.beta) {
        error "Please provide --beta parameter"
    }


    BIOMNI_PHARMACOLOGY_BI_EXP_MODEL()
}
