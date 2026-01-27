#!/usr/bin/env nextflow
/*
 * physiology/analyze_hemodynamic_data
 * Analyzes raw blood pressure data to calculate key hemodynamic parameters.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Simulated blood pressure waveform (mmHg) at 1000 Hz for 2 seconds
params.pressure_data = '[80, 85, 95, 110, 120, 118, 115, 105, 95, 85, 80, 82, 90, 108, 120, 119, 112, 100, 90, 82, 80, 83, 92, 112, 120, 117, 110, 98, 88, 81, 80, 84, 96, 115, 120, 116, 108, 96, 86, 80, 80, 85, 98, 118, 120, 115, 105, 94, 84, 80]'
params.sampling_rate = '50'
params.output_file = 'hemodynamic_results.csv'

process ANALYZE_HEMODYNAMIC_DATA {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_hemodynamic_data_results.json"), emit: results
    tuple val(meta), path("analyze_hemodynamic_data_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_PRESSURE_DATA="${params.pressure_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SAMPLING_RATE="${params.sampling_rate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_FILE="${params.output_file?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def analyze_hemodynamic_data(pressure_data, sampling_rate, output_file="hemodynamic_results.csv"):
    '''Analyzes raw blood pressure data to calculate key hemodynamic parameters.

    Parameters
    ----------
    pressure_data : numpy.ndarray
        Raw blood pressure measurements in mmHg
    sampling_rate : float
        Data acquisition rate in Hz (samples per second)
    output_file : str, optional
        Filename to save the calculated parameters, default is "hemodynamic_results.csv"

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    import numpy as np
    import pandas as pd
    from scipy import signal

    # Step 1: Preprocess the signal
    # Apply a bandpass filter to remove noise while preserving the physiological signal
    nyquist_freq = sampling_rate / 2
    low_cutoff = 0.5 / nyquist_freq  # 0.5 Hz (to preserve slow components)
    high_cutoff = 10 / nyquist_freq  # 10 Hz (to preserve fast components but remove noise)
    b, a = signal.butter(2, [low_cutoff, high_cutoff], btype="band")
    filtered_data = signal.filtfilt(b, a, pressure_data)

    # Step 2: Find peaks (systolic) and troughs (diastolic)
    # For systolic peaks
    peaks, _ = signal.find_peaks(filtered_data, distance=sampling_rate * 0.5)  # Minimum distance between peaks

    # For diastolic troughs (looking for minima between systolic peaks)
    valleys = []
    for i in range(len(peaks) - 1):
        segment = filtered_data[peaks[i] : peaks[i + 1]]
        valley_idx = np.argmin(segment) + peaks[i]
        valleys.append(valley_idx)

    # Step 3: Calculate hemodynamic parameters
    # Systolic Blood Pressure (SBP)
    sbp_values = filtered_data[peaks]
    sbp = np.mean(sbp_values)

    # Diastolic Blood Pressure (DBP)
    dbp_values = filtered_data[valleys]
    dbp = np.mean(dbp_values)

    # Mean Arterial Pressure (MAP)
    # MAP = DBP + (SBP - DBP) / 3
    map_value = dbp + (sbp - dbp) / 3

    # Heart Rate (HR)
    # Calculate average time between peaks and convert to beats per minute
    peak_intervals = np.diff(peaks) / sampling_rate  # Convert to seconds
    heart_rate = 60 / np.mean(peak_intervals)  # Convert to beats per minute

    # Step 4: Save results to CSV
    results_df = pd.DataFrame(
        {
            "Parameter": ["SBP", "DBP", "MAP", "HR"],
            "Value": [sbp, dbp, map_value, heart_rate],
            "Unit": ["mmHg", "mmHg", "mmHg", "bpm"],
        }
    )
    results_df.to_csv(output_file, index=False)

    # Generate research log
    log = f'''Hemodynamic Data Analysis Log:
1. Preprocessed raw pressure data using a bandpass filter (0.5-10 Hz)
2. Detected {len(peaks)} systolic peaks and {len(valleys)} diastolic troughs
3. Calculated hemodynamic parameters:
   - Systolic Blood Pressure (SBP): {sbp:.2f} mmHg
   - Diastolic Blood Pressure (DBP): {dbp:.2f} mmHg
   - Mean Arterial Pressure (MAP): {map_value:.2f} mmHg
   - Heart Rate (HR): {heart_rate:.2f} bpm
4. Results saved to {output_file}
'''

    return log

# Execute the function
try:
    result = analyze_hemodynamic_data(
        pressure_data=auto_convert(os.environ.get("PARAM_PRESSURE_DATA", "")),
        sampling_rate=auto_convert(os.environ.get("PARAM_SAMPLING_RATE", "")),
        output_file=auto_convert(os.environ.get("PARAM_OUTPUT_FILE", "hemodynamic_results.csv")),
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
    "function": "analyze_hemodynamic_data",
    "domain": "physiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_hemodynamic_data_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_hemodynamic_data_output.txt", "w") as f:
    f.write("Biomni: Analyze Hemodynamic Data" + NL)
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
        biomni_function: "analyze_hemodynamic_data"
    END_VERSIONS
    """
}

workflow ANALYZE_HEMODYNAMIC_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_HEMODYNAMIC_DATA(ch_input)

    emit:
    results = ANALYZE_HEMODYNAMIC_DATA.out.results
    output = ANALYZE_HEMODYNAMIC_DATA.out.output
    versions = ANALYZE_HEMODYNAMIC_DATA.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_HEMODYNAMIC_DATA_WORKFLOW(ch_input)

    ANALYZE_HEMODYNAMIC_DATA_WORKFLOW.out.output.view { "Output: $it" }
}
