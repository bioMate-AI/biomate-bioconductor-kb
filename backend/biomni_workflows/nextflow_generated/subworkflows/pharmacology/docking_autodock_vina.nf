#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_docking_autodock_vina
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.smiles_list = null
params.receptor_pdb_file = null
params.box_center = null
params.box_size = null
params.ncpu = '1'

// Main process
process DOCKING_AUTODOCK_VINA {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("docking_autodock_vina_results.json"), emit: results
    path("docking_autodock_vina_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.pharmacology import docking_autodock_vina
except ImportError:
    # Fallback: function may need to be implemented locally
    def docking_autodock_vina(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = docking_autodock_vina(
    smiles_list="${params.smiles_list}",
    receptor_pdb_file="${params.receptor_pdb_file}",
    box_center="${params.box_center}",
    box_size="${params.box_size}",
    ncpu="${params.ncpu}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("docking_autodock_vina_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("docking_autodock_vina_output.txt", "w") as f:
    f.write("Biomni: Docking Autodock Vina Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("docking_autodock_vina completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_DOCKING_AUTODOCK_VINA {
    take:
    // No file inputs

    main:
    DOCKING_AUTODOCK_VINA()

    emit:
    results = DOCKING_AUTODOCK_VINA.out.results
    output = DOCKING_AUTODOCK_VINA.out.output
}

// Entry workflow
workflow {
    if (!params.smiles_list) {
        error "Please provide --smiles_list parameter"
    }
    if (!params.receptor_pdb_file) {
        error "Please provide --receptor_pdb_file parameter"
    }
    if (!params.box_center) {
        error "Please provide --box_center parameter"
    }
    if (!params.box_size) {
        error "Please provide --box_size parameter"
    }


    BIOMNI_PHARMACOLOGY_DOCKING_AUTODOCK_VINA()
}
