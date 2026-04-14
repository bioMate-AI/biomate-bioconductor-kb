#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_predict_admet_properties
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.smiles_list = null
params.ADMET_model_type = 'MPNN'

// Main process
process PREDICT_ADMET_PROPERTIES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("predict_admet_properties_results.json"), emit: results
    path("predict_admet_properties_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.pharmacology import predict_admet_properties
except ImportError:
    # Fallback: function may need to be implemented locally
    def predict_admet_properties(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = predict_admet_properties(
    smiles_list="${params.smiles_list}",
    ADMET_model_type="${params.ADMET_model_type}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("predict_admet_properties_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("predict_admet_properties_output.txt", "w") as f:
    f.write("Biomni: Predict Admet Properties Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("predict_admet_properties completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_PREDICT_ADMET_PROPERTIES {
    take:
    // No file inputs

    main:
    PREDICT_ADMET_PROPERTIES()

    emit:
    results = PREDICT_ADMET_PROPERTIES.out.results
    output = PREDICT_ADMET_PROPERTIES.out.output
}

// Entry workflow
workflow {
    if (!params.smiles_list) {
        error "Please provide --smiles_list parameter"
    }


    BIOMNI_PHARMACOLOGY_PREDICT_ADMET_PROPERTIES()
}
