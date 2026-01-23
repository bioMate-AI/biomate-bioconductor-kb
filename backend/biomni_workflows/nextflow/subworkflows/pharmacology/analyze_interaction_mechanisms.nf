#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_analyze_interaction_mechanisms
 * Analyze interaction mechanisms between two specific drugs.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.drug_pair = null
params.detailed_analysis = 'True'
params.data_lake_path = null

// Main process
process ANALYZE_INTERACTION_MECHANISMS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_interaction_mechanisms_results.json"), emit: results
    path("analyze_interaction_mechanisms_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pharmacology import analyze_interaction_mechanisms

# Run the tool
try:
    result = analyze_interaction_mechanisms(
    drug_pair="${params.drug_pair}",
    detailed_analysis="${params.detailed_analysis}",
    data_lake_path="${params.data_lake_path}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_interaction_mechanisms_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_interaction_mechanisms_output.txt", "w") as f:
    f.write("Biomni: Analyze Interaction Mechanisms Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_interaction_mechanisms completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_ANALYZE_INTERACTION_MECHANISMS {
    take:
    // No file inputs

    main:
    ANALYZE_INTERACTION_MECHANISMS()

    emit:
    results = ANALYZE_INTERACTION_MECHANISMS.out.results
    output = ANALYZE_INTERACTION_MECHANISMS.out.output
}

// Entry workflow
workflow {
    if (!params.drug_pair) {
        error "Please provide --drug_pair parameter"
    }


    BIOMNI_PHARMACOLOGY_ANALYZE_INTERACTION_MECHANISMS()
}
