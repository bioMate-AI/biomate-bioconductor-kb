#!/usr/bin/env nextflow
/*
 * synthetic_biology/analyze_bacterial_growth_rate
 * Analyze bacterial growth data and extract growth parameters from OD600 measurements.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.time_points = null
params.od_measurements = null
params.strain_name = 'Unknown strain'
params.output_dir = './'

process ANALYZE_BACTERIAL_GROWTH_RATE {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_bacterial_growth_rate_results.json"), emit: results
    tuple val(meta), path("analyze_bacterial_growth_rate_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TIME_POINTS="${params.time_points?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OD_MEASUREMENTS="${params.od_measurements?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_STRAIN_NAME="${params.strain_name?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_bacterial_growth_rate(time_points, od_measurements, strain_name="Unknown strain", output_dir="./"):
    '''Analyze bacterial growth data and extract growth parameters from OD600 measurements.

    Parameters
    ----------
    time_points : list or numpy.ndarray
        Time points at which OD600 measurements were taken (in hours)
    od_measurements : list or numpy.ndarray
        Optical density (OD600) measurements corresponding to each time point
    strain_name : str, optional
        Name of the bacterial strain being analyzed, default is "Unknown strain"
    output_dir : str, optional
        Directory where to save the output files, default is current directory

    Returns
    -------
    str
        A research log summarizing the analysis steps, fitted parameters, and results

    '''
    import os
    from datetime import datetime

    import matplotlib

    matplotlib.use("Agg")  # Use non-interactive backend
    import matplotlib.pyplot as plt
    import numpy as np
    from scipy.optimize import curve_fit

    # Ensure output directory exists
    os.makedirs(output_dir, exist_ok=True)

    # Convert inputs to numpy arrays if they aren't already
    time_points = np.array(time_points)
    od_measurements = np.array(od_measurements)

    # Define the Gompertz growth model function
    def gompertz_model(t, lag, mu_max, A):
        '''Gompertz growth model.

        Parameters
        ----------
        t: time points
        lag: lag time (hours)
        mu_max: maximum growth rate (per hour)
        A: carrying capacity (maximum OD)

        '''
        return A * np.exp(-np.exp(mu_max * np.exp(1) * (lag - t) / A + 1))

    # Initial parameter guesses
    p0 = [
        np.mean(time_points) / 3,  # lag time guess: 1/3 of the mean time
        0.5,  # growth rate guess: 0.5 per hour
        max(od_measurements) * 1.1,  # carrying capacity: slightly above max OD
    ]

    # Fit the model to the data
    try:
        popt, pcov = curve_fit(
            gompertz_model,
            time_points,
            od_measurements,
            p0=p0,
            bounds=([0, 0, 0], [np.inf, np.inf, np.inf]),
        )
        lag_time, mu_max, carrying_capacity = popt

        # Calculate doubling time (ln(2)/μ)
        doubling_time = np.log(2) / mu_max

        # Generate fitted curve for plotting
        t_smooth = np.linspace(min(time_points), max(time_points), 100)
        od_fit = gompertz_model(t_smooth, *popt)

        # Create growth curve plot
        plt.figure(figsize=(10, 6))
        plt.scatter(time_points, od_measurements, label="Observed OD600")
        plt.plot(t_smooth, od_fit, "r-", label="Fitted Gompertz model")
        plt.xlabel("Time (hours)")
        plt.ylabel("Optical Density (OD600)")
        plt.title(f"Bacterial Growth Curve: {strain_name}")
        plt.legend()
        plt.grid(True, linestyle="--", alpha=0.7)

        # Save the plot
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        plot_filename = os.path.join(output_dir, f"{strain_name.replace(' ', '_')}_{timestamp}_growth_curve.png")
        plt.savefig(plot_filename)
        plt.close()

        # Create research log
        log = f'''## Bacterial Growth Rate Analysis: {strain_name}

### Analysis Summary
- **Date and Time:** {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
- **Sample:** {strain_name}
- **Data Points:** {len(time_points)} measurements over {max(time_points) - min(time_points):.2f} hours

### Growth Parameters (Gompertz Model)
- **Lag Phase Duration:** {lag_time:.2f} hours
- **Maximum Growth Rate (μ_max):** {mu_max:.4f} per hour
- **Doubling Time:** {doubling_time:.2f} hours
- **Carrying Capacity (max OD):** {carrying_capacity:.4f} OD600 units

### Methods
1. OD600 measurements were taken at various time points
2. Data was fitted to the Gompertz growth model
3. Growth parameters were extracted from the fitted model
4. Growth curve was plotted and saved as: {plot_filename}

### Note
The Gompertz model provides a good representation of bacterial growth phases including lag, exponential, and stationary phases.
'''

        return log

    except RuntimeError as e:
        return f'''## Bacterial Growth Rate Analysis: {strain_name}

### Error in Analysis
Failed to fit the growth model to the provided data: {str(e)}

### Suggestions
- Check if the data shows a typical growth pattern
- Ensure sufficient data points are provided
- Try different initial parameter guesses or a different growth model
'''

# Execute the function
try:
    result = analyze_bacterial_growth_rate(
        time_points=auto_convert(os.environ.get("PARAM_TIME_POINTS", "")),
        od_measurements=auto_convert(os.environ.get("PARAM_OD_MEASUREMENTS", "")),
        strain_name=auto_convert(os.environ.get("PARAM_STRAIN_NAME", "Unknown strain")),
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
    "function": "analyze_bacterial_growth_rate",
    "domain": "synthetic_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_bacterial_growth_rate_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_bacterial_growth_rate_output.txt", "w") as f:
    f.write("Biomni: Analyze Bacterial Growth Rate" + NL)
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
        biomni_function: "analyze_bacterial_growth_rate"
    END_VERSIONS
    """
}

workflow ANALYZE_BACTERIAL_GROWTH_RATE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_BACTERIAL_GROWTH_RATE(ch_input)

    emit:
    results = ANALYZE_BACTERIAL_GROWTH_RATE.out.results
    output = ANALYZE_BACTERIAL_GROWTH_RATE.out.output
    versions = ANALYZE_BACTERIAL_GROWTH_RATE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_BACTERIAL_GROWTH_RATE_WORKFLOW(ch_input)

    ANALYZE_BACTERIAL_GROWTH_RATE_WORKFLOW.out.output.view { "Output: $it" }
}
