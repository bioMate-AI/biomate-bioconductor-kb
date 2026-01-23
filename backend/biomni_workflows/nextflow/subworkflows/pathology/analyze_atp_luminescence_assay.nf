#!/usr/bin/env nextflow
/*
 * biomni_pathology_analyze_atp_luminescence_assay
 * Analyze luminescence-based ATP assay data to determine intracellular ATP concentration.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.data_file = null
params.standard_curve_file = null
params.normalization_method = 'cell_count'
params.normalization_data = null

// Main process
process ANALYZE_ATP_LUMINESCENCE_ASSAY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_atp_luminescence_assay_results.json"), emit: results
    path("analyze_atp_luminescence_assay_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pathology import analyze_atp_luminescence_assay

# Run the tool
try:
    result = analyze_atp_luminescence_assay(
    data_file="${params.data_file}",
    standard_curve_file="${params.standard_curve_file}",
    normalization_method="${params.normalization_method}",
    normalization_data="${params.normalization_data}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_atp_luminescence_assay_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_atp_luminescence_assay_output.txt", "w") as f:
    f.write("Biomni: Analyze Atp Luminescence Assay Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_atp_luminescence_assay completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PATHOLOGY_ANALYZE_ATP_LUMINESCENCE_ASSAY {
    take:
    // No file inputs

    main:
    ANALYZE_ATP_LUMINESCENCE_ASSAY()

    emit:
    results = ANALYZE_ATP_LUMINESCENCE_ASSAY.out.results
    output = ANALYZE_ATP_LUMINESCENCE_ASSAY.out.output
}

// Entry workflow
workflow {
    if (!params.data_file) {
        error "Please provide --data_file parameter"
    }
    if (!params.standard_curve_file) {
        error "Please provide --standard_curve_file parameter"
    }


    BIOMNI_PATHOLOGY_ANALYZE_ATP_LUMINESCENCE_ASSAY()
}
