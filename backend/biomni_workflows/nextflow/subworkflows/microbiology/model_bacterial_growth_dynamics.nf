#!/usr/bin/env nextflow
/*
 * biomni_microbiology_model_bacterial_growth_dynamics
 * Model bacterial population dynamics over time using ordinary differential equations.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.initial_population = null
params.growth_rate = null
params.clearance_rate = null
params.niche_size = null
params.simulation_time = '24'
params.time_step = '0.1'

// Main process
process MODEL_BACTERIAL_GROWTH_DYNAMICS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("model_bacterial_growth_dynamics_results.json"), emit: results
    path("model_bacterial_growth_dynamics_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.microbiology import model_bacterial_growth_dynamics

# Run the tool
try:
    result = model_bacterial_growth_dynamics(
    initial_population="${params.initial_population}",
    growth_rate="${params.growth_rate}",
    clearance_rate="${params.clearance_rate}",
    niche_size="${params.niche_size}",
    simulation_time="${params.simulation_time}",
    time_step="${params.time_step}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("model_bacterial_growth_dynamics_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("model_bacterial_growth_dynamics_output.txt", "w") as f:
    f.write("Biomni: Model Bacterial Growth Dynamics Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("model_bacterial_growth_dynamics completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_MODEL_BACTERIAL_GROWTH_DYNAMICS {
    take:
    // No file inputs

    main:
    MODEL_BACTERIAL_GROWTH_DYNAMICS()

    emit:
    results = MODEL_BACTERIAL_GROWTH_DYNAMICS.out.results
    output = MODEL_BACTERIAL_GROWTH_DYNAMICS.out.output
}

// Entry workflow
workflow {
    if (!params.initial_population) {
        error "Please provide --initial_population parameter"
    }
    if (!params.growth_rate) {
        error "Please provide --growth_rate parameter"
    }
    if (!params.clearance_rate) {
        error "Please provide --clearance_rate parameter"
    }
    if (!params.niche_size) {
        error "Please provide --niche_size parameter"
    }


    BIOMNI_MICROBIOLOGY_MODEL_BACTERIAL_GROWTH_DYNAMICS()
}
