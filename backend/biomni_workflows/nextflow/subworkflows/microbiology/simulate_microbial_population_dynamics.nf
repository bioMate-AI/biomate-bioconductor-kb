#!/usr/bin/env nextflow
/*
 * biomni_microbiology_simulate_microbial_population_dynamics
 * Performs stochastic simulation of microbial population dynamics using the Gillespie algorithm.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.initial_populations = null
params.growth_rates = null
params.clearance_rates = null
params.carrying_capacities = null
params.max_time = '100'
params.num_simulations = '100'
params.time_points = '100'

// Main process
process SIMULATE_MICROBIAL_POPULATION_DYNAMICS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("simulate_microbial_population_dynamics_results.json"), emit: results
    path("simulate_microbial_population_dynamics_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.microbiology import simulate_microbial_population_dynamics

# Run the tool
try:
    result = simulate_microbial_population_dynamics(
    initial_populations="${params.initial_populations}",
    growth_rates="${params.growth_rates}",
    clearance_rates="${params.clearance_rates}",
    carrying_capacities="${params.carrying_capacities}",
    max_time="${params.max_time}",
    num_simulations="${params.num_simulations}",
    time_points="${params.time_points}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("simulate_microbial_population_dynamics_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("simulate_microbial_population_dynamics_output.txt", "w") as f:
    f.write("Biomni: Simulate Microbial Population Dynamics Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("simulate_microbial_population_dynamics completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_SIMULATE_MICROBIAL_POPULATION_DYNAMICS {
    take:
    // No file inputs

    main:
    SIMULATE_MICROBIAL_POPULATION_DYNAMICS()

    emit:
    results = SIMULATE_MICROBIAL_POPULATION_DYNAMICS.out.results
    output = SIMULATE_MICROBIAL_POPULATION_DYNAMICS.out.output
}

// Entry workflow
workflow {
    if (!params.initial_populations) {
        error "Please provide --initial_populations parameter"
    }
    if (!params.growth_rates) {
        error "Please provide --growth_rates parameter"
    }
    if (!params.clearance_rates) {
        error "Please provide --clearance_rates parameter"
    }
    if (!params.carrying_capacities) {
        error "Please provide --carrying_capacities parameter"
    }


    BIOMNI_MICROBIOLOGY_SIMULATE_MICROBIAL_POPULATION_DYNAMICS()
}
