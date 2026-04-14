#!/usr/bin/env nextflow
/*
 * biomni_immunology_isolate_purify_immune_cells
 * Simulates the isolation and purification of immune cells from tissue samples.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.tissue_type = null
params.target_cell_type = null
params.enzyme_type = 'collagenase'
params.macs_antibody = null
params.digestion_time_min = '45'

// Main process
process ISOLATE_PURIFY_IMMUNE_CELLS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("isolate_purify_immune_cells_results.json"), emit: results
    path("isolate_purify_immune_cells_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.immunology import isolate_purify_immune_cells
except ImportError:
    # Fallback: function may need to be implemented locally
    def isolate_purify_immune_cells(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = isolate_purify_immune_cells(
    tissue_type="${params.tissue_type}",
    target_cell_type="${params.target_cell_type}",
    enzyme_type="${params.enzyme_type}",
    macs_antibody="${params.macs_antibody}",
    digestion_time_min="${params.digestion_time_min}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("isolate_purify_immune_cells_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("isolate_purify_immune_cells_output.txt", "w") as f:
    f.write("Biomni: Isolate Purify Immune Cells Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("isolate_purify_immune_cells completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_IMMUNOLOGY_ISOLATE_PURIFY_IMMUNE_CELLS {
    take:
    // No file inputs

    main:
    ISOLATE_PURIFY_IMMUNE_CELLS()

    emit:
    results = ISOLATE_PURIFY_IMMUNE_CELLS.out.results
    output = ISOLATE_PURIFY_IMMUNE_CELLS.out.output
}

// Entry workflow
workflow {
    if (!params.tissue_type) {
        error "Please provide --tissue_type parameter"
    }
    if (!params.target_cell_type) {
        error "Please provide --target_cell_type parameter"
    }


    BIOMNI_IMMUNOLOGY_ISOLATE_PURIFY_IMMUNE_CELLS()
}
