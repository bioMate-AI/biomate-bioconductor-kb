#!/usr/bin/env nextflow
/*
 * biomni_database_get_hpo_names
 * Retrieve the names of given HPO terms.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.hpo_terms = null
params.data_lake_path = null

// Main process
process GET_HPO_NAMES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_hpo_names_results.json"), emit: results
    path("get_hpo_names_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.database import get_hpo_names

# Run the tool
try:
    result = get_hpo_names(
    hpo_terms="${params.hpo_terms}",
    data_lake_path="${params.data_lake_path}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_hpo_names_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("get_hpo_names_output.txt", "w") as f:
    f.write("Biomni: Get Hpo Names Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("get_hpo_names completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_DATABASE_GET_HPO_NAMES {
    take:
    // No file inputs

    main:
    GET_HPO_NAMES()

    emit:
    results = GET_HPO_NAMES.out.results
    output = GET_HPO_NAMES.out.output
}

// Entry workflow
workflow {
    if (!params.hpo_terms) {
        error "Please provide --hpo_terms parameter"
    }
    if (!params.data_lake_path) {
        error "Please provide --data_lake_path parameter"
    }


    BIOMNI_DATABASE_GET_HPO_NAMES()
}
