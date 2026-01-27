#!/usr/bin/env nextflow
/*
 * pharmacology/predict_admet_properties
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Common drug SMILES (aspirin, caffeine, ibuprofen)
params.smiles_list = '["CC(=O)OC1=CC=CC=C1C(=O)O", "CN1C=NC2=C1C(=O)N(C(=O)N2C)C", "CC(C)CC1=CC=C(C=C1)C(C)C(=O)O"]'
params.ADMET_model_type = 'MPNN'

process PREDICT_ADMET_PROPERTIES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("predict_admet_properties_results.json"), emit: results
    tuple val(meta), path("predict_admet_properties_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SMILES_LIST="${params.smiles_list?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ADMET_MODEL_TYPE="${params.ADMET_model_type?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import subprocess
import sys
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



def predict_admet_properties(smiles_list, ADMET_model_type="MPNN"):
    try:
        from DeepPurpose import CompoundPred, utils
    except Exception:
        subprocess.run([sys.executable, "-m", "pip", "install", "DeepPurpose"], check=False)
        from DeepPurpose import CompoundPred, utils

    # Define available model types
    available_model_types = ["MPNN", "CNN", "Morgan"]

    # Check if the provided model type is valid
    if ADMET_model_type not in available_model_types:
        return f"Error: Invalid ADMET model type '{ADMET_model_type}'. Available options are: {', '.join(available_model_types)}."

    # Load pretrained ADMET models only once
    model_ADMETs = {}
    tasks = [
        "AqSolDB",
        "Caco2",
        "HIA",
        "Pgp_inhibitor",
        "Bioavailability",
        "BBB_MolNet",
        "PPBR",
        "CYP2C19",
        "CYP2D6",
        "CYP3A4",
        "CYP1A2",
        "CYP2C9",
        "ClinTox",
        "Lipo_AZ",
        "Half_life_eDrug3D",
        "Clearance_eDrug3D",
    ]

    for task in tasks:
        model_ADMETs[task + "_" + ADMET_model_type + "_model"] = CompoundPred.model_pretrained(
            model=task + "_" + ADMET_model_type + "_model"
        )

    # Helper function for ADMET prediction
    def ADMET_pred(drug, task, unit):
        model = model_ADMETs[task + "_" + ADMET_model_type + "_model"]
        X_pred = utils.data_process(
            X_drug=[drug],
            y=[0],
            drug_encoding=ADMET_model_type,
            split_method="no_split",
        )
        y_pred = model.predict(X_pred)[0]

        if unit == "%":
            y_pred = y_pred * 100

        return f"{y_pred:.2f} " + unit

    # Initialize research log string
    research_log = "Research Log for ADMET Predictions:\\n"
    research_log += "-------------------------------------\\n"

    # Process each SMILES string in the list
    for smiles in smiles_list:
        research_log += f"\\nCompound SMILES: {smiles}\\n"
        research_log += "Predicted ADMET properties:\\n"

        # Physiochemical properties
        solubility = ADMET_pred(smiles, "AqSolDB", "log mol/L")
        lipophilicity = ADMET_pred(smiles, "Lipo_AZ", "(log-ratio)")
        research_log += f"- Solubility: {solubility}\\n"
        research_log += f"- Lipophilicity: {lipophilicity}\\n"

        # Absorption
        caco2 = ADMET_pred(smiles, "Caco2", "cm/s")
        hia = ADMET_pred(smiles, "HIA", "%")
        pgp = ADMET_pred(smiles, "Pgp_inhibitor", "%")
        bioavail = ADMET_pred(smiles, "Bioavailability", "%")
        research_log += f"- Absorption (Caco-2 permeability): {caco2}\\n"
        research_log += f"- Absorption (HIA): {hia}\\n"
        research_log += f"- Absorption (Pgp Inhibitor): {pgp}\\n"
        research_log += f"- Absorption (Bioavailability): {bioavail}\\n"

        # Distribution
        bbb = ADMET_pred(smiles, "BBB_MolNet", "%")
        ppbr = ADMET_pred(smiles, "PPBR", "%")
        research_log += f"- Distribution (BBB permeation): {bbb}\\n"
        research_log += f"- Distribution (PPBR): {ppbr}\\n"

        # Metabolism
        cyp2c19 = ADMET_pred(smiles, "CYP2C19", "%")
        cyp2d6 = ADMET_pred(smiles, "CYP2D6", "%")
        cyp3a4 = ADMET_pred(smiles, "CYP3A4", "%")
        cyp1a2 = ADMET_pred(smiles, "CYP1A2", "%")
        cyp2c9 = ADMET_pred(smiles, "CYP2C9", "%")
        research_log += f"- Metabolism (CYP2C19): {cyp2c19}\\n"
        research_log += f"- Metabolism (CYP2D6): {cyp2d6}\\n"
        research_log += f"- Metabolism (CYP3A4): {cyp3a4}\\n"
        research_log += f"- Metabolism (CYP1A2): {cyp1a2}\\n"
        research_log += f"- Metabolism (CYP2C9): {cyp2c9}\\n"

        # Excretion
        half_life = ADMET_pred(smiles, "Half_life_eDrug3D", "h")
        clearance = ADMET_pred(smiles, "Clearance_eDrug3D", "mL/min/kg")
        research_log += f"- Excretion (Half-life): {half_life}\\n"
        research_log += f"- Excretion (Clearance): {clearance}\\n"

        # Clinical Toxicity
        clinical_toxicity = ADMET_pred(smiles, "ClinTox", "%")
        research_log += f"- Clinical Toxicity: {clinical_toxicity}\\n"

        research_log += "-------------------------------------\\n"

    return research_log

# Execute the function
try:
    result = predict_admet_properties(
        smiles_list=auto_convert(os.environ.get("PARAM_SMILES_LIST", "")),
        ADMET_model_type=auto_convert(os.environ.get("PARAM_ADMET_MODEL_TYPE", "MPNN")),
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
    "function": "predict_admet_properties",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("predict_admet_properties_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("predict_admet_properties_output.txt", "w") as f:
    f.write("Biomni: Predict Admet Properties" + NL)
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
        biomni_function: "predict_admet_properties"
    END_VERSIONS
    """
}

workflow PREDICT_ADMET_PROPERTIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PREDICT_ADMET_PROPERTIES(ch_input)

    emit:
    results = PREDICT_ADMET_PROPERTIES.out.results
    output = PREDICT_ADMET_PROPERTIES.out.output
    versions = PREDICT_ADMET_PROPERTIES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PREDICT_ADMET_PROPERTIES_WORKFLOW(ch_input)

    PREDICT_ADMET_PROPERTIES_WORKFLOW.out.output.view { "Output: $it" }
}
