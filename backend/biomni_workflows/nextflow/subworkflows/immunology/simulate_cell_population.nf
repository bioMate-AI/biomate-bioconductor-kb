#!/usr/bin/env nextflow
/*
 * biomni_immunology_simulate_cell_population
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.time_points = null
params.g1_duration = null
params.s_duration = null
params.g2m_duration = null
params.death_rate = null

// Main process
process SIMULATE_CELL_POPULATION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("simulate_cell_population_results.json"), emit: results
    path("simulate_cell_population_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.immunology import simulate_cell_population

# Run the tool
try:
    result = simulate_cell_population(
    time_points="${params.time_points}",
    g1_duration="${params.g1_duration}",
    s_duration="${params.s_duration}",
    g2m_duration="${params.g2m_duration}",
    death_rate="${params.death_rate}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("simulate_cell_population_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("simulate_cell_population_output.txt", "w") as f:
    f.write("Biomni: Simulate Cell Population Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("simulate_cell_population completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_IMMUNOLOGY_SIMULATE_CELL_POPULATION {
    take:
    // No file inputs

    main:
    SIMULATE_CELL_POPULATION()

    emit:
    results = SIMULATE_CELL_POPULATION.out.results
    output = SIMULATE_CELL_POPULATION.out.output
}

// Entry workflow
workflow {
    if (!params.time_points) {
        error "Please provide --time_points parameter"
    }
    if (!params.g1_duration) {
        error "Please provide --g1_duration parameter"
    }
    if (!params.s_duration) {
        error "Please provide --s_duration parameter"
    }
    if (!params.g2m_duration) {
        error "Please provide --g2m_duration parameter"
    }
    if (!params.death_rate) {
        error "Please provide --death_rate parameter"
    }


    BIOMNI_IMMUNOLOGY_SIMULATE_CELL_POPULATION()
}
