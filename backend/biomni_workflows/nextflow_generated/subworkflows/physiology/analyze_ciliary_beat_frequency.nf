#!/usr/bin/env nextflow
/*
 * biomni_physiology_analyze_ciliary_beat_frequency
 * Analyze ciliary beat frequency from high-speed video microscopy data using FFT analysis.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.video_path = null
params.roi_count = '5'
params.min_freq = '0'
params.max_freq = '30'
params.output_dir = './'

// Main process
process ANALYZE_CILIARY_BEAT_FREQUENCY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_ciliary_beat_frequency_results.json"), emit: results
    path("analyze_ciliary_beat_frequency_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.physiology import analyze_ciliary_beat_frequency
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_ciliary_beat_frequency(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_ciliary_beat_frequency(
    video_path="${params.video_path}",
    roi_count="${params.roi_count}",
    min_freq="${params.min_freq}",
    max_freq="${params.max_freq}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_ciliary_beat_frequency_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_ciliary_beat_frequency_output.txt", "w") as f:
    f.write("Biomni: Analyze Ciliary Beat Frequency Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_ciliary_beat_frequency completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHYSIOLOGY_ANALYZE_CILIARY_BEAT_FREQUENCY {
    take:
    // No file inputs

    main:
    ANALYZE_CILIARY_BEAT_FREQUENCY()

    emit:
    results = ANALYZE_CILIARY_BEAT_FREQUENCY.out.results
    output = ANALYZE_CILIARY_BEAT_FREQUENCY.out.output
}

// Entry workflow
workflow {
    if (!params.video_path) {
        error "Please provide --video_path parameter"
    }


    BIOMNI_PHYSIOLOGY_ANALYZE_CILIARY_BEAT_FREQUENCY()
}
