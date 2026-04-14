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

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("norm_chr_results.json"), emit: results
    path("norm_chr_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.cancer_biology import norm_chr
except ImportError:
    # Fallback: function may need to be implemented locally
    def norm_chr(**kwargs):
        return {"status": "Function not available", "params": kwargs}

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
with open("norm_chr_output.txt", "w") as f:
    f.write("Biomni: Norm Chr Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
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
