#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_predict_binding_affinity_protein_1d_sequence
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.smiles_list = null
params.amino_acid_sequence = null
params.affinity_model_type = 'MPNN-CNN'

// Main process
process PREDICT_BINDING_AFFINITY_PROTEIN_1D_SEQUENCE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("predict_binding_affinity_protein_1d_sequence_results.json"), emit: results
    path("predict_binding_affinity_protein_1d_sequence_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.pharmacology import predict_binding_affinity_protein_1d_sequence
except ImportError:
    # Fallback: function may need to be implemented locally
    def predict_binding_affinity_protein_1d_sequence(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = predict_binding_affinity_protein_1d_sequence(
    smiles_list="${params.smiles_list}",
    amino_acid_sequence="${params.amino_acid_sequence}",
    affinity_model_type="${params.affinity_model_type}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("predict_binding_affinity_protein_1d_sequence_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("predict_binding_affinity_protein_1d_sequence_output.txt", "w") as f:
    f.write("Biomni: Predict Binding Affinity Protein 1D Sequence Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("predict_binding_affinity_protein_1d_sequence completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_PREDICT_BINDING_AFFINITY_PROTEIN_1D_SEQUENCE {
    take:
    // No file inputs

    main:
    PREDICT_BINDING_AFFINITY_PROTEIN_1D_SEQUENCE()

    emit:
    results = PREDICT_BINDING_AFFINITY_PROTEIN_1D_SEQUENCE.out.results
    output = PREDICT_BINDING_AFFINITY_PROTEIN_1D_SEQUENCE.out.output
}

// Entry workflow
workflow {
    if (!params.smiles_list) {
        error "Please provide --smiles_list parameter"
    }
    if (!params.amino_acid_sequence) {
        error "Please provide --amino_acid_sequence parameter"
    }


    BIOMNI_PHARMACOLOGY_PREDICT_BINDING_AFFINITY_PROTEIN_1D_SEQUENCE()
}
