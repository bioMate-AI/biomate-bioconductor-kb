#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_analyze_radiolabeled_antibody_biodistribution
 * Analyze biodistribution and pharmacokinetic profile of radiolabeled antibodies.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.time_points = null
params.tissue_data = null

// Main process
process ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_radiolabeled_antibody_biodistribution_results.json"), emit: results
    path("analyze_radiolabeled_antibody_biodistribution_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pharmacology import analyze_radiolabeled_antibody_biodistribution

# Run the tool
try:
    result = analyze_radiolabeled_antibody_biodistribution(
    time_points="${params.time_points}",
    tissue_data="${params.tissue_data}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_radiolabeled_antibody_biodistribution_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_radiolabeled_antibody_biodistribution_output.txt", "w") as f:
    f.write("Biomni: Analyze Radiolabeled Antibody Biodistribution Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_radiolabeled_antibody_biodistribution completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION {
    take:
    // No file inputs

    main:
    ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION()

    emit:
    results = ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION.out.results
    output = ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION.out.output
}

// Entry workflow
workflow {
    if (!params.time_points) {
        error "Please provide --time_points parameter"
    }
    if (!params.tissue_data) {
        error "Please provide --tissue_data parameter"
    }


    BIOMNI_PHARMACOLOGY_ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION()
}
