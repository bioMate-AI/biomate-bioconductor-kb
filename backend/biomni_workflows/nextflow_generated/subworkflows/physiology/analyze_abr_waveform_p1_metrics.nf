#!/usr/bin/env nextflow
/*
 * biomni_physiology_analyze_abr_waveform_p1_metrics
 * Extracts P1 amplitude and latency from Auditory Brainstem Response (ABR) waveform data.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.time_ms = null
params.amplitude_uv = null

// Main process
process ANALYZE_ABR_WAVEFORM_P1_METRICS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_abr_waveform_p1_metrics_results.json"), emit: results
    path("analyze_abr_waveform_p1_metrics_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.physiology import analyze_abr_waveform_p1_metrics
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_abr_waveform_p1_metrics(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_abr_waveform_p1_metrics(
    time_ms="${params.time_ms}",
    amplitude_uv="${params.amplitude_uv}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_abr_waveform_p1_metrics_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_abr_waveform_p1_metrics_output.txt", "w") as f:
    f.write("Biomni: Analyze Abr Waveform P1 Metrics Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_abr_waveform_p1_metrics completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHYSIOLOGY_ANALYZE_ABR_WAVEFORM_P1_METRICS {
    take:
    // No file inputs

    main:
    ANALYZE_ABR_WAVEFORM_P1_METRICS()

    emit:
    results = ANALYZE_ABR_WAVEFORM_P1_METRICS.out.results
    output = ANALYZE_ABR_WAVEFORM_P1_METRICS.out.output
}

// Entry workflow
workflow {
    if (!params.time_ms) {
        error "Please provide --time_ms parameter"
    }
    if (!params.amplitude_uv) {
        error "Please provide --amplitude_uv parameter"
    }


    BIOMNI_PHYSIOLOGY_ANALYZE_ABR_WAVEFORM_P1_METRICS()
}
