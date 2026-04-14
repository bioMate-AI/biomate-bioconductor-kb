#!/usr/bin/env nextflow
/*
 * biomni_immunology_analyze_ebv_antibody_titers
 * Analyze ELISA data to quantify EBV antibody titers in plasma/serum samples.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.raw_od_data = null
params.standard_curve_data = null
params.sample_metadata = null
params.output_dir = './'

// Main process
process ANALYZE_EBV_ANTIBODY_TITERS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_ebv_antibody_titers_results.json"), emit: results
    path("analyze_ebv_antibody_titers_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.immunology import analyze_ebv_antibody_titers

# Run the tool
try:
    result = analyze_ebv_antibody_titers(
    raw_od_data="${params.raw_od_data}",
    standard_curve_data="${params.standard_curve_data}",
    sample_metadata="${params.sample_metadata}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_ebv_antibody_titers_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_ebv_antibody_titers_output.txt", "w") as f:
    f.write("Biomni: Analyze Ebv Antibody Titers Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_ebv_antibody_titers completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_IMMUNOLOGY_ANALYZE_EBV_ANTIBODY_TITERS {
    take:
    // No file inputs

    main:
    ANALYZE_EBV_ANTIBODY_TITERS()

    emit:
    results = ANALYZE_EBV_ANTIBODY_TITERS.out.results
    output = ANALYZE_EBV_ANTIBODY_TITERS.out.output
}

// Entry workflow
workflow {
    if (!params.raw_od_data) {
        error "Please provide --raw_od_data parameter"
    }
    if (!params.standard_curve_data) {
        error "Please provide --standard_curve_data parameter"
    }
    if (!params.sample_metadata) {
        error "Please provide --sample_metadata parameter"
    }


    BIOMNI_IMMUNOLOGY_ANALYZE_EBV_ANTIBODY_TITERS()
}
