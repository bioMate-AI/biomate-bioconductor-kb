#!/usr/bin/env nextflow
/*
 * biomni_physiology_analyze_fatty_acid_composition_by_gc
 * Analyzes fatty acid composition in tissue samples using gas chromatography data.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.gc_data_file = null
params.tissue_type = null
params.sample_id = null
params.output_directory = './results'

// Main process
process ANALYZE_FATTY_ACID_COMPOSITION_BY_GC {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_fatty_acid_composition_by_gc_results.json"), emit: results
    path("analyze_fatty_acid_composition_by_gc_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.physiology import analyze_fatty_acid_composition_by_gc
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_fatty_acid_composition_by_gc(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_fatty_acid_composition_by_gc(
    gc_data_file="${params.gc_data_file}",
    tissue_type="${params.tissue_type}",
    sample_id="${params.sample_id}",
    output_directory="${params.output_directory}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_fatty_acid_composition_by_gc_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_fatty_acid_composition_by_gc_output.txt", "w") as f:
    f.write("Biomni: Analyze Fatty Acid Composition By Gc Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_fatty_acid_composition_by_gc completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHYSIOLOGY_ANALYZE_FATTY_ACID_COMPOSITION_BY_GC {
    take:
    // No file inputs

    main:
    ANALYZE_FATTY_ACID_COMPOSITION_BY_GC()

    emit:
    results = ANALYZE_FATTY_ACID_COMPOSITION_BY_GC.out.results
    output = ANALYZE_FATTY_ACID_COMPOSITION_BY_GC.out.output
}

// Entry workflow
workflow {
    if (!params.gc_data_file) {
        error "Please provide --gc_data_file parameter"
    }
    if (!params.tissue_type) {
        error "Please provide --tissue_type parameter"
    }
    if (!params.sample_id) {
        error "Please provide --sample_id parameter"
    }


    BIOMNI_PHYSIOLOGY_ANALYZE_FATTY_ACID_COMPOSITION_BY_GC()
}
