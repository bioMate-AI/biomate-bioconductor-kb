#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_analyze_flow_cytometry_immunophenotyping
 * Analyze flow cytometry data to identify and quantify specific cell populations based on surface markers.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.fcs_file_path = null
params.gating_strategy = null
params.compensation_matrix = null
params.output_dir = './results'

// Main process
process ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_flow_cytometry_immunophenotyping_results.json"), emit: results
    path("analyze_flow_cytometry_immunophenotyping_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.cell_biology import analyze_flow_cytometry_immunophenotyping

# Run the tool
try:
    result = analyze_flow_cytometry_immunophenotyping(
    fcs_file_path="${params.fcs_file_path}",
    gating_strategy="${params.gating_strategy}",
    compensation_matrix="${params.compensation_matrix}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_flow_cytometry_immunophenotyping_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_flow_cytometry_immunophenotyping_output.txt", "w") as f:
    f.write("Biomni: Analyze Flow Cytometry Immunophenotyping Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_flow_cytometry_immunophenotyping completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_CELL_BIOLOGY_ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING {
    take:
    // No file inputs

    main:
    ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING()

    emit:
    results = ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING.out.results
    output = ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING.out.output
}

// Entry workflow
workflow {
    if (!params.fcs_file_path) {
        error "Please provide --fcs_file_path parameter"
    }
    if (!params.gating_strategy) {
        error "Please provide --gating_strategy parameter"
    }


    BIOMNI_CELL_BIOLOGY_ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING()
}
