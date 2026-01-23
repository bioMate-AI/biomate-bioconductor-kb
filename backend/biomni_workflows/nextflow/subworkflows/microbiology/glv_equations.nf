#!/usr/bin/env nextflow
/*
 * biomni_microbiology_glv_equations
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.abundances = null
params.t = null
params.growth_rates = null
params.interaction_matrix = null

// Main process
process GLV_EQUATIONS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("glv_equations_results.json"), emit: results
    path("glv_equations_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.microbiology import glv_equations

# Run the tool
try:
    result = glv_equations(
    abundances="${params.abundances}",
    t="${params.t}",
    growth_rates="${params.growth_rates}",
    interaction_matrix="${params.interaction_matrix}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("glv_equations_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("glv_equations_output.txt", "w") as f:
    f.write("Biomni: Glv Equations Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("glv_equations completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_GLV_EQUATIONS {
    take:
    // No file inputs

    main:
    GLV_EQUATIONS()

    emit:
    results = GLV_EQUATIONS.out.results
    output = GLV_EQUATIONS.out.output
}

// Entry workflow
workflow {
    if (!params.abundances) {
        error "Please provide --abundances parameter"
    }
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.growth_rates) {
        error "Please provide --growth_rates parameter"
    }
    if (!params.interaction_matrix) {
        error "Please provide --interaction_matrix parameter"
    }


    BIOMNI_MICROBIOLOGY_GLV_EQUATIONS()
}
