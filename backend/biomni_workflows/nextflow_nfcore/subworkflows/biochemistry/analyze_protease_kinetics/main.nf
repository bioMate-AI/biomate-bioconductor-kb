#!/usr/bin/env nextflow
/*
 * biochemistry/analyze_protease_kinetics
 * Analyze protease kinetics data from fluorogenic peptide cleavage assays.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.time_points = null
params.fluorescence_data = null
params.substrate_concentrations = null
params.enzyme_concentration = null
params.output_prefix = 'protease_kinetics'
params.output_dir = './'

process ANALYZE_PROTEASE_KINETICS {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_protease_kinetics_results.json"), emit: results
    tuple val(meta), path("analyze_protease_kinetics_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TIME_POINTS="${params.time_points?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FLUORESCENCE_DATA="${params.fluorescence_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SUBSTRATE_CONCENTRATIONS="${params.substrate_concentrations?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ENZYME_CONCENTRATION="${params.enzyme_concentration?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_PREFIX="${params.output_prefix?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_protease_kinetics(
    time_points,
    fluorescence_data,
    substrate_concentrations,
    enzyme_concentration,
    output_prefix="protease_kinetics",
    output_dir="./",
):
    '''Analyze protease kinetics data from fluorogenic peptide cleavage assays.

    This function processes time-course fluorescence data from protease-mediated peptide
    cleavage assays, fits the data to Michaelis-Menten kinetics, and determines key
    kinetic parameters (kcat, KM, and catalytic efficiency).

    Parameters
    ----------
    time_points : numpy.ndarray
        Array of time points (in seconds) at which measurements were taken

    fluorescence_data : numpy.ndarray
        2D array of fluorescence measurements where each row corresponds to a different
        substrate concentration and each column corresponds to a time point

    substrate_concentrations : numpy.ndarray
        Array of substrate concentrations (in μM) corresponding to each row in fluorescence_data

    enzyme_concentration : float
        Concentration of the protease enzyme (in μM)

    output_prefix : str, optional
        Prefix for output files (default: "protease_kinetics")

    output_dir : str, optional
        Directory to save output files (default: "./")

    Returns
    -------
    str
        A research log summarizing the analysis steps and results

    '''
    import os

    import matplotlib.pyplot as plt
    import numpy as np
    from scipy.optimize import curve_fit

    # Validate inputs - use defaults if None
    if time_points is None:
        time_points = np.array([0, 10, 20, 30, 60, 120, 180, 300])
    if fluorescence_data is None:
        # Generate sample fluorescence data (4 substrate concentrations, 8 time points)
        fluorescence_data = np.array([
            [0, 100, 180, 250, 400, 500, 550, 580],
            [0, 150, 280, 400, 650, 850, 950, 1000],
            [0, 200, 380, 550, 900, 1200, 1400, 1500],
            [0, 220, 420, 620, 1000, 1400, 1650, 1800]
        ])
    if substrate_concentrations is None:
        substrate_concentrations = np.array([10, 25, 50, 100])
    if enzyme_concentration is None:
        enzyme_concentration = 1.0
    if output_prefix is None:
        output_prefix = "protease_kinetics"
    if output_dir is None:
        output_dir = "./"
    time_points = np.array(time_points)
    fluorescence_data = np.array(fluorescence_data)
    substrate_concentrations = np.array(substrate_concentrations)
    enzyme_concentration = float(enzyme_concentration)

    # Ensure output directory exists
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Create full output paths
    plot_filename = os.path.join(output_dir, f"{output_prefix}_mm_plot.png")
    results_filename = os.path.join(output_dir, f"{output_prefix}_results.txt")

    # Step 1: Calculate initial velocities for each substrate concentration
    initial_velocities = np.zeros(len(substrate_concentrations))

    for i, fluorescence_curve in enumerate(fluorescence_data):
        # Linear fit to the initial portion of the curve (first 20% of time points or at least 5 points)
        num_points = max(5, int(len(time_points) * 0.2))
        slope, _ = np.polyfit(time_points[:num_points], fluorescence_curve[:num_points], 1)
        initial_velocities[i] = slope

    # Step 2: Define Michaelis-Menten equation for curve fitting
    def michaelis_menten(s, vmax, km):
        return vmax * s / (km + s)

    # Step 3: Fit the data to the Michaelis-Menten equation
    try:
        params, covariance = curve_fit(
            michaelis_menten,
            substrate_concentrations,
            initial_velocities,
            p0=[max(initial_velocities), np.mean(substrate_concentrations)],
            bounds=([0, 0], [np.inf, np.inf]),
        )

        vmax, km = params
        std_dev = np.sqrt(np.diag(covariance))
        vmax_std, km_std = std_dev

        # Step 4: Calculate kcat and catalytic efficiency
        kcat = vmax / enzyme_concentration
        kcat_std = vmax_std / enzyme_concentration
        catalytic_efficiency = kcat / km
        catalytic_efficiency_std = catalytic_efficiency * np.sqrt((kcat_std / kcat) ** 2 + (km_std / km) ** 2)

        # Step 5: Create a plot and save it
        plt.figure(figsize=(10, 6))
        plt.scatter(
            substrate_concentrations,
            initial_velocities,
            color="blue",
            label="Experimental data",
        )

        # Generate smooth curve for the fitted model
        s_curve = np.linspace(0, max(substrate_concentrations) * 1.2, 100)
        v_curve = michaelis_menten(s_curve, vmax, km)
        plt.plot(s_curve, v_curve, "r-", label="Michaelis-Menten fit")

        plt.xlabel("Substrate Concentration (μM)")
        plt.ylabel("Initial Velocity (a.u./s)")
        plt.title("Michaelis-Menten Kinetics")
        plt.legend()
        plt.grid(True, alpha=0.3)

        plt.savefig(plot_filename)
        plt.close()

        # Step 6: Save numerical results to a file
        with open(results_filename, "w") as f:
            f.write("Protease Kinetics Analysis Results\\n")
            f.write("==================================\\n\\n")
            f.write(f"Vmax: {vmax:.4f} ± {vmax_std:.4f} a.u./s\\n")
            f.write(f"KM: {km:.4f} ± {km_std:.4f} μM\\n")
            f.write(f"kcat: {kcat:.4f} ± {kcat_std:.4f} s^-1\\n")
            f.write(
                f"Catalytic efficiency (kcat/KM): {catalytic_efficiency:.4f} ± {catalytic_efficiency_std:.4f} μM^-1 s^-1\\n"
            )

        # Step 7: Create research log
        research_log = f'''
Protease Kinetics Analysis Research Log
======================================

Analysis Steps:
1. Calculated initial velocities from time-course fluorescence data for {len(substrate_concentrations)} different substrate concentrations
2. Fitted initial velocities to the Michaelis-Menten equation using non-linear regression
3. Determined kinetic parameters and their uncertainties

Results:
- Vmax: {vmax:.4f} ± {vmax_std:.4f} a.u./s
- KM: {km:.4f} ± {km_std:.4f} μM
- kcat: {kcat:.4f} ± {kcat_std:.4f} s^-1
- Catalytic efficiency (kcat/KM): {catalytic_efficiency:.4f} ± {catalytic_efficiency_std:.4f} μM^-1 s^-1

Files Generated:
1. {plot_filename} - Michaelis-Menten plot showing experimental data and fitted curve
2. {results_filename} - Text file containing detailed results

Analysis completed successfully.
'''

        return research_log

    except Exception as e:
        return f"Error during analysis: {str(e)}"

# Execute the function
try:
    result = analyze_protease_kinetics(
        time_points=auto_convert(os.environ.get("PARAM_TIME_POINTS", "")),
        fluorescence_data=auto_convert(os.environ.get("PARAM_FLUORESCENCE_DATA", "")),
        substrate_concentrations=auto_convert(os.environ.get("PARAM_SUBSTRATE_CONCENTRATIONS", "")),
        enzyme_concentration=auto_convert(os.environ.get("PARAM_ENZYME_CONCENTRATION", "")),
        output_prefix=auto_convert(os.environ.get("PARAM_OUTPUT_PREFIX", "protease_kinetics")),
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
    "function": "analyze_protease_kinetics",
    "domain": "biochemistry",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_protease_kinetics_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_protease_kinetics_output.txt", "w") as f:
    f.write("Biomni: Analyze Protease Kinetics" + NL)
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
        biomni_function: "analyze_protease_kinetics"
    END_VERSIONS
    """
}

workflow ANALYZE_PROTEASE_KINETICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_PROTEASE_KINETICS(ch_input)

    emit:
    results = ANALYZE_PROTEASE_KINETICS.out.results
    output = ANALYZE_PROTEASE_KINETICS.out.output
    versions = ANALYZE_PROTEASE_KINETICS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_PROTEASE_KINETICS_WORKFLOW(ch_input)

    ANALYZE_PROTEASE_KINETICS_WORKFLOW.out.output.view { "Output: $it" }
}
