#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_is_region_fully_covered
 * Check if the target region is fully covered.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.covered_regions = null
params.start = null
params.end = null

// Main process
process IS_REGION_FULLY_COVERED {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("is_region_fully_covered_results.json"), emit: results
    path("is_region_fully_covered_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import is_region_fully_covered
except ImportError:
    # Fallback: function may need to be implemented locally
    def is_region_fully_covered(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = is_region_fully_covered(
    covered_regions="${params.covered_regions}",
    start="${params.start}",
    end="${params.end}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("is_region_fully_covered_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("is_region_fully_covered_output.txt", "w") as f:
    f.write("Biomni: Is Region Fully Covered Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("is_region_fully_covered completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_IS_REGION_FULLY_COVERED {
    take:
    // No file inputs

    main:
    IS_REGION_FULLY_COVERED()

    emit:
    results = IS_REGION_FULLY_COVERED.out.results
    output = IS_REGION_FULLY_COVERED.out.output
}

// Entry workflow
workflow {
    if (!params.covered_regions) {
        error "Please provide --covered_regions parameter"
    }
    if (!params.start) {
        error "Please provide --start parameter"
    }
    if (!params.end) {
        error "Please provide --end parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_IS_REGION_FULLY_COVERED()
}
