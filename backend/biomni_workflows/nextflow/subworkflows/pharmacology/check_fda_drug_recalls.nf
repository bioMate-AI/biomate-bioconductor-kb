#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_check_fda_drug_recalls
 * Check for FDA drug recalls and enforcement actions.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.drug_name = null
params.classification = null
params.date_range = null

// Main process
process CHECK_FDA_DRUG_RECALLS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("check_fda_drug_recalls_results.json"), emit: results
    path("check_fda_drug_recalls_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pharmacology import check_fda_drug_recalls

# Run the tool
try:
    result = check_fda_drug_recalls(
    drug_name="${params.drug_name}",
    classification="${params.classification}",
    date_range="${params.date_range}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("check_fda_drug_recalls_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("check_fda_drug_recalls_output.txt", "w") as f:
    f.write("Biomni: Check Fda Drug Recalls Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("check_fda_drug_recalls completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_CHECK_FDA_DRUG_RECALLS {
    take:
    // No file inputs

    main:
    CHECK_FDA_DRUG_RECALLS()

    emit:
    results = CHECK_FDA_DRUG_RECALLS.out.results
    output = CHECK_FDA_DRUG_RECALLS.out.output
}

// Entry workflow
workflow {
    if (!params.drug_name) {
        error "Please provide --drug_name parameter"
    }


    BIOMNI_PHARMACOLOGY_CHECK_FDA_DRUG_RECALLS()
}
