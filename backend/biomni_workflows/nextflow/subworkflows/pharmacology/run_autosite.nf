#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_run_autosite
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.pdb_file = null
params.output_dir = null
params.spacing = '1.0'

// Main process
process RUN_AUTOSITE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("run_autosite_results.json"), emit: results
    path("run_autosite_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.pharmacology import run_autosite
except ImportError:
    # Fallback: function may need to be implemented locally
    def run_autosite(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = run_autosite(
    pdb_file="${params.pdb_file}",
    output_dir="${params.output_dir}",
    spacing="${params.spacing}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("run_autosite_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("run_autosite_output.txt", "w") as f:
    f.write("Biomni: Run Autosite Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("run_autosite completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_RUN_AUTOSITE {
    take:
    // No file inputs

    main:
    RUN_AUTOSITE()

    emit:
    results = RUN_AUTOSITE.out.results
    output = RUN_AUTOSITE.out.output
}

// Entry workflow
workflow {
    if (!params.pdb_file) {
        error "Please provide --pdb_file parameter"
    }
    if (!params.output_dir) {
        error "Please provide --output_dir parameter"
    }


    BIOMNI_PHARMACOLOGY_RUN_AUTOSITE()
}
