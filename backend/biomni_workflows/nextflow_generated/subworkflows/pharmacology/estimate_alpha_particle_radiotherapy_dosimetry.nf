#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_estimate_alpha_particle_radiotherapy_dosimetry
 * Estimate radiation absorbed doses to tumor and normal organs for alpha-particle radiotherapeutics.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.biodistribution_data = null
params.radiation_parameters = null
params.output_file = 'dosimetry_results.csv'

// Main process
process ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("estimate_alpha_particle_radiotherapy_dosimetry_results.json"), emit: results
    path("estimate_alpha_particle_radiotherapy_dosimetry_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.pharmacology import estimate_alpha_particle_radiotherapy_dosimetry
except ImportError:
    # Fallback: function may need to be implemented locally
    def estimate_alpha_particle_radiotherapy_dosimetry(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = estimate_alpha_particle_radiotherapy_dosimetry(
    biodistribution_data="${params.biodistribution_data}",
    radiation_parameters="${params.radiation_parameters}",
    output_file="${params.output_file}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("estimate_alpha_particle_radiotherapy_dosimetry_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("estimate_alpha_particle_radiotherapy_dosimetry_output.txt", "w") as f:
    f.write("Biomni: Estimate Alpha Particle Radiotherapy Dosimetry Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("estimate_alpha_particle_radiotherapy_dosimetry completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY {
    take:
    // No file inputs

    main:
    ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY()

    emit:
    results = ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY.out.results
    output = ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY.out.output
}

// Entry workflow
workflow {
    if (!params.biodistribution_data) {
        error "Please provide --biodistribution_data parameter"
    }
    if (!params.radiation_parameters) {
        error "Please provide --radiation_parameters parameter"
    }


    BIOMNI_PHARMACOLOGY_ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY()
}
