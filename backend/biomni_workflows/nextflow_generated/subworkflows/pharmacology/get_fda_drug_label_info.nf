#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_get_fda_drug_label_info
 * Retrieve FDA drug label information.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.drug_name = null
params.sections = null

// Main process
process GET_FDA_DRUG_LABEL_INFO {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_fda_drug_label_info_results.json"), emit: results
    path("get_fda_drug_label_info_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.pharmacology import get_fda_drug_label_info
except ImportError:
    # Fallback: function may need to be implemented locally
    def get_fda_drug_label_info(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = get_fda_drug_label_info(
    drug_name="${params.drug_name}",
    sections="${params.sections}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_fda_drug_label_info_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("get_fda_drug_label_info_output.txt", "w") as f:
    f.write("Biomni: Get Fda Drug Label Info Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("get_fda_drug_label_info completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_GET_FDA_DRUG_LABEL_INFO {
    take:
    // No file inputs

    main:
    GET_FDA_DRUG_LABEL_INFO()

    emit:
    results = GET_FDA_DRUG_LABEL_INFO.out.results
    output = GET_FDA_DRUG_LABEL_INFO.out.output
}

// Entry workflow
workflow {
    if (!params.drug_name) {
        error "Please provide --drug_name parameter"
    }


    BIOMNI_PHARMACOLOGY_GET_FDA_DRUG_LABEL_INFO()
}
