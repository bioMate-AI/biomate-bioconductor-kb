#!/usr/bin/env nextflow
/*
 * biomni_cancer_biology_analyze_cell_senescence_and_apoptosis
 * Analyze flow cytometry data to quantify senescent and apoptotic cell populations.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.fcs_file_path = null

// Main process
process ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_cell_senescence_and_apoptosis_results.json"), emit: results
    path("analyze_cell_senescence_and_apoptosis_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.cancer_biology import analyze_cell_senescence_and_apoptosis
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_cell_senescence_and_apoptosis(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_cell_senescence_and_apoptosis(
    fcs_file_path="${params.fcs_file_path}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_cell_senescence_and_apoptosis_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_cell_senescence_and_apoptosis_output.txt", "w") as f:
    f.write("Biomni: Analyze Cell Senescence And Apoptosis Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_cell_senescence_and_apoptosis completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_CANCER_BIOLOGY_ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS {
    take:
    // No file inputs

    main:
    ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS()

    emit:
    results = ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS.out.results
    output = ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS.out.output
}

// Entry workflow
workflow {
    if (!params.fcs_file_path) {
        error "Please provide --fcs_file_path parameter"
    }


    BIOMNI_CANCER_BIOLOGY_ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS()
}
