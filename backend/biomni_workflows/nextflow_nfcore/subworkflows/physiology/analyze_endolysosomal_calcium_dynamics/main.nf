#!/usr/bin/env nextflow
/*
 * physiology/analyze_endolysosomal_calcium_dynamics
 * Analyze calcium dynamics in endo-lysosomal compartments using ELGA/ELGA1 probe data.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: ELGA probe calcium dynamics (baseline then drug treatment)
params.time_points = '[0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300]'
params.luminescence_values = '[1.0, 1.02, 0.98, 1.01, 2.5, 3.8, 4.2, 3.9, 3.2, 2.5, 1.8]'
params.treatment_time = '120'
params.cell_type = 'HeLa'
params.treatment_name = 'GPN'
params.output_file = 'calcium_analysis_results.txt'

process ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_endolysosomal_calcium_dynamics_results.json"), emit: results
    tuple val(meta), path("analyze_endolysosomal_calcium_dynamics_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TIME_POINTS="${params.time_points?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_LUMINESCENCE_VALUES="${params.luminescence_values?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TREATMENT_TIME="${params.treatment_time?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CELL_TYPE="${params.cell_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TREATMENT_NAME="${params.treatment_name?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_endolysosomal_calcium_dynamics(
    time_points,
    luminescence_values,
    treatment_time=None,
    cell_type="",
    treatment_name="",
    output_file="calcium_analysis_results.txt",
):
    '''Analyze calcium dynamics in endo-lysosomal compartments using ELGA/ELGA1 probe data.

    Parameters
    ----------
    time_points : numpy.ndarray or list
        Time points of the measurements in seconds
    luminescence_values : numpy.ndarray or list
        Luminescence intensity values from ELGA/ELGA1 probes corresponding to Ca2+ levels
    treatment_time : float, optional
        Time point (in seconds) when treatment/stimulus was applied
    cell_type : str, optional
        Type of cells used in the experiment
    treatment_name : str, optional
        Name of the treatment or stimulus applied
    output_file : str, optional
        Name of the file to save detailed analysis results

    Returns
    -------
    str
        A research log summarizing the calcium dynamics analysis and key findings

    '''
    import numpy as np
    from scipy import signal

    # Convert inputs to numpy arrays if they aren't already
    time_points = np.array(time_points)
    luminescence_values = np.array(luminescence_values)

    # Calculate baseline Ca2+ levels (average of pre-treatment values or first 10% of data)
    if treatment_time is not None:
        baseline_indices = time_points < treatment_time
        baseline = np.mean(luminescence_values[baseline_indices])
        baseline_std = np.std(luminescence_values[baseline_indices])
    else:
        baseline_idx = int(len(luminescence_values) * 0.1)  # First 10% of data
        baseline = np.mean(luminescence_values[:baseline_idx])
        baseline_std = np.std(luminescence_values[:baseline_idx])

    # Normalize data to baseline
    normalized_values = luminescence_values / baseline

    # Find peaks in Ca2+ signal
    peaks, properties = signal.find_peaks(normalized_values, height=1.1, distance=5)

    # Calculate key metrics
    if len(peaks) > 0:
        peak_heights = properties["peak_heights"]
        max_peak_idx = peaks[np.argmax(peak_heights)]
        max_peak_time = time_points[max_peak_idx]
        max_peak_value = normalized_values[max_peak_idx]

        # Calculate response kinetics if treatment_time is provided
        if treatment_time is not None and max_peak_time > treatment_time:
            response_time = max_peak_time - treatment_time
        else:
            response_time = None

        # Calculate area under the curve (Ca2+ load)
        auc = np.trapezoid(normalized_values - 1, time_points)

        # Calculate decay time (time to return to 50% of peak)
        if max_peak_idx < len(normalized_values) - 1:
            post_peak = normalized_values[max_peak_idx:]
            post_peak_times = time_points[max_peak_idx:]
            half_peak_value = 1 + (max_peak_value - 1) / 2

            # Find where signal drops below half-peak
            below_half_indices = np.where(post_peak < half_peak_value)[0]
            if len(below_half_indices) > 0:
                half_decay_idx = below_half_indices[0]
                decay_time = post_peak_times[half_decay_idx] - max_peak_time
            else:
                decay_time = None
        else:
            decay_time = None
    else:
        max_peak_value = None
        max_peak_time = None
        response_time = None
        auc = np.trapezoid(normalized_values - 1, time_points)
        decay_time = None

    # Calculate coefficient of variation to measure Ca2+ fluctuations
    cv = np.std(normalized_values) / np.mean(normalized_values)

    # Save detailed results to file
    with open(output_file, "w") as f:
        f.write("Endo-lysosomal Ca2+ Dynamics Analysis Results\\n")
        f.write("===========================================\\n\\n")
        f.write(f"Cell Type: {cell_type}\\n")
        f.write(f"Treatment: {treatment_name}\\n\\n")
        f.write(f"Baseline Ca2+ level: {baseline:.2f} ± {baseline_std:.2f}\\n")
        f.write(f"Number of detected Ca2+ peaks: {len(peaks)}\\n")

        if max_peak_value is not None:
            f.write(f"Maximum Ca2+ peak: {max_peak_value:.2f} (normalized to baseline)\\n")
            f.write(f"Time of maximum peak: {max_peak_time:.2f} seconds\\n")

        if response_time is not None:
            f.write(f"Response time after treatment: {response_time:.2f} seconds\\n")

        if decay_time is not None:
            f.write(f"Half-decay time: {decay_time:.2f} seconds\\n")

        f.write(f"Area under curve (Ca2+ load): {auc:.2f}\\n")
        f.write(f"Coefficient of variation: {cv:.4f}\\n\\n")

        if len(peaks) > 0:
            f.write("All detected peaks (time, normalized intensity):\\n")
            for i, peak_idx in enumerate(peaks):
                f.write(f"  Peak {i + 1}: {time_points[peak_idx]:.2f}s, {normalized_values[peak_idx]:.2f}\\n")

    # Generate research log
    log = f'''
Research Log: Endo-lysosomal Ca2+ Dynamics Analysis using ELGA/ELGA1 Probes

SUMMARY:
Analyzed calcium dynamics in the endo-lysosomal compartment of {cell_type} cells using ELGA/ELGA1 probes.
{f"Cells were treated with {treatment_name} at {treatment_time} seconds." if treatment_time is not None else ""}

METHODS:
- Measured luminescence values from ELGA/ELGA1 probes over {len(time_points)} time points
- Calculated baseline Ca2+ levels and normalized signals
- Identified Ca2+ peaks and analyzed response kinetics
- Quantified Ca2+ load using area under curve analysis

RESULTS:
- Baseline Ca2+ level: {baseline:.2f} ± {baseline_std:.2f} (arbitrary units)
- Detected {len(peaks)} Ca2+ peaks in the endo-lysosomal compartment
{f"- Maximum Ca2+ response: {max_peak_value:.2f}x baseline" if max_peak_value is not None else "- No significant Ca2+ peaks detected"}
{f"- Response time: {response_time:.2f} seconds after treatment" if response_time is not None else ""}
{f"- Half-decay time: {decay_time:.2f} seconds" if decay_time is not None else ""}
- Total Ca2+ load (AUC): {auc:.2f}
- Ca2+ signal variability (CV): {cv:.4f}

Detailed numerical results saved to: {output_file}
'''

    return log

# Execute the function
try:
    result = analyze_endolysosomal_calcium_dynamics(
        time_points=auto_convert(os.environ.get("PARAM_TIME_POINTS", "")),
        luminescence_values=auto_convert(os.environ.get("PARAM_LUMINESCENCE_VALUES", "")),
        treatment_time=auto_convert(os.environ.get("PARAM_TREATMENT_TIME", "")),
        cell_type=auto_convert(os.environ.get("PARAM_CELL_TYPE", "")),
        treatment_name=auto_convert(os.environ.get("PARAM_TREATMENT_NAME", "")),
        output_file=auto_convert(os.environ.get("PARAM_OUTPUT_FILE", "calcium_analysis_results.txt")),
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
    "function": "analyze_endolysosomal_calcium_dynamics",
    "domain": "physiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_endolysosomal_calcium_dynamics_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_endolysosomal_calcium_dynamics_output.txt", "w") as f:
    f.write("Biomni: Analyze Endolysosomal Calcium Dynamics" + NL)
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
        biomni_function: "analyze_endolysosomal_calcium_dynamics"
    END_VERSIONS
    """
}

workflow ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS(ch_input)

    emit:
    results = ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS.out.results
    output = ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS.out.output
    versions = ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS_WORKFLOW(ch_input)

    ANALYZE_ENDOLYSOSOMAL_CALCIUM_DYNAMICS_WORKFLOW.out.output.view { "Output: $it" }
}
