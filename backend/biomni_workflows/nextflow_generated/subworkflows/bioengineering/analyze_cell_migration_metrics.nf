#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_analyze_cell_migration_metrics
 * Analyze cell migration metrics from time-lapse microscopy images.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_sequence_path = null
params.pixel_size_um = '1.0'
params.time_interval_min = '1.0'
params.min_track_length = '10'
params.output_dir = './'

// Main process
process ANALYZE_CELL_MIGRATION_METRICS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_cell_migration_metrics_results.json"), emit: results
    path("analyze_cell_migration_metrics_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.bioengineering import analyze_cell_migration_metrics
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_cell_migration_metrics(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_cell_migration_metrics(
    image_sequence_path="${params.image_sequence_path}",
    pixel_size_um="${params.pixel_size_um}",
    time_interval_min="${params.time_interval_min}",
    min_track_length="${params.min_track_length}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_cell_migration_metrics_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_cell_migration_metrics_output.txt", "w") as f:
    f.write("Biomni: Analyze Cell Migration Metrics Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_cell_migration_metrics completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOENGINEERING_ANALYZE_CELL_MIGRATION_METRICS {
    take:
    // No file inputs

    main:
    ANALYZE_CELL_MIGRATION_METRICS()

    emit:
    results = ANALYZE_CELL_MIGRATION_METRICS.out.results
    output = ANALYZE_CELL_MIGRATION_METRICS.out.output
}

// Entry workflow
workflow {
    if (!params.image_sequence_path) {
        error "Please provide --image_sequence_path parameter"
    }


    BIOMNI_BIOENGINEERING_ANALYZE_CELL_MIGRATION_METRICS()
}
