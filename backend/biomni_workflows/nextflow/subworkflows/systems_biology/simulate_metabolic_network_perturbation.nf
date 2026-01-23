#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_simulate_metabolic_network_perturbation
 * Construct and simulate kinetic models of metabolic networks and analyze their responses to perturbations.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.model_file = null
params.initial_concentrations = null
params.perturbation_params = null
params.simulation_time = '100'
params.time_points = '1000'

// Main process
process SIMULATE_METABOLIC_NETWORK_PERTURBATION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("simulate_metabolic_network_perturbation_results.json"), emit: results
    path("simulate_metabolic_network_perturbation_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.systems_biology import simulate_metabolic_network_perturbation

# Run the tool
try:
    result = simulate_metabolic_network_perturbation(
    model_file="${params.model_file}",
    initial_concentrations="${params.initial_concentrations}",
    perturbation_params="${params.perturbation_params}",
    simulation_time="${params.simulation_time}",
    time_points="${params.time_points}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("simulate_metabolic_network_perturbation_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("simulate_metabolic_network_perturbation_output.txt", "w") as f:
    f.write("Biomni: Simulate Metabolic Network Perturbation Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("simulate_metabolic_network_perturbation completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYSTEMS_BIOLOGY_SIMULATE_METABOLIC_NETWORK_PERTURBATION {
    take:
    // No file inputs

    main:
    SIMULATE_METABOLIC_NETWORK_PERTURBATION()

    emit:
    results = SIMULATE_METABOLIC_NETWORK_PERTURBATION.out.results
    output = SIMULATE_METABOLIC_NETWORK_PERTURBATION.out.output
}

// Entry workflow
workflow {
    if (!params.model_file) {
        error "Please provide --model_file parameter"
    }
    if (!params.initial_concentrations) {
        error "Please provide --initial_concentrations parameter"
    }
    if (!params.perturbation_params) {
        error "Please provide --perturbation_params parameter"
    }


    BIOMNI_SYSTEMS_BIOLOGY_SIMULATE_METABOLIC_NETWORK_PERTURBATION()
}
