#!/usr/bin/env nextflow
/*
 * biomni_immunology_estimate_cell_cycle_phase_durations
 * Estimate cell cycle phase durations using dual-nucleoside pulse labeling data and mathematical modeling.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.flow_cytometry_data = null
params.initial_estimates = null

// Main process
process ESTIMATE_CELL_CYCLE_PHASE_DURATIONS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("estimate_cell_cycle_phase_durations_results.json"), emit: results
    path("estimate_cell_cycle_phase_durations_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.immunology import estimate_cell_cycle_phase_durations

# Run the tool
try:
    result = estimate_cell_cycle_phase_durations(
    flow_cytometry_data="${params.flow_cytometry_data}",
    initial_estimates="${params.initial_estimates}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("estimate_cell_cycle_phase_durations_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("estimate_cell_cycle_phase_durations_output.txt", "w") as f:
    f.write("Biomni: Estimate Cell Cycle Phase Durations Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("estimate_cell_cycle_phase_durations completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_IMMUNOLOGY_ESTIMATE_CELL_CYCLE_PHASE_DURATIONS {
    take:
    // No file inputs

    main:
    ESTIMATE_CELL_CYCLE_PHASE_DURATIONS()

    emit:
    results = ESTIMATE_CELL_CYCLE_PHASE_DURATIONS.out.results
    output = ESTIMATE_CELL_CYCLE_PHASE_DURATIONS.out.output
}

// Entry workflow
workflow {
    if (!params.flow_cytometry_data) {
        error "Please provide --flow_cytometry_data parameter"
    }
    if (!params.initial_estimates) {
        error "Please provide --initial_estimates parameter"
    }


    BIOMNI_IMMUNOLOGY_ESTIMATE_CELL_CYCLE_PHASE_DURATIONS()
}
