#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_perform_flux_balance_analysis
 * Perform Flux Balance Analysis (FBA) on a genome-scale metabolic network model.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.model_file = null
params.constraints = null
params.objective_reaction = null
params.output_file = 'fba_results.csv'

// Main process
process PERFORM_FLUX_BALANCE_ANALYSIS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("perform_flux_balance_analysis_results.json"), emit: results
    path("perform_flux_balance_analysis_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.systems_biology import perform_flux_balance_analysis

# Run the tool
try:
    result = perform_flux_balance_analysis(
    model_file="${params.model_file}",
    constraints="${params.constraints}",
    objective_reaction="${params.objective_reaction}",
    output_file="${params.output_file}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("perform_flux_balance_analysis_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("perform_flux_balance_analysis_output.txt", "w") as f:
    f.write("Biomni: Perform Flux Balance Analysis Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("perform_flux_balance_analysis completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYSTEMS_BIOLOGY_PERFORM_FLUX_BALANCE_ANALYSIS {
    take:
    // No file inputs

    main:
    PERFORM_FLUX_BALANCE_ANALYSIS()

    emit:
    results = PERFORM_FLUX_BALANCE_ANALYSIS.out.results
    output = PERFORM_FLUX_BALANCE_ANALYSIS.out.output
}

// Entry workflow
workflow {
    if (!params.model_file) {
        error "Please provide --model_file parameter"
    }


    BIOMNI_SYSTEMS_BIOLOGY_PERFORM_FLUX_BALANCE_ANALYSIS()
}
