#!/usr/bin/env nextflow
/*
 * biomni_microbiology_simulate_generalized_lotka_volterra_dynamics
 * Simulate microbial community dynamics using the Generalized Lotka-Volterra (gLV) model.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.initial_abundances = null
params.growth_rates = null
params.interaction_matrix = null
params.time_points = null
params.output_file = 'glv_simulation_results.csv'

// Main process
process SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("simulate_generalized_lotka_volterra_dynamics_results.json"), emit: results
    path("simulate_generalized_lotka_volterra_dynamics_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.microbiology import simulate_generalized_lotka_volterra_dynamics

# Run the tool
try:
    result = simulate_generalized_lotka_volterra_dynamics(
    initial_abundances="${params.initial_abundances}",
    growth_rates="${params.growth_rates}",
    interaction_matrix="${params.interaction_matrix}",
    time_points="${params.time_points}",
    output_file="${params.output_file}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("simulate_generalized_lotka_volterra_dynamics_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("simulate_generalized_lotka_volterra_dynamics_output.txt", "w") as f:
    f.write("Biomni: Simulate Generalized Lotka Volterra Dynamics Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("simulate_generalized_lotka_volterra_dynamics completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS {
    take:
    // No file inputs

    main:
    SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS()

    emit:
    results = SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS.out.results
    output = SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS.out.output
}

// Entry workflow
workflow {
    if (!params.initial_abundances) {
        error "Please provide --initial_abundances parameter"
    }
    if (!params.growth_rates) {
        error "Please provide --growth_rates parameter"
    }
    if (!params.interaction_matrix) {
        error "Please provide --interaction_matrix parameter"
    }
    if (!params.time_points) {
        error "Please provide --time_points parameter"
    }


    BIOMNI_MICROBIOLOGY_SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS()
}
