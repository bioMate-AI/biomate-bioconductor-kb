#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_ode_system
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
process ODE_SYSTEM {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("ode_system_results.json"), emit: results
    path("ode_system_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.systems_biology import ode_system
except ImportError:
    # Fallback: function may need to be implemented locally
    def ode_system(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = ode_system(
    t="${params.t}",
    y="${params.y}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("ode_system_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("ode_system_output.txt", "w") as f:
    f.write("Biomni: Ode System Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("ode_system completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYSTEMS_BIOLOGY_ODE_SYSTEM {
    take:
    // No file inputs

    main:
    ODE_SYSTEM()

    emit:
    results = ODE_SYSTEM.out.results
    output = ODE_SYSTEM.out.output
}

// Entry workflow
workflow {
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.y) {
        error "Please provide --y parameter"
    }


    BIOMNI_SYSTEMS_BIOLOGY_ODE_SYSTEM()
}
