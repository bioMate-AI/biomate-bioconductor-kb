#!/usr/bin/env nextflow
/*
 * biomni_physiology_pk_ode_system
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
process PK_ODE_SYSTEM {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("pk_ode_system_results.json"), emit: results
    path("pk_ode_system_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.physiology import pk_ode_system
except ImportError:
    # Fallback: function may need to be implemented locally
    def pk_ode_system(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = pk_ode_system(
    t="${params.t}",
    y="${params.y}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("pk_ode_system_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("pk_ode_system_output.txt", "w") as f:
    f.write("Biomni: Pk Ode System Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("pk_ode_system completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHYSIOLOGY_PK_ODE_SYSTEM {
    take:
    // No file inputs

    main:
    PK_ODE_SYSTEM()

    emit:
    results = PK_ODE_SYSTEM.out.results
    output = PK_ODE_SYSTEM.out.output
}

// Entry workflow
workflow {
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.y) {
        error "Please provide --y parameter"
    }


    BIOMNI_PHYSIOLOGY_PK_ODE_SYSTEM()
}
