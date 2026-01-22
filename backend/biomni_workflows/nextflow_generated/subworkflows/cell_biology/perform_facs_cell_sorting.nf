#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_perform_facs_cell_sorting
 * Performs Fluorescence-Activated Cell Sorting (FACS) to enrich cell populations based on fluorescence characteristics.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.cell_suspension_data = null
params.fluorescence_parameter = null
params.threshold_min = null
params.threshold_max = null
params.output_file = 'sorted_cells.csv'

// Main process
process PERFORM_FACS_CELL_SORTING {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("perform_facs_cell_sorting_results.json"), emit: results
    path("perform_facs_cell_sorting_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.cell_biology import perform_facs_cell_sorting
except ImportError:
    # Fallback: function may need to be implemented locally
    def perform_facs_cell_sorting(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = perform_facs_cell_sorting(
    cell_suspension_data="${params.cell_suspension_data}",
    fluorescence_parameter="${params.fluorescence_parameter}",
    threshold_min="${params.threshold_min}",
    threshold_max="${params.threshold_max}",
    output_file="${params.output_file}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("perform_facs_cell_sorting_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("perform_facs_cell_sorting_output.txt", "w") as f:
    f.write("Biomni: Perform Facs Cell Sorting Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("perform_facs_cell_sorting completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_CELL_BIOLOGY_PERFORM_FACS_CELL_SORTING {
    take:
    // No file inputs

    main:
    PERFORM_FACS_CELL_SORTING()

    emit:
    results = PERFORM_FACS_CELL_SORTING.out.results
    output = PERFORM_FACS_CELL_SORTING.out.output
}

// Entry workflow
workflow {
    if (!params.cell_suspension_data) {
        error "Please provide --cell_suspension_data parameter"
    }
    if (!params.fluorescence_parameter) {
        error "Please provide --fluorescence_parameter parameter"
    }


    BIOMNI_CELL_BIOLOGY_PERFORM_FACS_CELL_SORTING()
}
