#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_simulate_whole_cell_ode_model
 * Simulate a whole-cell model represented as a system of ordinary differential equations (ODEs).
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.initial_conditions = null
params.parameters = null
params.ode_function = null
params.time_span = null
params.time_points = '1000'
params.method = 'LSODA'

// Main process
process SIMULATE_WHOLE_CELL_ODE_MODEL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("simulate_whole_cell_ode_model_results.json"), emit: results
    path("simulate_whole_cell_ode_model_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.bioengineering import simulate_whole_cell_ode_model

# Run the tool
try:
    result = simulate_whole_cell_ode_model(
    initial_conditions="${params.initial_conditions}",
    parameters="${params.parameters}",
    ode_function="${params.ode_function}",
    time_span="${params.time_span}",
    time_points="${params.time_points}",
    method="${params.method}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("simulate_whole_cell_ode_model_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("simulate_whole_cell_ode_model_output.txt", "w") as f:
    f.write("Biomni: Simulate Whole Cell Ode Model Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("simulate_whole_cell_ode_model completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOENGINEERING_SIMULATE_WHOLE_CELL_ODE_MODEL {
    take:
    // No file inputs

    main:
    SIMULATE_WHOLE_CELL_ODE_MODEL()

    emit:
    results = SIMULATE_WHOLE_CELL_ODE_MODEL.out.results
    output = SIMULATE_WHOLE_CELL_ODE_MODEL.out.output
}

// Entry workflow
workflow {
    if (!params.initial_conditions) {
        error "Please provide --initial_conditions parameter"
    }
    if (!params.parameters) {
        error "Please provide --parameters parameter"
    }


    BIOMNI_BIOENGINEERING_SIMULATE_WHOLE_CELL_ODE_MODEL()
}
