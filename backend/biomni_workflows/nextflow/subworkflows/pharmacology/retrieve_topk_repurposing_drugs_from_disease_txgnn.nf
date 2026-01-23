#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_retrieve_topk_repurposing_drugs_from_disease_txgnn
 * This function computes TxGNN model predictions for drug repurposing. It takes in the paths to the data,
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.disease_name = null
params.data_lake_path = null
params.k = '5'

// Main process
process RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("retrieve_topk_repurposing_drugs_from_disease_txgnn_results.json"), emit: results
    path("retrieve_topk_repurposing_drugs_from_disease_txgnn_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pharmacology import retrieve_topk_repurposing_drugs_from_disease_txgnn

# Run the tool
try:
    result = retrieve_topk_repurposing_drugs_from_disease_txgnn(
    disease_name="${params.disease_name}",
    data_lake_path="${params.data_lake_path}",
    k="${params.k}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("retrieve_topk_repurposing_drugs_from_disease_txgnn_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("retrieve_topk_repurposing_drugs_from_disease_txgnn_output.txt", "w") as f:
    f.write("Biomni: Retrieve Topk Repurposing Drugs From Disease Txgnn Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("retrieve_topk_repurposing_drugs_from_disease_txgnn completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN {
    take:
    // No file inputs

    main:
    RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN()

    emit:
    results = RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN.out.results
    output = RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN.out.output
}

// Entry workflow
workflow {
    if (!params.disease_name) {
        error "Please provide --disease_name parameter"
    }
    if (!params.data_lake_path) {
        error "Please provide --data_lake_path parameter"
    }


    BIOMNI_PHARMACOLOGY_RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN()
}
