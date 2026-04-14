#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_model_protein_dimerization_network
 * Model protein dimerization networks to find equilibrium concentrations of dimers.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.monomer_concentrations = null
params.dimerization_affinities = null
params.network_topology = null

// Main process
process MODEL_PROTEIN_DIMERIZATION_NETWORK {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("model_protein_dimerization_network_results.json"), emit: results
    path("model_protein_dimerization_network_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.systems_biology import model_protein_dimerization_network

# Run the tool
try:
    result = model_protein_dimerization_network(
    monomer_concentrations="${params.monomer_concentrations}",
    dimerization_affinities="${params.dimerization_affinities}",
    network_topology="${params.network_topology}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("model_protein_dimerization_network_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("model_protein_dimerization_network_output.txt", "w") as f:
    f.write("Biomni: Model Protein Dimerization Network Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("model_protein_dimerization_network completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYSTEMS_BIOLOGY_MODEL_PROTEIN_DIMERIZATION_NETWORK {
    take:
    // No file inputs

    main:
    MODEL_PROTEIN_DIMERIZATION_NETWORK()

    emit:
    results = MODEL_PROTEIN_DIMERIZATION_NETWORK.out.results
    output = MODEL_PROTEIN_DIMERIZATION_NETWORK.out.output
}

// Entry workflow
workflow {
    if (!params.monomer_concentrations) {
        error "Please provide --monomer_concentrations parameter"
    }
    if (!params.dimerization_affinities) {
        error "Please provide --dimerization_affinities parameter"
    }
    if (!params.network_topology) {
        error "Please provide --network_topology parameter"
    }


    BIOMNI_SYSTEMS_BIOLOGY_MODEL_PROTEIN_DIMERIZATION_NETWORK()
}
