#!/usr/bin/env nextflow
/*
 * biomni_biophysics_predict_protein_disorder_regions
 * Predicts intrinsically disordered regions (IDRs) in a protein sequence using IUPred2A.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.protein_sequence = null
params.threshold = '0.5'
params.output_file = 'disorder_prediction_results.csv'

// Main process
process PREDICT_PROTEIN_DISORDER_REGIONS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("predict_protein_disorder_regions_results.json"), emit: results
    path("predict_protein_disorder_regions_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.biophysics import predict_protein_disorder_regions

# Run the tool
try:
    result = predict_protein_disorder_regions(
    protein_sequence="${params.protein_sequence}",
    threshold="${params.threshold}",
    output_file="${params.output_file}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("predict_protein_disorder_regions_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("predict_protein_disorder_regions_output.txt", "w") as f:
    f.write("Biomni: Predict Protein Disorder Regions Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("predict_protein_disorder_regions completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOPHYSICS_PREDICT_PROTEIN_DISORDER_REGIONS {
    take:
    // No file inputs

    main:
    PREDICT_PROTEIN_DISORDER_REGIONS()

    emit:
    results = PREDICT_PROTEIN_DISORDER_REGIONS.out.results
    output = PREDICT_PROTEIN_DISORDER_REGIONS.out.output
}

// Entry workflow
workflow {
    if (!params.protein_sequence) {
        error "Please provide --protein_sequence parameter"
    }


    BIOMNI_BIOPHYSICS_PREDICT_PROTEIN_DISORDER_REGIONS()
}
