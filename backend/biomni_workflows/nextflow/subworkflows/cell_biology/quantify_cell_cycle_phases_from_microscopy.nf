#!/usr/bin/env nextflow
/*
 * biomni_cell_biology_quantify_cell_cycle_phases_from_microscopy
 * Quantify the percentage of cells in each cell cycle phase using Calcofluor white stained microscopy images.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_paths = null
params.output_dir = './results'

// Main process
process QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("quantify_cell_cycle_phases_from_microscopy_results.json"), emit: results
    path("quantify_cell_cycle_phases_from_microscopy_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.cell_biology import quantify_cell_cycle_phases_from_microscopy

# Run the tool
try:
    result = quantify_cell_cycle_phases_from_microscopy(
    image_paths="${params.image_paths}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("quantify_cell_cycle_phases_from_microscopy_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("quantify_cell_cycle_phases_from_microscopy_output.txt", "w") as f:
    f.write("Biomni: Quantify Cell Cycle Phases From Microscopy Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("quantify_cell_cycle_phases_from_microscopy completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_CELL_BIOLOGY_QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY {
    take:
    // No file inputs

    main:
    QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY()

    emit:
    results = QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY.out.results
    output = QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY.out.output
}

// Entry workflow
workflow {
    if (!params.image_paths) {
        error "Please provide --image_paths parameter"
    }


    BIOMNI_CELL_BIOLOGY_QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY()
}
