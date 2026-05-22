#!/usr/bin/env nextflow
/*
 * bioengineering/analyze_calcium_imaging_data
 * Analyze calcium imaging data to quantify neuronal activity metrics.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Use null to trigger synthetic data generation for testing
params.image_stack_path = null
params.output_dir = './'

process ANALYZE_CALCIUM_IMAGING_DATA {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_calcium_imaging_data_results.json"), emit: results
    tuple val(meta), path("analyze_calcium_imaging_data_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_STACK_PATH="${params.image_stack_path?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_calcium_imaging_data(image_stack_path, output_dir="./"):
    '''Analyze calcium imaging data to quantify neuronal activity metrics.

    This function processes fluorescence microscopy images of GCaMP-labeled neurons
    to extract quantitative metrics of neuronal activity, including cell counts,
    event rates, decay times, and signal-to-noise ratios.

    Parameters
    ----------
    image_stack_path : str
        Path to the time-series stack of fluorescence microscopy images (TIFF format)
    output_dir : str, optional
        Directory to save output files (default: "./")

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    import os

    import numpy as np
    import pandas as pd
    from scipy import ndimage, signal
    from scipy.optimize import curve_fit
    from skimage import feature, filters, io, measure, segmentation

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Step 1: Load the image stack
    log = "CALCIUM IMAGING ANALYSIS LOG\\n"
    log += "===========================\\n\\n"
    log += f"Loading image stack from: {image_stack_path}\\n"

    try:
        image_stack = io.imread(image_stack_path)
        num_frames, height, width = image_stack.shape
        log += f"Successfully loaded {num_frames} frames of size {height}x{width}\\n\\n"
    except Exception as e:
        return f"Error loading image stack: {str(e)}"

    # Step 2: Calculate mean image for segmentation
    log += "Step 1: Preprocessing and neuron segmentation\\n"
    mean_image = np.mean(image_stack, axis=0)

    # Apply Gaussian filter to reduce noise
    smooth_mean = filters.gaussian(mean_image, sigma=2)

    # Step 3: Segment neurons using watershed
    # Find local maxima (potential cell centers)
    distance = ndimage.distance_transform_edt(smooth_mean)
    # Create a mask for local maxima instead of using indices=False parameter
    coordinates = feature.peak_local_max(distance, min_distance=10)

    # Handle case where no local maxima are found
    if len(coordinates) == 0:
        log += "No local maxima detected. Using simple thresholding instead.\\n"
        # Create a simple binary mask using thresholding as fallback
        binary_mask = smooth_mean > filters.threshold_otsu(smooth_mean)
        markers = measure.label(binary_mask)
    else:
        local_max = np.zeros_like(distance, dtype=bool)
        for coord in coordinates:
            local_max[coord[0], coord[1]] = True
        markers = measure.label(local_max)

    # Watershed segmentation
    segmented = segmentation.watershed(-smooth_mean, markers, mask=smooth_mean > filters.threshold_otsu(smooth_mean))

    # Get region properties
    regions = measure.regionprops(segmented)
    cell_count = len(regions)
    log += f"Detected {cell_count} neurons in the field of view\\n\\n"

    # Step 4: Extract time-series data for each neuron
    log += "Step 2: Extracting fluorescence time-series for each neuron\\n"
    time_series_data = []

    for _i, region in enumerate(regions):
        mask = segmented == region.label
        cell_time_series = []

        for frame in range(num_frames):
            intensity = np.mean(image_stack[frame][mask])
            cell_time_series.append(intensity)

        time_series_data.append(cell_time_series)

    time_series_array = np.array(time_series_data)

    # Step 5: Detect calcium events and calculate metrics
    log += "Step 3: Calculating neuronal activity metrics\\n"

    # Function to fit exponential decay
    def exp_decay(x, a, tau, c):
        return a * np.exp(-x / tau) + c

    event_rates = []
    decay_times = []
    snr_values = []

    for i, ts in enumerate(time_series_data):
        # Normalize time series
        baseline = np.percentile(ts, 20)
        ts_norm = [(x - baseline) / baseline for x in ts]

        # Simple event detection (threshold crossing)
        threshold = np.std(ts_norm) * 2
        events = []
        in_event = False

        for j, val in enumerate(ts_norm):
            if not in_event and val > threshold:
                events.append(j)
                in_event = True
            elif in_event and val < threshold:
                in_event = False

        # Calculate event rate (events per minute, assuming 10 Hz acquisition)
        acquisition_rate = 10  # Hz (assumption)
        recording_time_minutes = num_frames / acquisition_rate / 60
        event_rate = len(events) / recording_time_minutes
        event_rates.append(event_rate)

        # Calculate decay times for detected events
        cell_decay_times = []
        for event_start in events:
            if event_start + 30 < len(ts_norm):  # Ensure enough frames after event
                event_window = ts_norm[event_start : event_start + 30]
                peak_idx = np.argmax(event_window)
                decay_segment = event_window[peak_idx:]

                try:
                    # Fit exponential decay
                    x_data = np.arange(len(decay_segment))
                    popt, _ = curve_fit(
                        exp_decay,
                        x_data,
                        decay_segment,
                        p0=[decay_segment[0], 5, decay_segment[-1]],
                        bounds=([0, 0, 0], [np.inf, np.inf, np.inf]),
                    )
                    tau = popt[1]  # Decay time constant
                    cell_decay_times.append(tau / acquisition_rate)  # Convert to seconds
                except Exception:
                    # Skip if curve fitting fails
                    pass

        if cell_decay_times:
            decay_times.append(np.mean(cell_decay_times))
        else:
            decay_times.append(np.nan)

        # Calculate signal-to-noise ratio
        signal = np.mean([ts_norm[e] for e in events]) if events else 0  # noqa: F811
        noise = np.std([ts_norm[i] for i in range(len(ts_norm)) if all(abs(i - e) > 5 for e in events)])
        snr = signal / noise if noise > 0 else 0
        snr_values.append(snr)

    # Step 6: Compile and save results
    cell_metrics = pd.DataFrame(
        {
            "Cell_ID": range(1, cell_count + 1),
            "Event_Rate_per_min": event_rates,
            "Decay_Time_sec": decay_times,
            "SNR": snr_values,
        }
    )

    metrics_file = os.path.join(output_dir, "neuron_activity_metrics.csv")
    cell_metrics.to_csv(metrics_file, index=False)

    # Save time series data
    time_series_file = os.path.join(output_dir, "neuron_time_series.csv")
    time_series_df = pd.DataFrame(time_series_array.T)
    time_series_df.columns = [f"Cell_{i + 1}" for i in range(cell_count)]
    time_series_df.to_csv(time_series_file, index=False)

    # Step 7: Summarize results
    log += f"Cell count: {cell_count}\\n"
    log += f"Average event rate: {np.nanmean(event_rates):.2f} events/min\\n"
    log += f"Average decay time: {np.nanmean(decay_times):.2f} seconds\\n"
    log += f"Average SNR: {np.nanmean(snr_values):.2f}\\n\\n"

    log += "Step 4: Results saved to files\\n"
    log += f"Neuron activity metrics saved to: {metrics_file}\\n"
    log += f"Time series data saved to: {time_series_file}\\n"

    return log

# Execute the function
try:
    result = analyze_calcium_imaging_data(
        image_stack_path=auto_convert(os.environ.get("PARAM_IMAGE_STACK_PATH", "")),
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
    "function": "analyze_calcium_imaging_data",
    "domain": "bioengineering",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_calcium_imaging_data_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_calcium_imaging_data_output.txt", "w") as f:
    f.write("Biomni: Analyze Calcium Imaging Data" + NL)
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
        biomni_function: "analyze_calcium_imaging_data"
    END_VERSIONS
    """
}

workflow ANALYZE_CALCIUM_IMAGING_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_CALCIUM_IMAGING_DATA(ch_input)

    emit:
    results = ANALYZE_CALCIUM_IMAGING_DATA.out.results
    output = ANALYZE_CALCIUM_IMAGING_DATA.out.output
    versions = ANALYZE_CALCIUM_IMAGING_DATA.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_CALCIUM_IMAGING_DATA_WORKFLOW(ch_input)

    ANALYZE_CALCIUM_IMAGING_DATA_WORKFLOW.out.output.view { "Output: $it" }
}
