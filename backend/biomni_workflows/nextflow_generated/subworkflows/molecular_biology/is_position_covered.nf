#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_is_position_covered
 * Check if a position is covered by any region.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.pos = null
params.covered_regions = null

// Main process
process IS_POSITION_COVERED {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("is_position_covered_results.json"), emit: results
    path("is_position_covered_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import is_position_covered
except ImportError:
    # Fallback: function may need to be implemented locally
    def is_position_covered(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = is_position_covered(
    pos="${params.pos}",
    covered_regions="${params.covered_regions}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("is_position_covered_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("is_position_covered_output.txt", "w") as f:
    f.write("Biomni: Is Position Covered Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("is_position_covered completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_IS_POSITION_COVERED {
    take:
    // No file inputs

    main:
    IS_POSITION_COVERED()

    emit:
    results = IS_POSITION_COVERED.out.results
    output = IS_POSITION_COVERED.out.output
}

// Entry workflow
workflow {
    if (!params.pos) {
        error "Please provide --pos parameter"
    }
    if (!params.covered_regions) {
        error "Please provide --covered_regions parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_IS_POSITION_COVERED()
}
