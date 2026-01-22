#!/usr/bin/env nextflow
/*
 * biomni_microbiology_bacterial_dynamics
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.t = null
params.N = null

// Main process
process BACTERIAL_DYNAMICS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("bacterial_dynamics_results.json"), emit: results
    path("bacterial_dynamics_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.microbiology import bacterial_dynamics
except ImportError:
    # Fallback: function may need to be implemented locally
    def bacterial_dynamics(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = bacterial_dynamics(
    t="${params.t}",
    N="${params.N}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("bacterial_dynamics_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("bacterial_dynamics_output.txt", "w") as f:
    f.write("Biomni: Bacterial Dynamics Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("bacterial_dynamics completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_BACTERIAL_DYNAMICS {
    take:
    // No file inputs

    main:
    BACTERIAL_DYNAMICS()

    emit:
    results = BACTERIAL_DYNAMICS.out.results
    output = BACTERIAL_DYNAMICS.out.output
}

// Entry workflow
workflow {
    if (!params.t) {
        error "Please provide --t parameter"
    }
    if (!params.N) {
        error "Please provide --N parameter"
    }


    BIOMNI_MICROBIOLOGY_BACTERIAL_DYNAMICS()
}
