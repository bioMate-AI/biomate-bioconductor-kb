#!/usr/bin/env nextflow
/*
 * biomni_cancer_biology_norm_chr
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.x = null

// Main process
process NORM_CHR {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("norm_chr_results.json"), emit: results
    path("norm_chr_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.cancer_biology import norm_chr

# Run the tool
try:
    result = norm_chr(
    x="${params.x}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("norm_chr_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("norm_chr_output.txt", "w") as f:
    f.write("Biomni: Norm Chr Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("norm_chr completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_CANCER_BIOLOGY_NORM_CHR {
    take:
    // No file inputs

    main:
    NORM_CHR()

    emit:
    results = NORM_CHR.out.results
    output = NORM_CHR.out.output
}

// Entry workflow
workflow {
    if (!params.x) {
        error "Please provide --x parameter"
    }


    BIOMNI_CANCER_BIOLOGY_NORM_CHR()
}
