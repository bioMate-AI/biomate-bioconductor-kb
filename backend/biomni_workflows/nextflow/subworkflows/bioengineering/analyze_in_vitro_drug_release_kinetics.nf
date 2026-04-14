#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_analyze_in_vitro_drug_release_kinetics
 * Analyzes in vitro drug release kinetics from biomaterial formulations.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.time_points = null
params.concentration_data = null
params.drug_name = 'Drug'
params.total_drug_loaded = null
params.output_dir = './'

// Main process
process ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_in_vitro_drug_release_kinetics_results.json"), emit: results
    path("analyze_in_vitro_drug_release_kinetics_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.bioengineering import analyze_in_vitro_drug_release_kinetics

# Run the tool
try:
    result = analyze_in_vitro_drug_release_kinetics(
    time_points="${params.time_points}",
    concentration_data="${params.concentration_data}",
    drug_name="${params.drug_name}",
    total_drug_loaded="${params.total_drug_loaded}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_in_vitro_drug_release_kinetics_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_in_vitro_drug_release_kinetics_output.txt", "w") as f:
    f.write("Biomni: Analyze In Vitro Drug Release Kinetics Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_in_vitro_drug_release_kinetics completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOENGINEERING_ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS {
    take:
    // No file inputs

    main:
    ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS()

    emit:
    results = ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS.out.results
    output = ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS.out.output
}

// Entry workflow
workflow {
    if (!params.time_points) {
        error "Please provide --time_points parameter"
    }
    if (!params.concentration_data) {
        error "Please provide --concentration_data parameter"
    }


    BIOMNI_BIOENGINEERING_ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS()
}
