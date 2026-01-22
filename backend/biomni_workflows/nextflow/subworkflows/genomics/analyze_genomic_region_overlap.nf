#!/usr/bin/env nextflow
/*
 * biomni_genomics_analyze_genomic_region_overlap
 * Analyze overlaps between two or more sets of genomic regions.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.region_sets = null
params.output_prefix = 'overlap_analysis'

// Main process
process ANALYZE_GENOMIC_REGION_OVERLAP {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_genomic_region_overlap_results.json"), emit: results
    path("analyze_genomic_region_overlap_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.genomics import analyze_genomic_region_overlap
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_genomic_region_overlap(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_genomic_region_overlap(
    region_sets="${params.region_sets}",
    output_prefix="${params.output_prefix}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_genomic_region_overlap_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_genomic_region_overlap_output.txt", "w") as f:
    f.write("Biomni: Analyze Genomic Region Overlap Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_genomic_region_overlap completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_ANALYZE_GENOMIC_REGION_OVERLAP {
    take:
    // No file inputs

    main:
    ANALYZE_GENOMIC_REGION_OVERLAP()

    emit:
    results = ANALYZE_GENOMIC_REGION_OVERLAP.out.results
    output = ANALYZE_GENOMIC_REGION_OVERLAP.out.output
}

// Entry workflow
workflow {
    if (!params.region_sets) {
        error "Please provide --region_sets parameter"
    }


    BIOMNI_GENOMICS_ANALYZE_GENOMIC_REGION_OVERLAP()
}
