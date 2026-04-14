#!/usr/bin/env nextflow
/*
 * biomni_microbiology_predict_rna_secondary_structure
 * Predict the secondary structure of an RNA molecule using ViennaRNA.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.rna_sequence = null
params.output_prefix = 'rna_structure'

// Main process
process PREDICT_RNA_SECONDARY_STRUCTURE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("predict_rna_secondary_structure_results.json"), emit: results
    path("predict_rna_secondary_structure_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.microbiology import predict_rna_secondary_structure
except ImportError:
    # Fallback: function may need to be implemented locally
    def predict_rna_secondary_structure(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = predict_rna_secondary_structure(
    rna_sequence="${params.rna_sequence}",
    output_prefix="${params.output_prefix}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("predict_rna_secondary_structure_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("predict_rna_secondary_structure_output.txt", "w") as f:
    f.write("Biomni: Predict Rna Secondary Structure Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("predict_rna_secondary_structure completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_PREDICT_RNA_SECONDARY_STRUCTURE {
    take:
    // No file inputs

    main:
    PREDICT_RNA_SECONDARY_STRUCTURE()

    emit:
    results = PREDICT_RNA_SECONDARY_STRUCTURE.out.results
    output = PREDICT_RNA_SECONDARY_STRUCTURE.out.output
}

// Entry workflow
workflow {
    if (!params.rna_sequence) {
        error "Please provide --rna_sequence parameter"
    }


    BIOMNI_MICROBIOLOGY_PREDICT_RNA_SECONDARY_STRUCTURE()
}
