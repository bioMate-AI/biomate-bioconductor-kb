#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_find_alternative_drugs_ddinter
 * Find alternative drugs that don't interact with contraindicated drugs.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.target_drug = null
params.contraindicated_drugs = null
params.therapeutic_class = null
params.data_lake_path = null

// Main process
process FIND_ALTERNATIVE_DRUGS_DDINTER {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("find_alternative_drugs_ddinter_results.json"), emit: results
    path("find_alternative_drugs_ddinter_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pharmacology import find_alternative_drugs_ddinter

# Run the tool
try:
    result = find_alternative_drugs_ddinter(
    target_drug="${params.target_drug}",
    contraindicated_drugs="${params.contraindicated_drugs}",
    therapeutic_class="${params.therapeutic_class}",
    data_lake_path="${params.data_lake_path}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("find_alternative_drugs_ddinter_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("find_alternative_drugs_ddinter_output.txt", "w") as f:
    f.write("Biomni: Find Alternative Drugs Ddinter Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("find_alternative_drugs_ddinter completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_FIND_ALTERNATIVE_DRUGS_DDINTER {
    take:
    // No file inputs

    main:
    FIND_ALTERNATIVE_DRUGS_DDINTER()

    emit:
    results = FIND_ALTERNATIVE_DRUGS_DDINTER.out.results
    output = FIND_ALTERNATIVE_DRUGS_DDINTER.out.output
}

// Entry workflow
workflow {
    if (!params.target_drug) {
        error "Please provide --target_drug parameter"
    }
    if (!params.contraindicated_drugs) {
        error "Please provide --contraindicated_drugs parameter"
    }


    BIOMNI_PHARMACOLOGY_FIND_ALTERNATIVE_DRUGS_DDINTER()
}
