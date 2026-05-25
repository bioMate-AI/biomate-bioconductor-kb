#!/usr/bin/env nextflow
/*
 * physiology/analyze_abr_waveform_p1_metrics
 * Extracts P1 amplitude and latency from Auditory Brainstem Response (ABR) waveform data.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Simulated ABR waveform data (0-10 ms with peaks at P1, N1, P2)
// Time points from 0 to 10 ms in 0.1 ms increments
params.time_ms = '[0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 3.0, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 4.0, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.9, 5.0]'
// Simulated amplitude in microvolts with P1 peak around 1.8 ms
params.amplitude_uv = '[0.0, 0.02, 0.05, 0.08, 0.12, 0.18, 0.25, 0.35, 0.48, 0.65, 0.85, 1.05, 1.25, 1.40, 1.50, 1.55, 1.52, 1.42, 1.28, 1.10, 0.88, 0.65, 0.42, 0.20, 0.02, -0.12, -0.22, -0.28, -0.30, -0.28, -0.22, -0.12, 0.0, 0.15, 0.32, 0.48, 0.62, 0.72, 0.78, 0.80, 0.78, 0.72, 0.62, 0.50, 0.38, 0.25, 0.15, 0.08, 0.03, 0.01, 0.0]'

process ANALYZE_ABR_WAVEFORM_P1_METRICS {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_abr_waveform_p1_metrics_results.json"), emit: results
    tuple val(meta), path("analyze_abr_waveform_p1_metrics_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TIME_MS="${params.time_ms?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_AMPLITUDE_UV="${params.amplitude_uv?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os

def auto_convert(val):
    # Auto-convert string to appropriate type
    if val is None or val == '' or val == 'null':
        return None
    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    # Try float
    try:
        return float(val)
    except ValueError:
        pass
    # Return as string
    return val



def analyze_abr_waveform_p1_metrics(time_ms, amplitude_uv):
    '''Extracts P1 amplitude and latency from Auditory Brainstem Response (ABR) waveform data.

    P1 (Wave I) is typically the first positive peak in the ABR waveform and is a critical
    marker for auditory function assessment.

    Parameters
    ----------
    time_ms : array-like
        Time points of the ABR recording in milliseconds
    amplitude_uv : array-like
        Amplitude values of the ABR recording in microvolts

    Returns
    -------
    str
        Research log summarizing the analysis steps and results, including P1 amplitude and latency

    '''
    import numpy as np
    from scipy.signal import find_peaks

    # Convert inputs to numpy arrays if they aren't already
    time_ms = np.array(time_ms)
    amplitude_uv = np.array(amplitude_uv)

    # Find all positive peaks in the waveform
    # Height parameter can be adjusted based on expected signal-to-noise ratio
    peaks, peak_properties = find_peaks(amplitude_uv, height=0)

    if len(peaks) == 0:
        return "Research Log: No positive peaks detected in the ABR waveform."

    # Calculate peak heights (amplitudes)
    peak_heights = peak_properties["peak_heights"]

    # Get the time points (latencies) of the peaks
    peak_latencies = time_ms[peaks]

    # Identify the P1 peak (typically the first significant peak, usually within 1-2 ms)
    # We'll look for peaks in the expected time window for P1 (typically 1-3 ms)
    p1_window_indices = np.where((peak_latencies >= 1) & (peak_latencies <= 3))[0]

    if len(p1_window_indices) == 0:
        # If no peaks in the expected P1 window, use the first peak as P1
        p1_index = 0
    else:
        # Use the highest peak in the P1 window
        p1_index = p1_window_indices[np.argmax(peak_heights[p1_window_indices])]

    p1_amplitude = peak_heights[p1_index]
    p1_latency = peak_latencies[p1_index]

    # Create research log
    log = (
        f"Research Log: ABR Waveform P1 Analysis\\n"
        f"- Analyzed waveform with {len(time_ms)} data points\\n"
        f"- Detected {len(peaks)} positive peaks in the waveform\\n"
        f"- Identified P1 peak metrics:\\n"
        f"  * P1 Amplitude: {p1_amplitude:.2f} μV\\n"
        f"  * P1 Latency: {p1_latency:.2f} ms\\n"
        f"- Analysis complete"
    )

    return log

# Execute the function
try:
    result = analyze_abr_waveform_p1_metrics(
        time_ms=auto_convert(os.environ.get("PARAM_TIME_MS", "")),
        amplitude_uv=auto_convert(os.environ.get("PARAM_AMPLITUDE_UV", "")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "analyze_abr_waveform_p1_metrics",
    "domain": "physiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_abr_waveform_p1_metrics_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_abr_waveform_p1_metrics_output.txt", "w") as f:
    f.write("Biomni: Analyze Abr Waveform P1 Metrics" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "analyze_abr_waveform_p1_metrics"
    END_VERSIONS
    """
}

workflow ANALYZE_ABR_WAVEFORM_P1_METRICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_ABR_WAVEFORM_P1_METRICS(ch_input)

    emit:
    results = ANALYZE_ABR_WAVEFORM_P1_METRICS.out.results
    output = ANALYZE_ABR_WAVEFORM_P1_METRICS.out.output
    versions = ANALYZE_ABR_WAVEFORM_P1_METRICS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_ABR_WAVEFORM_P1_METRICS_WORKFLOW(ch_input)

    ANALYZE_ABR_WAVEFORM_P1_METRICS_WORKFLOW.out.output.view { "Output: $it" }
}
