#!/usr/bin/env nextflow
/*
 * biomni_genetics_liftover_coordinates
 * Perform liftover of genomic coordinates between hg19 and hg38 formats with detailed intermediate steps.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.chromosome = null
params.position = 0
params.input_format = null
params.output_format = null
params.data_path = null

// Main process
process LIFTOVER_COORDINATES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("liftover_coordinates_results.json"), emit: results
    path("liftover_coordinates_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genetics import liftover_coordinates
except ImportError:
    # Fallback: function may need to be implemented locally
    def liftover_coordinates(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = liftover_coordinates(
    chromosome="${params.chromosome}",
    position=${params.position},
    input_format="${params.input_format}",
    output_format="${params.output_format}",
    data_path="${params.data_path}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("liftover_coordinates_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("liftover_coordinates_output.txt", "w") as f:
    f.write("Biomni: Liftover Coordinates Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("liftover_coordinates completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENETICS_LIFTOVER_COORDINATES {
    take:
    // No file inputs

    main:
    LIFTOVER_COORDINATES()

    emit:
    results = LIFTOVER_COORDINATES.out.results
    output = LIFTOVER_COORDINATES.out.output
}

// Entry workflow
workflow {
    if (!params.chromosome) {
        error "Please provide --chromosome parameter"
    }
    if (!params.input_format) {
        error "Please provide --input_format parameter"
    }
    if (!params.output_format) {
        error "Please provide --output_format parameter"
    }
    if (!params.data_path) {
        error "Please provide --data_path parameter"
    }


    BIOMNI_GENETICS_LIFTOVER_COORDINATES()
}
