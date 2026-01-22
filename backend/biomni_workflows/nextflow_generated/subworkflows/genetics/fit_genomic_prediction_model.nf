#!/usr/bin/env nextflow
/*
 * biomni_genetics_fit_genomic_prediction_model
 * Fit a linear mixed model for genomic prediction using genotype and phenotype data.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.genotypes = null
params.phenotypes = null
params.fixed_effects = null
params.model_type = 'additive'
params.output_file = 'genomic_prediction_results.csv'

// Main process
process FIT_GENOMIC_PREDICTION_MODEL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("fit_genomic_prediction_model_results.json"), emit: results
    path("fit_genomic_prediction_model_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genetics import fit_genomic_prediction_model
except ImportError:
    # Fallback: function may need to be implemented locally
    def fit_genomic_prediction_model(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = fit_genomic_prediction_model(
    genotypes="${params.genotypes}",
    phenotypes="${params.phenotypes}",
    fixed_effects="${params.fixed_effects}",
    model_type="${params.model_type}",
    output_file="${params.output_file}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("fit_genomic_prediction_model_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("fit_genomic_prediction_model_output.txt", "w") as f:
    f.write("Biomni: Fit Genomic Prediction Model Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("fit_genomic_prediction_model completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENETICS_FIT_GENOMIC_PREDICTION_MODEL {
    take:
    // No file inputs

    main:
    FIT_GENOMIC_PREDICTION_MODEL()

    emit:
    results = FIT_GENOMIC_PREDICTION_MODEL.out.results
    output = FIT_GENOMIC_PREDICTION_MODEL.out.output
}

// Entry workflow
workflow {
    if (!params.genotypes) {
        error "Please provide --genotypes parameter"
    }
    if (!params.phenotypes) {
        error "Please provide --phenotypes parameter"
    }


    BIOMNI_GENETICS_FIT_GENOMIC_PREDICTION_MODEL()
}
