#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_analyze_accelerated_stability_of_pharmaceutical_formulations
 * Analyzes the stability of pharmaceutical formulations under accelerated storage conditions.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.formulations = null
params.storage_conditions = null
params.time_points = null

// Main process
process ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_accelerated_stability_of_pharmaceutical_formulations_results.json"), emit: results
    path("analyze_accelerated_stability_of_pharmaceutical_formulations_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pharmacology import analyze_accelerated_stability_of_pharmaceutical_formulations

# Run the tool
try:
    result = analyze_accelerated_stability_of_pharmaceutical_formulations(
    formulations="${params.formulations}",
    storage_conditions="${params.storage_conditions}",
    time_points="${params.time_points}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_accelerated_stability_of_pharmaceutical_formulations_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_accelerated_stability_of_pharmaceutical_formulations_output.txt", "w") as f:
    f.write("Biomni: Analyze Accelerated Stability Of Pharmaceutical Formulations Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_accelerated_stability_of_pharmaceutical_formulations completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS {
    take:
    // No file inputs

    main:
    ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS()

    emit:
    results = ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS.out.results
    output = ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS.out.output
}

// Entry workflow
workflow {
    if (!params.formulations) {
        error "Please provide --formulations parameter"
    }
    if (!params.storage_conditions) {
        error "Please provide --storage_conditions parameter"
    }
    if (!params.time_points) {
        error "Please provide --time_points parameter"
    }


    BIOMNI_PHARMACOLOGY_ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS()
}
