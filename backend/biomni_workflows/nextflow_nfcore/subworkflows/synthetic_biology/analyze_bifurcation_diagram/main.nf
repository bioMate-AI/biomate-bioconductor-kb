#!/usr/bin/env nextflow
/*
 * synthetic_biology/analyze_bifurcation_diagram
 * Performs bifurcation analysis on a dynamical system and generates a bifurcation diagram.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Bifurcation analysis of logistic map (2D array: rows=parameter values, cols=time points)
params.time_series_data = '[[0.1, 0.2, 0.35, 0.45, 0.49, 0.5, 0.5], [0.1, 0.25, 0.45, 0.55, 0.62, 0.65, 0.65], [0.1, 0.3, 0.55, 0.72, 0.58, 0.71, 0.6], [0.1, 0.35, 0.68, 0.82, 0.55, 0.93, 0.25], [0.1, 0.36, 0.73, 0.79, 0.67, 0.89, 0.39]]'
params.parameter_values = '[2.5, 3.0, 3.3, 3.5, 3.8]'
params.system_name = 'Logistic Map'
params.output_dir = './'

process ANALYZE_BIFURCATION_DIAGRAM {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_bifurcation_diagram_results.json"), emit: results
    tuple val(meta), path("analyze_bifurcation_diagram_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TIME_SERIES_DATA="${params.time_series_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PARAMETER_VALUES="${params.parameter_values?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SYSTEM_NAME="${params.system_name?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_bifurcation_diagram(time_series_data, parameter_values, system_name="Dynamical System", output_dir="./"):
    '''Performs bifurcation analysis on a dynamical system and generates a bifurcation diagram.

    Parameters
    ----------
    time_series_data : numpy.ndarray
        A 2D array where each row represents a time series for a specific parameter value.
        Shape should be (n_parameter_values, n_time_points).
    parameter_values : numpy.ndarray
        1D array of parameter values corresponding to each time series.
        Shape should be (n_parameter_values,).
    system_name : str, optional
        Name of the dynamical system being analyzed, used for plot titles.
    output_dir : str, optional
        Directory to save the output files.

    Returns
    -------
    str
        Research log summarizing the bifurcation analysis process and results.

    '''
    import os

    import matplotlib

    matplotlib.use("Agg")  # Use non-interactive backend
    import matplotlib.pyplot as plt
    import numpy as np
    from scipy.signal import find_peaks

    # Convert inputs to numpy arrays if they aren't already
    time_series_data = np.asarray(time_series_data)
    parameter_values = np.asarray(parameter_values)

    # Create output directory if it doesn't exist
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Initialize research log
    research_log = f"# Bifurcation Analysis for {system_name}\\n\\n"
    research_log += "## Analysis Steps\\n\\n"

    # Step 1: Verify input data
    research_log += "### Step 1: Data Verification\\n"
    if len(parameter_values) != time_series_data.shape[0]:
        research_log += "Error: Number of parameter values does not match number of time series.\\n"
        return research_log

    research_log += f"- Analyzed {len(parameter_values)} parameter values\\n"
    research_log += f"- Each time series contains {time_series_data.shape[1]} data points\\n\\n"

    # Step 2: Calculate indicators for different dynamical regimes
    research_log += "### Step 2: Calculating Dynamical Indicators\\n"

    # Initialize arrays to store results
    local_maxima_counts = np.zeros(len(parameter_values))
    lyapunov_estimates = np.zeros(len(parameter_values))
    attractor_points = []

    for i, series in enumerate(time_series_data):
        # Use the last 70% of the time series to avoid transients
        steady_state = series[int(0.7 * len(series)) :]

        # Find local maxima (peaks) to identify periodicity
        peaks, _ = find_peaks(steady_state)
        local_maxima_counts[i] = len(peaks)

        # Simple estimate of the largest Lyapunov exponent
        # Positive values suggest chaos, negative values suggest stability
        if len(steady_state) > 10:
            diffs = np.abs(np.diff(steady_state))
            if np.mean(diffs) > 0:
                lyapunov_estimates[i] = np.log(np.mean(diffs))
            else:
                lyapunov_estimates[i] = -1.0  # Stable behavior

        # Collect points for the bifurcation diagram
        # We use local maxima as sampling points for the attractor
        if len(peaks) > 0:
            attractor_points.append((parameter_values[i], steady_state[peaks]))
        else:
            # If no peaks, use the last few points
            attractor_points.append((parameter_values[i], steady_state[-5:]))

    research_log += "- Calculated approximate Lyapunov exponents\\n"
    research_log += "- Identified local maxima for periodicity analysis\\n"
    research_log += "- Sampled attractor points for bifurcation diagram\\n\\n"

    # Step 3: Classify dynamical regimes
    research_log += "### Step 3: Classifying Dynamical Regimes\\n"

    # Initialize arrays for regime classification
    regimes = np.full(len(parameter_values), "unknown", dtype=object)

    # Classify based on Lyapunov exponent and periodicity
    for i in range(len(parameter_values)):
        if lyapunov_estimates[i] > 0.05:
            regimes[i] = "chaotic"
        elif local_maxima_counts[i] == 0:
            regimes[i] = "stable"
        elif local_maxima_counts[i] == 1:
            regimes[i] = "period-1"
        elif local_maxima_counts[i] == 2:
            regimes[i] = "period-2"
        elif local_maxima_counts[i] == 4:
            regimes[i] = "period-4"
        elif local_maxima_counts[i] > 4:
            if lyapunov_estimates[i] > 0:
                regimes[i] = "chaotic"
            else:
                regimes[i] = f"period-{int(local_maxima_counts[i])}"

    # Count regime types
    unique_regimes = np.unique(regimes)
    for regime in unique_regimes:
        count = np.sum(regimes == regime)
        research_log += f"- Identified {count} parameter values in '{regime}' regime\\n"

    research_log += "\\n"

    # Step 4: Create bifurcation diagram
    research_log += "### Step 4: Creating Bifurcation Diagram\\n"

    plt.figure(figsize=(12, 8))

    # Plot bifurcation points
    for param_val, points in attractor_points:
        y_values = points.flatten()  # Flatten in case points is multi-dimensional
        plt.plot([param_val] * len(y_values), y_values, "k.", markersize=0.5)

    # Highlight different regimes with colored background
    regime_changes = np.where(regimes[:-1] != regimes[1:])[0]
    regime_boundaries = (
        [parameter_values[0]] + [parameter_values[i + 1] for i in regime_changes] + [parameter_values[-1]]
    )

    colors = {
        "stable": "lightblue",
        "period-1": "lightgreen",
        "period-2": "lightyellow",
        "period-4": "lightpink",
        "chaotic": "salmon",
    }

    for i in range(len(regime_boundaries) - 1):
        start_idx = list(parameter_values).index(regime_boundaries[i])
        regime = regimes[start_idx]
        if regime in colors:
            plt.axvspan(
                regime_boundaries[i],
                regime_boundaries[i + 1],
                alpha=0.3,
                color=colors.get(regime, "lightgray"),
            )

    plt.xlabel("Parameter Value")
    plt.ylabel("State Variable")
    plt.title(f"Bifurcation Diagram for {system_name}")

    # Add legend for regimes
    from matplotlib.patches import Patch

    legend_elements = [
        Patch(facecolor=colors.get(regime, "lightgray"), alpha=0.3, label=regime)
        for regime in unique_regimes
        if regime in colors
    ]
    plt.legend(handles=legend_elements, loc="upper right")

    # Save the figure
    output_file = os.path.join(output_dir, f"{system_name.replace(' ', '_')}_bifurcation_diagram.png")
    plt.savefig(output_file, dpi=300)
    plt.close()

    research_log += "- Created bifurcation diagram showing different dynamical regimes\\n"
    research_log += f"- Diagram saved as: {output_file}\\n\\n"

    # Step 5: Identify regime transitions
    research_log += "### Step 5: Identifying Regime Transitions\\n"

    if len(regime_changes) > 0:
        for i in regime_changes:
            research_log += f"- Transition from '{regimes[i]}' to '{regimes[i + 1]}' at parameter value ≈ {parameter_values[i + 1]:.4f}\\n"
    else:
        research_log += "- No regime transitions detected in the parameter range\\n"

    research_log += "\\n### Summary\\n"
    research_log += f"Bifurcation analysis completed for {system_name}. "
    research_log += f"The system exhibits {len(unique_regimes)} different dynamical regimes "
    research_log += f"across the parameter range [{parameter_values[0]:.4f}, {parameter_values[-1]:.4f}].\\n"

    return research_log

# Execute the function
try:
    result = analyze_bifurcation_diagram(
        time_series_data=auto_convert(os.environ.get("PARAM_TIME_SERIES_DATA", "")),
        parameter_values=auto_convert(os.environ.get("PARAM_PARAMETER_VALUES", "")),
        system_name=auto_convert(os.environ.get("PARAM_SYSTEM_NAME", "Dynamical System")),
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
    "function": "analyze_bifurcation_diagram",
    "domain": "synthetic_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_bifurcation_diagram_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_bifurcation_diagram_output.txt", "w") as f:
    f.write("Biomni: Analyze Bifurcation Diagram" + NL)
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
        biomni_function: "analyze_bifurcation_diagram"
    END_VERSIONS
    """
}

workflow ANALYZE_BIFURCATION_DIAGRAM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_BIFURCATION_DIAGRAM(ch_input)

    emit:
    results = ANALYZE_BIFURCATION_DIAGRAM.out.results
    output = ANALYZE_BIFURCATION_DIAGRAM.out.output
    versions = ANALYZE_BIFURCATION_DIAGRAM.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_BIFURCATION_DIAGRAM_WORKFLOW(ch_input)

    ANALYZE_BIFURCATION_DIAGRAM_WORKFLOW.out.output.view { "Output: $it" }
}
