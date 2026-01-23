#!/usr/bin/env nextflow
/*
 * biomni_physiology_simulate_thyroid_hormone_pharmacokinetics
 * Simulates the transport and binding of thyroid hormones across different tissue compartments
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.parameters = null
params.initial_conditions = null
params.time_span = null
params.time_points = '100'

// Main process
process SIMULATE_THYROID_HORMONE_PHARMACOKINETICS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("simulate_thyroid_hormone_pharmacokinetics_results.json"), emit: results
    path("simulate_thyroid_hormone_pharmacokinetics_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.physiology import simulate_thyroid_hormone_pharmacokinetics

# Run the tool
try:
    result = simulate_thyroid_hormone_pharmacokinetics(
    parameters="${params.parameters}",
    initial_conditions="${params.initial_conditions}",
    time_span="${params.time_span}",
    time_points="${params.time_points}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("simulate_thyroid_hormone_pharmacokinetics_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("simulate_thyroid_hormone_pharmacokinetics_output.txt", "w") as f:
    f.write("Biomni: Simulate Thyroid Hormone Pharmacokinetics Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("simulate_thyroid_hormone_pharmacokinetics completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHYSIOLOGY_SIMULATE_THYROID_HORMONE_PHARMACOKINETICS {
    take:
    // No file inputs

    main:
    SIMULATE_THYROID_HORMONE_PHARMACOKINETICS()

    emit:
    results = SIMULATE_THYROID_HORMONE_PHARMACOKINETICS.out.results
    output = SIMULATE_THYROID_HORMONE_PHARMACOKINETICS.out.output
}

// Entry workflow
workflow {
    if (!params.parameters) {
        error "Please provide --parameters parameter"
    }
    if (!params.initial_conditions) {
        error "Please provide --initial_conditions parameter"
    }


    BIOMNI_PHYSIOLOGY_SIMULATE_THYROID_HORMONE_PHARMACOKINETICS()
}
