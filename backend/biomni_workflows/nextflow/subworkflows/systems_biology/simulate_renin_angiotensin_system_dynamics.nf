#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_simulate_renin_angiotensin_system_dynamics
 * Simulate the time-dependent concentrations of renin-angiotensin system (RAS) components.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.initial_concentrations = null
params.rate_constants = null
params.feedback_params = null
params.simulation_time = '48'
params.time_points = '100'

// Main process
process SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("simulate_renin_angiotensin_system_dynamics_results.json"), emit: results
    path("simulate_renin_angiotensin_system_dynamics_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.systems_biology import simulate_renin_angiotensin_system_dynamics

# Run the tool
try:
    result = simulate_renin_angiotensin_system_dynamics(
    initial_concentrations="${params.initial_concentrations}",
    rate_constants="${params.rate_constants}",
    feedback_params="${params.feedback_params}",
    simulation_time="${params.simulation_time}",
    time_points="${params.time_points}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("simulate_renin_angiotensin_system_dynamics_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("simulate_renin_angiotensin_system_dynamics_output.txt", "w") as f:
    f.write("Biomni: Simulate Renin Angiotensin System Dynamics Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("simulate_renin_angiotensin_system_dynamics completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYSTEMS_BIOLOGY_SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS {
    take:
    // No file inputs

    main:
    SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS()

    emit:
    results = SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS.out.results
    output = SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS.out.output
}

// Entry workflow
workflow {
    if (!params.initial_concentrations) {
        error "Please provide --initial_concentrations parameter"
    }
    if (!params.rate_constants) {
        error "Please provide --rate_constants parameter"
    }
    if (!params.feedback_params) {
        error "Please provide --feedback_params parameter"
    }


    BIOMNI_SYSTEMS_BIOLOGY_SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS()
}
