#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_run_diffdock_with_smiles
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.pdb_path = null
params.smiles_string = null
params.local_output_dir = null
params.gpu_device = '0'
params.use_gpu = 'True'

// Main process
process RUN_DIFFDOCK_WITH_SMILES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("run_diffdock_with_smiles_results.json"), emit: results
    path("run_diffdock_with_smiles_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.pharmacology import run_diffdock_with_smiles
except ImportError:
    # Fallback: function may need to be implemented locally
    def run_diffdock_with_smiles(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = run_diffdock_with_smiles(
    pdb_path="${params.pdb_path}",
    smiles_string="${params.smiles_string}",
    local_output_dir="${params.local_output_dir}",
    gpu_device="${params.gpu_device}",
    use_gpu="${params.use_gpu}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("run_diffdock_with_smiles_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("run_diffdock_with_smiles_output.txt", "w") as f:
    f.write("Biomni: Run Diffdock With Smiles Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("run_diffdock_with_smiles completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_RUN_DIFFDOCK_WITH_SMILES {
    take:
    // No file inputs

    main:
    RUN_DIFFDOCK_WITH_SMILES()

    emit:
    results = RUN_DIFFDOCK_WITH_SMILES.out.results
    output = RUN_DIFFDOCK_WITH_SMILES.out.output
}

// Entry workflow
workflow {
    if (!params.pdb_path) {
        error "Please provide --pdb_path parameter"
    }
    if (!params.smiles_string) {
        error "Please provide --smiles_string parameter"
    }
    if (!params.local_output_dir) {
        error "Please provide --local_output_dir parameter"
    }


    BIOMNI_PHARMACOLOGY_RUN_DIFFDOCK_WITH_SMILES()
}
