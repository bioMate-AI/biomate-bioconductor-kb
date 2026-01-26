#!/usr/bin/env nextflow
/*
 * physiology/analyze_ciliary_beat_frequency
 * Analyze ciliary beat frequency from high-speed video microscopy data using FFT analysis.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.video_path = null
params.roi_count = '5'
params.min_freq = '0'
params.max_freq = '30'
params.output_dir = './'

process ANALYZE_CILIARY_BEAT_FREQUENCY {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_ciliary_beat_frequency_results.json"), emit: results
    tuple val(meta), path("analyze_ciliary_beat_frequency_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_VIDEO_PATH="${params.video_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ROI_COUNT="${params.roi_count?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MIN_FREQ="${params.min_freq?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MAX_FREQ="${params.max_freq?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def analyze_ciliary_beat_frequency(video_path, roi_count=5, min_freq=0, max_freq=30, output_dir="./"):
    '''Analyze ciliary beat frequency from high-speed video microscopy data using FFT analysis.

    Parameters
    ----------
    video_path : str
        Path to the high-speed video microscopy file of ciliary beating
    roi_count : int, optional
        Number of regions of interest to analyze (default: 5)
    min_freq : float, optional
        Minimum frequency to consider in Hz (default: 0)
    max_freq : float, optional
        Maximum frequency to consider in Hz (default: 30)
    output_dir : str, optional
        Directory to save output files (default: current directory)

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    import os
    from datetime import datetime

    import cv2
    import numpy as np
    import pandas as pd
    from scipy.fftpack import fft

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Initialize research log
    log = []
    log.append(f"CILIARY BEAT FREQUENCY ANALYSIS - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    log.append(f"Video file: {video_path}")

    # Open the video file
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return f"Error: Could not open video file {video_path}"

    # Get video properties
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    log.append(f"Video properties: {width}x{height}, {fps} fps, {frame_count} frames")

    # Extract frames and prepare for analysis
    log.append("Extracting frames and preparing for analysis...")

    # Create regions of interest (ROIs)
    rois = []
    roi_size = min(width, height) // 10  # ROI size as 1/10 of the smallest dimension

    # Generate ROIs in a grid pattern
    rows = int(np.sqrt(roi_count))
    cols = (roi_count + rows - 1) // rows  # Ceiling division

    for i in range(rows):
        for j in range(cols):
            if len(rois) >= roi_count:
                break

            x = (j + 1) * width // (cols + 1) - roi_size // 2
            y = (i + 1) * height // (rows + 1) - roi_size // 2

            # Ensure ROI is within frame boundaries
            x = max(0, min(x, width - roi_size))
            y = max(0, min(y, height - roi_size))

            rois.append((x, y, roi_size, roi_size))

    log.append(f"Created {len(rois)} regions of interest for analysis")

    # Extract intensity time series for each ROI
    intensity_series = [[] for _ in range(len(rois))]

    frame_idx = 0
    while cap.isOpened() and frame_idx < frame_count:
        ret, frame = cap.read()
        if not ret:
            break

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        for i, (x, y, w, h) in enumerate(rois):
            roi = gray[y : y + h, x : x + w]
            intensity_series[i].append(np.mean(roi))

        frame_idx += 1

    cap.release()

    log.append(f"Processed {frame_idx} frames for time series analysis")

    # Perform FFT analysis on each ROI
    frequencies = []

    for i, series in enumerate(intensity_series):
        # Convert to numpy array
        series = np.array(series)

        # Remove DC component (mean)
        series = series - np.mean(series)

        # Apply Hanning window to reduce spectral leakage
        window = np.hanning(len(series))
        series = series * window

        # Compute FFT
        fft_result = fft(series)
        fft_magnitude = np.abs(fft_result[: len(series) // 2])

        # Compute frequency axis
        freq_axis = np.fft.fftfreq(len(series), d=1 / fps)[: len(series) // 2]

        # Find dominant frequency in the specified range
        valid_indices = (freq_axis >= min_freq) & (freq_axis <= max_freq)
        valid_freq = freq_axis[valid_indices]
        valid_magnitude = fft_magnitude[valid_indices]

        if len(valid_magnitude) > 0 and np.max(valid_magnitude) > 0:
            dominant_idx = np.argmax(valid_magnitude)
            dominant_freq = valid_freq[dominant_idx]
            frequencies.append(dominant_freq)
            log.append(f"ROI #{i + 1}: Dominant frequency = {dominant_freq:.2f} Hz")

    # Calculate median frequency
    if frequencies:
        median_cbf = np.median(frequencies)
        log.append(f"\\nResults: Detected {len(frequencies)} valid ciliary regions")
        log.append(f"Median ciliary beat frequency: {median_cbf:.2f} Hz")

        # Save results to CSV
        results_file = os.path.join(output_dir, "cbf_results.csv")
        df = pd.DataFrame({"ROI": range(1, len(frequencies) + 1), "Beat_Frequency_Hz": frequencies})
        df.to_csv(results_file, index=False)
        log.append(f"\\nDetailed frequency data saved to: {results_file}")
    else:
        log.append("\\nNo valid ciliary beat frequencies detected in the specified range")

    return "\\n".join(log)

# Execute the function
try:
    result = analyze_ciliary_beat_frequency(
        video_path=auto_convert(os.environ.get("PARAM_VIDEO_PATH", "")),
        roi_count=auto_convert(os.environ.get("PARAM_ROI_COUNT", "5")),
        min_freq=auto_convert(os.environ.get("PARAM_MIN_FREQ", "0")),
        max_freq=auto_convert(os.environ.get("PARAM_MAX_FREQ", "30")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./")),
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
    "function": "analyze_ciliary_beat_frequency",
    "domain": "physiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_ciliary_beat_frequency_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_ciliary_beat_frequency_output.txt", "w") as f:
    f.write("Biomni: Analyze Ciliary Beat Frequency" + NL)
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
        biomni_function: "analyze_ciliary_beat_frequency"
    END_VERSIONS
    """
}

workflow ANALYZE_CILIARY_BEAT_FREQUENCY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_CILIARY_BEAT_FREQUENCY(ch_input)

    emit:
    results = ANALYZE_CILIARY_BEAT_FREQUENCY.out.results
    output = ANALYZE_CILIARY_BEAT_FREQUENCY.out.output
    versions = ANALYZE_CILIARY_BEAT_FREQUENCY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_CILIARY_BEAT_FREQUENCY_WORKFLOW(ch_input)

    ANALYZE_CILIARY_BEAT_FREQUENCY_WORKFLOW.out.output.view { "Output: $it" }
}
