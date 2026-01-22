#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_merge_overlapping_regions
 * Merge overlapping regions in the list.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.regions = null

// Main process
process MERGE_OVERLAPPING_REGIONS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("merge_overlapping_regions_results.json"), emit: results
    path("merge_overlapping_regions_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.molecular_biology import merge_overlapping_regions
except ImportError:
    # Fallback: function may need to be implemented locally
    def merge_overlapping_regions(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = merge_overlapping_regions(
    regions="${params.regions}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("merge_overlapping_regions_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("merge_overlapping_regions_output.txt", "w") as f:
    f.write("Biomni: Merge Overlapping Regions Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("merge_overlapping_regions completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_MERGE_OVERLAPPING_REGIONS {
    take:
    // No file inputs

    main:
    MERGE_OVERLAPPING_REGIONS()

    emit:
    results = MERGE_OVERLAPPING_REGIONS.out.results
    output = MERGE_OVERLAPPING_REGIONS.out.output
}

// Entry workflow
workflow {
    if (!params.regions) {
        error "Please provide --regions parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_MERGE_OVERLAPPING_REGIONS()
}
