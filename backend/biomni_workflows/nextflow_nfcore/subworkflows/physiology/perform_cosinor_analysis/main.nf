#!/usr/bin/env nextflow
/*
 * physiology/perform_cosinor_analysis
 * Performs cosinor analysis on physiological time series data to characterize circadian rhythms.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: 48-hour circadian rhythm data (temperature measurements every 2 hours)
params.time_data = '[0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48]'
params.physiological_data = '[36.5, 36.3, 36.1, 36.0, 36.2, 36.5, 36.8, 37.1, 37.3, 37.4, 37.2, 36.9, 36.5, 36.3, 36.1, 36.0, 36.2, 36.5, 36.8, 37.1, 37.3, 37.4, 37.2, 36.9, 36.5]'
params.period = '24.0'

process PERFORM_COSINOR_ANALYSIS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("perform_cosinor_analysis_results.json"), emit: results
    tuple val(meta), path("perform_cosinor_analysis_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TIME_DATA="${params.time_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PHYSIOLOGICAL_DATA="${params.physiological_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PERIOD="${params.period?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def perform_cosinor_analysis(time_data, physiological_data, period=24.0):
    '''Performs cosinor analysis on physiological time series data to characterize circadian rhythms.

    Parameters
    ----------
    time_data : array-like
        Time points of the measurements in hours
    physiological_data : array-like
        Physiological measurements corresponding to each time point
    period : float, default=24.0
        Period of the rhythm in hours, default is 24 hours for circadian rhythms

    Returns
    -------
    str
        A research log summarizing the cosinor analysis process and results

    '''
    from datetime import datetime

    import numpy as np
    from scipy import optimize

    # Define the cosinor model function
    def cosinor_model(t, mesor, amplitude, acrophase):
        '''Cosine function with baseline (mesor), amplitude, and phase shift.'''
        return mesor + amplitude * np.cos((2 * np.pi * t / period) - acrophase)

    # Initial parameter guesses
    mesor_guess = np.mean(physiological_data)
    amplitude_guess = (np.max(physiological_data) - np.min(physiological_data)) / 2
    acrophase_guess = 0  # Starting with zero phase shift

    # Fit the cosinor model to the data
    try:
        params, params_covariance = optimize.curve_fit(
            cosinor_model,
            time_data,
            physiological_data,
            p0=[mesor_guess, amplitude_guess, acrophase_guess],
        )

        # Extract parameters
        mesor, amplitude, acrophase = params

        # Convert acrophase to hours (peak time)
        acrophase_hours = (acrophase * period) / (2 * np.pi)
        acrophase_hours = acrophase_hours % period  # Ensure it's within the period

        # Calculate model fit
        predicted_values = cosinor_model(time_data, mesor, amplitude, acrophase)

        # Calculate goodness of fit metrics
        residuals = physiological_data - predicted_values
        ss_total = np.sum((physiological_data - np.mean(physiological_data)) ** 2)
        ss_residual = np.sum(residuals**2)
        r_squared = 1 - (ss_residual / ss_total)

        # Calculate standard errors from covariance matrix
        std_errors = np.sqrt(np.diag(params_covariance))

        # Create results summary
        results = {
            "Mesor": f"{mesor:.4f} ± {std_errors[0]:.4f}",
            "Amplitude": f"{amplitude:.4f} ± {std_errors[1]:.4f}",
            "Acrophase (radians)": f"{acrophase:.4f} ± {std_errors[2]:.4f}",
            "Peak Time (hours)": f"{acrophase_hours:.2f}",
            "R-squared": f"{r_squared:.4f}",
        }

        # Create a research log
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log = f"Cosinor Analysis Research Log - {timestamp}\\n"
        log += "=" * 50 + "\\n\\n"
        log += "ANALYSIS SUMMARY:\\n"
        log += f"Analyzed {len(time_data)} data points over {max(time_data) - min(time_data):.1f} hours\\n"
        log += f"Fitted a cosine curve with period = {period} hours\\n\\n"

        log += "CIRCADIAN RHYTHM PARAMETERS:\\n"
        for param, value in results.items():
            log += f"- {param}: {value}\\n"

        log += "\\nINTERPRETATION:\\n"
        log += f"- The rhythm-adjusted mean (mesor) is {mesor:.4f}\\n"
        log += f"- The rhythm shows a peak-to-trough variation of {2 * amplitude:.4f}\\n"
        log += f"- The peak of the rhythm occurs at {acrophase_hours:.2f} hours\\n"
        log += f"- The model explains {r_squared * 100:.1f}% of the variation in the data\\n"

        if r_squared < 0.3:
            log += "\\nNOTE: The low R-squared suggests a weak circadian pattern in this data.\\n"

        return log

    except Exception as e:
        return f"Error in cosinor analysis: {str(e)}"

# Execute the function
try:
    result = perform_cosinor_analysis(
        time_data=auto_convert(os.environ.get("PARAM_TIME_DATA", "")),
        physiological_data=auto_convert(os.environ.get("PARAM_PHYSIOLOGICAL_DATA", "")),
        period=auto_convert(os.environ.get("PARAM_PERIOD", "24.0")),
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
    "function": "perform_cosinor_analysis",
    "domain": "physiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("perform_cosinor_analysis_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("perform_cosinor_analysis_output.txt", "w") as f:
    f.write("Biomni: Perform Cosinor Analysis" + NL)
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
        biomni_function: "perform_cosinor_analysis"
    END_VERSIONS
    """
}

workflow PERFORM_COSINOR_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PERFORM_COSINOR_ANALYSIS(ch_input)

    emit:
    results = PERFORM_COSINOR_ANALYSIS.out.results
    output = PERFORM_COSINOR_ANALYSIS.out.output
    versions = PERFORM_COSINOR_ANALYSIS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PERFORM_COSINOR_ANALYSIS_WORKFLOW(ch_input)

    PERFORM_COSINOR_ANALYSIS_WORKFLOW.out.output.view { "Output: $it" }
}
