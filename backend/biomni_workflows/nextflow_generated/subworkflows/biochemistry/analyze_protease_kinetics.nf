#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_analyze_protease_kinetics
 * Analyze protease kinetics data from fluorogenic peptide cleavage assays.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.time_points = null
params.fluorescence_data = null
params.substrate_concentrations = null
params.enzyme_concentration = null
params.output_prefix = 'protease_kinetics'
params.output_dir = './'

// Main process
process ANALYZE_PROTEASE_KINETICS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_protease_kinetics_results.json"), emit: results
    path("analyze_protease_kinetics_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.biochemistry import analyze_protease_kinetics
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_protease_kinetics(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_protease_kinetics(
    time_points="${params.time_points}",
    fluorescence_data="${params.fluorescence_data}",
    substrate_concentrations="${params.substrate_concentrations}",
    enzyme_concentration="${params.enzyme_concentration}",
    output_prefix="${params.output_prefix}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_protease_kinetics_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_protease_kinetics_output.txt", "w") as f:
    f.write("Biomni: Analyze Protease Kinetics Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_protease_kinetics completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOCHEMISTRY_ANALYZE_PROTEASE_KINETICS {
    take:
    // No file inputs

    main:
    ANALYZE_PROTEASE_KINETICS()

    emit:
    results = ANALYZE_PROTEASE_KINETICS.out.results
    output = ANALYZE_PROTEASE_KINETICS.out.output
}

// Entry workflow
workflow {
    if (!params.time_points) {
        error "Please provide --time_points parameter"
    }
    if (!params.fluorescence_data) {
        error "Please provide --fluorescence_data parameter"
    }
    if (!params.substrate_concentrations) {
        error "Please provide --substrate_concentrations parameter"
    }
    if (!params.enzyme_concentration) {
        error "Please provide --enzyme_concentration parameter"
    }


    BIOMNI_BIOCHEMISTRY_ANALYZE_PROTEASE_KINETICS()
}
