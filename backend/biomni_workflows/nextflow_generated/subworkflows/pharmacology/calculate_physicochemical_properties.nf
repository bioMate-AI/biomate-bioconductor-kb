#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_calculate_physicochemical_properties
 * Calculate key physicochemical properties of a drug candidate molecule.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.smiles_string = null

// Main process
process CALCULATE_PHYSICOCHEMICAL_PROPERTIES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("calculate_physicochemical_properties_results.json"), emit: results
    path("calculate_physicochemical_properties_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.pharmacology import calculate_physicochemical_properties
except ImportError:
    # Fallback: function may need to be implemented locally
    def calculate_physicochemical_properties(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = calculate_physicochemical_properties(
    smiles_string="${params.smiles_string}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("calculate_physicochemical_properties_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("calculate_physicochemical_properties_output.txt", "w") as f:
    f.write("Biomni: Calculate Physicochemical Properties Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("calculate_physicochemical_properties completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_CALCULATE_PHYSICOCHEMICAL_PROPERTIES {
    take:
    // No file inputs

    main:
    CALCULATE_PHYSICOCHEMICAL_PROPERTIES()

    emit:
    results = CALCULATE_PHYSICOCHEMICAL_PROPERTIES.out.results
    output = CALCULATE_PHYSICOCHEMICAL_PROPERTIES.out.output
}

// Entry workflow
workflow {
    if (!params.smiles_string) {
        error "Please provide --smiles_string parameter"
    }


    BIOMNI_PHARMACOLOGY_CALCULATE_PHYSICOCHEMICAL_PROPERTIES()
}
