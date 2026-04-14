#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_ras_ode_system
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.y = null

// Main process
process RAS_ODE_SYSTEM {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("ras_ode_system_results.json"), emit: results
    path("ras_ode_system_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.systems_biology import ras_ode_system

# Run the tool
try:
    result = ras_ode_system(
    t="${params.t}",
    y="${params.y}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("ras_ode_system_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("ras_ode_system_output.txt", "w") as f:
    f.write("Biomni: Ras Ode System Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("ras_ode_system completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYSTEMS_BIOLOGY_RAS_ODE_SYSTEM {
    take:
    // No file inputs

    main:
    RAS_ODE_SYSTEM()

    emit:
    results = RAS_ODE_SYSTEM.out.results
    output = RAS_ODE_SYSTEM.out.output
}

// Entry workflow
workflow {
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.y) {
        error "Please provide --y parameter"
    }


    BIOMNI_SYSTEMS_BIOLOGY_RAS_ODE_SYSTEM()
}
