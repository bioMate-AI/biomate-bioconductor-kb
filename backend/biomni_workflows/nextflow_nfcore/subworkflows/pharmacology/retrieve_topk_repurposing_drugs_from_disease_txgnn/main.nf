#!/usr/bin/env nextflow
/*
 * pharmacology/retrieve_topk_repurposing_drugs_from_disease_txgnn
 * This function computes TxGNN model predictions for drug repurposing. It takes in the paths to the data,
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Drug repurposing for diabetes using TxGNN model
params.disease_name = 'diabetes mellitus'
// Uses inline-generated mock TxGNN data (created in script)
params.data_lake_path = './mock_txgnn_data'
params.k = '5'

process RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("retrieve_topk_repurposing_drugs_from_disease_txgnn_results.json"), emit: results
    tuple val(meta), path("retrieve_topk_repurposing_drugs_from_disease_txgnn_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_DISEASE_NAME="${params.disease_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA_LAKE_PATH="${params.data_lake_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_K="${params.k?.toString()?.replace('"', '\\"') ?: 'null'}"

    # Create mock TxGNN prediction data for testing
    python3 << 'MOCKEOF'
import pickle
import os
import numpy as np

# Create mock TxGNN data directory
os.makedirs('./mock_txgnn_data', exist_ok=True)

# Create mock name mapping
name_mapping = {
    'id2name_drug': {
        'DRUG001': 'Metformin',
        'DRUG002': 'Sitagliptin',
        'DRUG003': 'Empagliflozin',
        'DRUG004': 'Liraglutide',
        'DRUG005': 'Dapagliflozin',
        'DRUG006': 'Pioglitazone',
        'DRUG007': 'Canagliflozin',
        'DRUG008': 'Semaglutide'
    }
}

# Create mock prediction results for diseases
np.random.seed(42)
predictions = {
    'diabetes mellitus': {
        'DRUG001': 2.5,  # Metformin - high score
        'DRUG002': 1.8,  # Sitagliptin
        'DRUG003': 2.2,  # Empagliflozin
        'DRUG004': 1.5,  # Liraglutide
        'DRUG005': 1.9,  # Dapagliflozin
        'DRUG006': 1.2,  # Pioglitazone
        'DRUG007': 1.7,  # Canagliflozin
        'DRUG008': 2.0   # Semaglutide
    },
    'hypertension': {
        'DRUG001': 0.8,
        'DRUG002': 0.5,
        'DRUG003': 1.5,
        'DRUG004': 0.3,
        'DRUG005': 1.4,
        'DRUG006': 0.6,
        'DRUG007': 1.3,
        'DRUG008': 0.7
    }
}

# Save mock data
with open('./mock_txgnn_data/txgnn_name_mapping.pkl', 'wb') as f:
    pickle.dump(name_mapping, f)

with open('./mock_txgnn_data/txgnn_prediction.pkl', 'wb') as f:
    pickle.dump(predictions, f)

print("Created mock TxGNN prediction data")
MOCKEOF

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import pickle
from difflib import get_close_matches
import numpy as np
import json
import os

def auto_convert(val):
    # Auto-convert string to appropriate type
    if val is None or val == '' or val == 'null':
        return None
    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    # Try float
    try:
        return float(val)
    except ValueError:
        pass
    # Return as string
    return val



def retrieve_topk_repurposing_drugs_from_disease_txgnn(disease_name, data_lake_path, k=5):
    '''This function computes TxGNN model predictions for drug repurposing. It takes in the paths to the data,
    the disease name, and returns a summary of the top K predicted drugs with their sigmoid-transformed scores.

    Args:
    - disease_name (str): The name of the disease for which the drug predictions are to be retrieved.
    - data_lake_path (str): The path to the data lake containing the TxGNN predictions.
    - k (int, optional): The number of top drug predictions to return. Defaults to 5.

    Returns:
    - str: A summary of the steps and the top K drug predictions with their scores.

    '''

    # Sigmoid function to convert raw prediction scores
    def sigmoid(x):
        return 1 / (1 + np.exp(-x))

    # Step 1: Load the mappings and prediction data from the provided paths
    name_mapping_path = data_lake_path + "/txgnn_name_mapping.pkl"
    result_path = data_lake_path + "/txgnn_prediction.pkl"

    with open(name_mapping_path, "rb") as f:
        mapping = pickle.load(f)

    with open(result_path, "rb") as f:
        result = pickle.load(f)

    # Step 2: Fuzzy match the disease name to find the closest match
    possible_diseases = result.keys()
    matched_disease = get_close_matches(disease_name, possible_diseases, n=1, cutoff=0.6)

    if not matched_disease:
        return f"Error: No matching disease found for '{disease_name}'. Please try a different name."

    matched_disease = matched_disease[0]

    # Step 3: Retrieve the prediction scores for the matched disease
    disease_predictions = result[matched_disease]

    # Step 4: Apply the sigmoid function to the raw prediction scores
    sigmoid_predictions = {drug_id: sigmoid(score) for drug_id, score in disease_predictions.items()}

    # Step 5: Sort the drugs by prediction score in descending order
    top_k_drugs = sorted(sigmoid_predictions.items(), key=lambda x: x[1], reverse=True)[:k]

    # Step 6: Map drug IDs to their names and format the results
    top_k_drug_names = [(mapping["id2name_drug"].get(drug_id, "Unknown Drug"), score) for drug_id, score in top_k_drugs]

    # Step 7: Create a human and LLM-friendly summary string
    summary = f"TxGNN Drug Repurposing Predictions for '{matched_disease}':\\n"
    summary += f"Top {k} predicted drugs and their corresponding prediction scores (post-sigmoid transformation):\\n"

    for i, (drug_name, score) in enumerate(top_k_drug_names, 1):
        summary += f"{i}. {drug_name} - Prediction Score: {score:.4f}\\n"

    summary += "\\nProcess Summary:\\n"
    summary += "- Fuzzy matching was used to match the input disease name to '{matched_disease}'.\\n"
    summary += "- Sigmoid function was applied to raw prediction scores to convert them into probabilities.\\n"
    summary += f"- The top {k} drugs were selected based on their prediction scores.\\n"

    return summary

# Execute the function
try:
    result = retrieve_topk_repurposing_drugs_from_disease_txgnn(
        disease_name=auto_convert(os.environ.get("PARAM_DISEASE_NAME", "")),
        data_lake_path=auto_convert(os.environ.get("PARAM_DATA_LAKE_PATH", "")),
        k=auto_convert(os.environ.get("PARAM_K", "5")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "retrieve_topk_repurposing_drugs_from_disease_txgnn",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("retrieve_topk_repurposing_drugs_from_disease_txgnn_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("retrieve_topk_repurposing_drugs_from_disease_txgnn_output.txt", "w") as f:
    f.write("Biomni: Retrieve Topk Repurposing Drugs From Disease Txgnn" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "retrieve_topk_repurposing_drugs_from_disease_txgnn"
    END_VERSIONS
    """
}

workflow RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN(ch_input)

    emit:
    results = RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN.out.results
    output = RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN.out.output
    versions = RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN_WORKFLOW(ch_input)

    RETRIEVE_TOPK_REPURPOSING_DRUGS_FROM_DISEASE_TXGNN_WORKFLOW.out.output.view { "Output: $it" }
}
