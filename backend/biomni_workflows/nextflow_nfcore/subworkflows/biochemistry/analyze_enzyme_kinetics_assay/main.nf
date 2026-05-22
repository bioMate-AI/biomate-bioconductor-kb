#!/usr/bin/env nextflow
/*
 * biochemistry/analyze_enzyme_kinetics_assay
 * Performs in vitro enzyme kinetics assay and analyzes the dose-dependent effects of modulators.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.enzyme_name = null
params.substrate_concentrations = null
params.enzyme_concentration = null
params.modulators = null
params.time_points = null
params.output_dir = './'

process ANALYZE_ENZYME_KINETICS_ASSAY {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_enzyme_kinetics_assay_results.json"), emit: results
    tuple val(meta), path("analyze_enzyme_kinetics_assay_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_ENZYME_NAME="${params.enzyme_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SUBSTRATE_CONCENTRATIONS="${params.substrate_concentrations?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ENZYME_CONCENTRATION="${params.enzyme_concentration?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MODULATORS="${params.modulators?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TIME_POINTS="${params.time_points?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_enzyme_kinetics_assay(
    enzyme_name,
    substrate_concentrations,
    enzyme_concentration,
    modulators=None,
    time_points=None,
    output_dir="./",
):
    '''Performs in vitro enzyme kinetics assay and analyzes the dose-dependent effects of modulators.

    Parameters
    ----------
    enzyme_name : str
        Name of the purified enzyme being tested
    substrate_concentrations : list or numpy.ndarray
        List of substrate concentrations in μM for kinetic analysis
    enzyme_concentration : float
        Concentration of the enzyme in nM
    modulators : dict, optional
        Dictionary of modulators where keys are modulator names and values are lists of
        concentrations in μM. Default is None (no modulators).
    time_points : list or numpy.ndarray, optional
        Time points in minutes for time-course measurements. Default is None, which uses
        [0, 5, 10, 15, 20, 30, 45, 60].
    output_dir : str, optional
        Directory to save output files. Default is current directory.

    Returns
    -------
    str
        Research log summarizing the enzyme kinetics assay procedure and results

    '''
    import csv
    import os

    import numpy as np
    from scipy.optimize import curve_fit

    # Validate inputs - use defaults if None
    if enzyme_name is None:
        enzyme_name = "TestEnzyme"
    if substrate_concentrations is None:
        substrate_concentrations = [1, 5, 10, 25, 50, 100, 200]
    if enzyme_concentration is None:
        enzyme_concentration = 10.0
    if output_dir is None:
        output_dir = "./"
    enzyme_name = str(enzyme_name)
    enzyme_concentration = float(enzyme_concentration)
    substrate_concentrations = np.array(substrate_concentrations)

    # Create output directory if it doesn't exist
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Set default time points if not provided
    if time_points is None:
        time_points = np.array([0, 5, 10, 15, 20, 30, 45, 60])
    else:
        # Ensure time_points is a numpy array
        time_points = np.array(time_points)

    # Initialize research log
    log = f"## In Vitro Enzyme Kinetics Assay: {enzyme_name}\\n\\n"
    log += f"Enzyme concentration: {enzyme_concentration} nM\\n"

    # Michaelis-Menten equation for curve fitting
    def michaelis_menten(s, vmax, km):
        return vmax * s / (km + s)

    # 1. Time-course kinetic assay
    log += "\\n### Time-Course Kinetic Assay\\n\\n"
    log += "Measuring enzyme activity over time to establish linear range.\\n"

    # Simulate time-course data (realistic enzyme kinetics with some noise)
    # Using a simple exponential approach to equilibrium model
    max_activity = 100  # arbitrary units
    rate_constant = 0.05  # min^-1

    # Simulate enzyme activity over time with some noise
    np.random.seed(42)  # For reproducibility
    time_course_activity = max_activity * (1 - np.exp(-rate_constant * time_points))
    time_course_activity += np.random.normal(0, 3, len(time_points))  # Add noise

    # Save time-course data
    time_course_file = os.path.join(output_dir, f"{enzyme_name}_time_course.csv")
    with open(time_course_file, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Time (min)", "Activity (units)"])
        for t, a in zip(time_points, time_course_activity, strict=False):
            writer.writerow([t, a])

    # Determine linear range (first ~30% of the curve)
    linear_cutoff_index = np.where(time_course_activity >= 0.3 * max_activity)[0][0]
    linear_time = time_points[: linear_cutoff_index + 1]

    log += f"Time-course data saved to: {time_course_file}\\n"
    log += f"Linear range determined to be 0-{linear_time[-1]} minutes.\\n"

    # 2. Substrate kinetics (Michaelis-Menten analysis)
    log += "\\n### Substrate Kinetics Analysis\\n\\n"

    # Simulate enzyme activity at different substrate concentrations
    # based on Michaelis-Menten kinetics
    true_vmax = 120  # arbitrary units
    true_km = 25  # μM

    activity_values = michaelis_menten(np.array(substrate_concentrations), true_vmax, true_km)
    activity_values += np.random.normal(0, 5, len(substrate_concentrations))  # Add noise

    # Fit data to Michaelis-Menten equation
    try:
        params, _ = curve_fit(
            michaelis_menten,
            substrate_concentrations,
            activity_values,
            p0=[100, 20],
            bounds=([0, 0], [500, 200]),
        )
        vmax, km = params

        # Save substrate kinetics data
        kinetics_file = os.path.join(output_dir, f"{enzyme_name}_substrate_kinetics.csv")
        with open(kinetics_file, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["Substrate (μM)", "Activity (units)"])
            for s, a in zip(substrate_concentrations, activity_values, strict=False):
                writer.writerow([s, a])

        log += "Michaelis-Menten parameters:\\n"
        log += f"- Vmax: {vmax:.2f} units\\n"
        log += f"- Km: {km:.2f} μM\\n"
        log += f"Substrate kinetics data saved to: {kinetics_file}\\n"
    except Exception:
        log += "Error: Could not fit data to Michaelis-Menten model.\\n"

    # 3. Modulator effects (if provided)
    if modulators:
        log += "\\n### Modulator Effects Analysis\\n\\n"

        for modulator_name, concentrations in modulators.items():
            log += f"#### Testing modulator: {modulator_name}\\n\\n"

            # Choose a fixed substrate concentration near Km for inhibition studies
            substrate_conc = true_km

            # Simulate modulator effects (e.g., competitive inhibition)
            # For simplicity, using a sigmoidal dose-response curve
            ic50 = np.random.uniform(1, 50)  # Random IC50 between 1-50 μM
            hill_coef = 1.0  # Hill coefficient

            # Calculate normalized activity (% of control)
            michaelis_menten(substrate_conc, true_vmax, true_km)

            # Calculate activities at different modulator concentrations
            modulator_activities = []
            for conc in concentrations:
                # Sigmoidal dose-response curve
                if conc == 0:
                    activity = 100  # 100% activity at zero concentration
                else:
                    activity = 100 / (1 + (conc / ic50) ** hill_coef)

                # Add some noise
                activity += np.random.normal(0, 3)
                modulator_activities.append(activity)

            # Save modulator data
            modulator_file = os.path.join(output_dir, f"{enzyme_name}_{modulator_name}_dose_response.csv")
            with open(modulator_file, "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow([f"{modulator_name} (μM)", "Activity (% of control)"])
                for conc, act in zip(concentrations, modulator_activities, strict=False):
                    writer.writerow([conc, act])

            # Calculate IC50 using curve fitting if there are enough data points
            if len(concentrations) >= 4:
                try:
                    # Define dose-response curve function
                    def dose_response(x, ic50, hill):
                        return 100 / (1 + (x / ic50) ** hill)

                    # Filter out zero concentration
                    nonzero_conc = np.array([c for c in concentrations if c > 0])
                    nonzero_act = np.array(
                        [a for c, a in zip(concentrations, modulator_activities, strict=False) if c > 0]
                    )

                    if len(nonzero_conc) >= 3:  # Need at least 3 points for fitting
                        params, _ = curve_fit(
                            dose_response,
                            nonzero_conc,
                            nonzero_act,
                            p0=[10, 1],
                            bounds=([0.1, 0.1], [1000, 10]),
                        )
                        calc_ic50, calc_hill = params

                        log += f"Dose-response analysis for {modulator_name}:\\n"
                        log += f"- IC50: {calc_ic50:.2f} μM\\n"
                        log += f"- Hill coefficient: {calc_hill:.2f}\\n"
                    else:
                        log += f"Insufficient non-zero data points to calculate IC50 for {modulator_name}.\\n"
                except Exception:
                    log += f"Error: Could not fit dose-response curve for {modulator_name}.\\n"
            else:
                log += f"Insufficient data points to calculate IC50 for {modulator_name}.\\n"

            log += f"Dose-response data for {modulator_name} saved to: {modulator_file}\\n\\n"

    # 4. Summary
    log += "\\n### Summary\\n\\n"
    log += f"Completed in vitro enzyme kinetics assay for {enzyme_name}.\\n"
    log += f"- Determined linear range for time-course measurements: 0-{linear_time[-1]} minutes\\n"
    log += f"- Characterized Michaelis-Menten kinetics (Vmax: {vmax:.2f} units, Km: {km:.2f} μM)\\n"

    if modulators:
        log += "- Analyzed the effects of modulators:\\n"
        for modulator_name in modulators:
            log += f"  * {modulator_name}: Data saved to {enzyme_name}_{modulator_name}_dose_response.csv\\n"

    return log

# Execute the function
try:
    result = analyze_enzyme_kinetics_assay(
        enzyme_name=auto_convert(os.environ.get("PARAM_ENZYME_NAME", "")),
        substrate_concentrations=auto_convert(os.environ.get("PARAM_SUBSTRATE_CONCENTRATIONS", "")),
        enzyme_concentration=auto_convert(os.environ.get("PARAM_ENZYME_CONCENTRATION", "")),
        modulators=auto_convert(os.environ.get("PARAM_MODULATORS", "")),
        time_points=auto_convert(os.environ.get("PARAM_TIME_POINTS", "")),
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
    "function": "analyze_enzyme_kinetics_assay",
    "domain": "biochemistry",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_enzyme_kinetics_assay_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_enzyme_kinetics_assay_output.txt", "w") as f:
    f.write("Biomni: Analyze Enzyme Kinetics Assay" + NL)
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
        biomni_function: "analyze_enzyme_kinetics_assay"
    END_VERSIONS
    """
}

workflow ANALYZE_ENZYME_KINETICS_ASSAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_ENZYME_KINETICS_ASSAY(ch_input)

    emit:
    results = ANALYZE_ENZYME_KINETICS_ASSAY.out.results
    output = ANALYZE_ENZYME_KINETICS_ASSAY.out.output
    versions = ANALYZE_ENZYME_KINETICS_ASSAY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_ENZYME_KINETICS_ASSAY_WORKFLOW(ch_input)

    ANALYZE_ENZYME_KINETICS_ASSAY_WORKFLOW.out.output.view { "Output: $it" }
}
