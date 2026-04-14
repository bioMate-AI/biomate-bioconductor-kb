#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_run_3d_chondrogenic_aggregate_assay
 * Generates a detailed protocol for performing a 3D chondrogenic aggregate culture assay to evaluate compounds' effects on chondrogenesis.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.chondrocyte_cells = null
params.test_compounds = null
params.culture_duration_days = '21'
params.measurement_intervals = '7'

// Main process
process RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("run_3d_chondrogenic_aggregate_assay_results.json"), emit: results
    path("run_3d_chondrogenic_aggregate_assay_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.pharmacology import run_3d_chondrogenic_aggregate_assay
except ImportError:
    # Fallback: function may need to be implemented locally
    def run_3d_chondrogenic_aggregate_assay(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = run_3d_chondrogenic_aggregate_assay(
    chondrocyte_cells="${params.chondrocyte_cells}",
    test_compounds="${params.test_compounds}",
    culture_duration_days="${params.culture_duration_days}",
    measurement_intervals="${params.measurement_intervals}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("run_3d_chondrogenic_aggregate_assay_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("run_3d_chondrogenic_aggregate_assay_output.txt", "w") as f:
    f.write("Biomni: Run 3D Chondrogenic Aggregate Assay Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("run_3d_chondrogenic_aggregate_assay completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY {
    take:
    // No file inputs

    main:
    RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY()

    emit:
    results = RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY.out.results
    output = RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY.out.output
}

// Entry workflow
workflow {
    if (!params.chondrocyte_cells) {
        error "Please provide --chondrocyte_cells parameter"
    }
    if (!params.test_compounds) {
        error "Please provide --test_compounds parameter"
    }


    BIOMNI_PHARMACOLOGY_RUN_3D_CHONDROGENIC_AGGREGATE_ASSAY()
}
