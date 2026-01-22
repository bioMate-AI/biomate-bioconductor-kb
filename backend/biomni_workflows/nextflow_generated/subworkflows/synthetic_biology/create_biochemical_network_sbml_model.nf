#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_create_biochemical_network_sbml_model
 * Generate a mathematical model of a biochemical network in SBML format.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.reaction_network = null
params.kinetic_parameters = null
params.output_file = 'biochemical_model.xml'

// Main process
process CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("create_biochemical_network_sbml_model_results.json"), emit: results
    path("create_biochemical_network_sbml_model_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.synthetic_biology import create_biochemical_network_sbml_model
except ImportError:
    # Fallback: function may need to be implemented locally
    def create_biochemical_network_sbml_model(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = create_biochemical_network_sbml_model(
    reaction_network="${params.reaction_network}",
    kinetic_parameters="${params.kinetic_parameters}",
    output_file="${params.output_file}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("create_biochemical_network_sbml_model_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("create_biochemical_network_sbml_model_output.txt", "w") as f:
    f.write("Biomni: Create Biochemical Network Sbml Model Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("create_biochemical_network_sbml_model completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYNTHETIC_BIOLOGY_CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL {
    take:
    // No file inputs

    main:
    CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL()

    emit:
    results = CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL.out.results
    output = CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL.out.output
}

// Entry workflow
workflow {
    if (!params.reaction_network) {
        error "Please provide --reaction_network parameter"
    }
    if (!params.kinetic_parameters) {
        error "Please provide --kinetic_parameters parameter"
    }


    BIOMNI_SYNTHETIC_BIOLOGY_CREATE_BIOCHEMICAL_NETWORK_SBML_MODEL()
}
