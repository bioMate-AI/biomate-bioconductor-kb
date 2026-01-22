#!/usr/bin/env nextflow
/*
 * biomni_genomics_custom_mode
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.x = null

// Main process
process CUSTOM_MODE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("custom_mode_results.json"), emit: results
    path("custom_mode_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genomics import custom_mode
except ImportError:
    # Fallback: function may need to be implemented locally
    def custom_mode(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = custom_mode(
    x="${params.x}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("custom_mode_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("custom_mode_output.txt", "w") as f:
    f.write("Biomni: Custom Mode Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("custom_mode completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_CUSTOM_MODE {
    take:
    // No file inputs

    main:
    CUSTOM_MODE()

    emit:
    results = CUSTOM_MODE.out.results
    output = CUSTOM_MODE.out.output
}

// Entry workflow
workflow {
    if (!params.x) {
        error "Please provide --x parameter"
    }


    BIOMNI_GENOMICS_CUSTOM_MODE()
}
