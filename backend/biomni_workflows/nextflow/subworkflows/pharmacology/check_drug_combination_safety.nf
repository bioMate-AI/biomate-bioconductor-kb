#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_check_drug_combination_safety
 * Analyze safety of a drug combination for potential interactions.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.drug_list = null
params.include_mechanisms = 'True'
params.include_management = 'True'
params.data_lake_path = null

// Main process
process CHECK_DRUG_COMBINATION_SAFETY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("check_drug_combination_safety_results.json"), emit: results
    path("check_drug_combination_safety_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pharmacology import check_drug_combination_safety

# Run the tool
try:
    result = check_drug_combination_safety(
    drug_list="${params.drug_list}",
    include_mechanisms="${params.include_mechanisms}",
    include_management="${params.include_management}",
    data_lake_path="${params.data_lake_path}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("check_drug_combination_safety_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("check_drug_combination_safety_output.txt", "w") as f:
    f.write("Biomni: Check Drug Combination Safety Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("check_drug_combination_safety completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_CHECK_DRUG_COMBINATION_SAFETY {
    take:
    // No file inputs

    main:
    CHECK_DRUG_COMBINATION_SAFETY()

    emit:
    results = CHECK_DRUG_COMBINATION_SAFETY.out.results
    output = CHECK_DRUG_COMBINATION_SAFETY.out.output
}

// Entry workflow
workflow {
    if (!params.drug_list) {
        error "Please provide --drug_list parameter"
    }


    BIOMNI_PHARMACOLOGY_CHECK_DRUG_COMBINATION_SAFETY()
}
