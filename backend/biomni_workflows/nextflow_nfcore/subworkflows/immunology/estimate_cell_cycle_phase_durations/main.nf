#!/usr/bin/env nextflow
/*
 * immunology/estimate_cell_cycle_phase_durations
 * Estimate cell cycle phase durations using dual-nucleoside pulse labeling data and mathematical modeling.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: dual-nucleoside pulse labeling experiment over 48 hours
params.flow_cytometry_data = '{"time_points": [0, 4, 8, 12, 24, 36, 48], "edu_positive": [5.0, 15.0, 25.0, 30.0, 35.0, 32.0, 28.0], "brdu_positive": [0.0, 8.0, 18.0, 28.0, 38.0, 42.0, 40.0], "double_positive": [0.0, 5.0, 12.0, 20.0, 25.0, 22.0, 18.0]}'
// Default initial estimates for typical mammalian cells
params.initial_estimates = '{"g1_duration": 10.0, "s_duration": 8.0, "g2m_duration": 4.0, "death_rate": 0.01}'

process ESTIMATE_CELL_CYCLE_PHASE_DURATIONS {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("estimate_cell_cycle_phase_durations_results.json"), emit: results
    tuple val(meta), path("estimate_cell_cycle_phase_durations_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_FLOW_CYTOMETRY_DATA="${params.flow_cytometry_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_INITIAL_ESTIMATES="${params.initial_estimates?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def estimate_cell_cycle_phase_durations(flow_cytometry_data, initial_estimates):
    '''
    Estimate cell cycle phase durations using dual-nucleoside pulse labeling data and mathematical modeling.

    Parameters
    ----------
    flow_cytometry_data : dict
        Dictionary containing experimental data from flow cytometry with EdU and BrdU labeling.
        Expected format::

            {
                'time_points': list of time points (hours),
                'edu_positive': list of percentages of EdU+ cells at each time point,
                'brdu_positive': list of percentages of BrdU+ cells at each time point,
                'double_positive': list of percentages of EdU+BrdU+ cells at each time point
            }

    initial_estimates : dict
        Initial estimates for cell cycle phase durations and death rates.
        Expected format::

            {
                'g1_duration': float (hours),
                's_duration': float (hours),
                'g2m_duration': float (hours),
                'death_rate': float (fraction per hour)
            }

    Returns
    -------
    str
        Research log summarizing the cell cycle phase duration estimation process and results.
    '''

    import time

    import numpy as np
    from scipy import optimize

    # Start research log
    log = "# Cell Cycle Phase Duration Estimation Research Log\\n\\n"
    log += f"Analysis started at: {time.strftime('%Y-%m-%d %H:%M:%S')}\\n\\n"

    # Log input data summary
    log += "## Input Data Summary\\n"
    log += f"- Number of time points: {len(flow_cytometry_data['time_points'])}\\n"
    log += (
        f"- Time range: {min(flow_cytometry_data['time_points'])} to {max(flow_cytometry_data['time_points'])} hours\\n"
    )
    log += f"- Initial estimates: G1={initial_estimates['g1_duration']}h, S={initial_estimates['s_duration']}h, "
    log += f"G2/M={initial_estimates['g2m_duration']}h, Death rate={initial_estimates['death_rate']}\\n\\n"

    # Define the objective function for optimization
    def objective_function(params):
        g1_duration, s_duration, g2m_duration, death_rate = params

        # Simple cell cycle model simulation
        simulated_results = simulate_cell_population(
            flow_cytometry_data["time_points"],
            g1_duration,
            s_duration,
            g2m_duration,
            death_rate,
        )

        # Calculate error between simulated and experimental data
        edu_error = np.sum(
            (np.array(simulated_results["edu_positive"]) - np.array(flow_cytometry_data["edu_positive"])) ** 2
        )
        brdu_error = np.sum(
            (np.array(simulated_results["brdu_positive"]) - np.array(flow_cytometry_data["brdu_positive"])) ** 2
        )
        double_error = np.sum(
            (np.array(simulated_results["double_positive"]) - np.array(flow_cytometry_data["double_positive"])) ** 2
        )

        # Total error
        total_error = edu_error + brdu_error + double_error
        return total_error

    # Function to simulate cell population dynamics
    def simulate_cell_population(time_points, g1_duration, s_duration, g2m_duration, death_rate):
        # Simple simulation of cell populations based on ODE model
        # This is a simplified version - a real implementation would use differential equations

        # Initialize results
        edu_positive = []
        brdu_positive = []
        double_positive = []

        total_cycle_time = g1_duration + s_duration + g2m_duration

        for t in time_points:
            # Simplified model for demonstration
            # In a real implementation, this would involve solving ODEs

            # Calculate fractions of cells in each phase
            s_fraction = s_duration / total_cycle_time
            g2m_duration / total_cycle_time

            # Simple model for EdU and BrdU incorporation
            edu_pos = s_fraction * np.exp(-death_rate * t)
            brdu_pos = s_fraction * (1 - np.exp(-t / s_duration))
            double_pos = s_fraction * np.exp(-death_rate * t) * (1 - np.exp(-t / s_duration))

            # Adjust values to be realistic
            edu_pos = min(edu_pos, 1.0) * 100  # Convert to percentage
            brdu_pos = min(brdu_pos, 1.0) * 100
            double_pos = min(double_pos, 1.0) * 100

            edu_positive.append(edu_pos)
            brdu_positive.append(brdu_pos)
            double_positive.append(double_pos)

        return {
            "edu_positive": edu_positive,
            "brdu_positive": brdu_positive,
            "double_positive": double_positive,
        }

    # Set up initial parameter values and bounds for optimization
    initial_params = [
        initial_estimates["g1_duration"],
        initial_estimates["s_duration"],
        initial_estimates["g2m_duration"],
        initial_estimates["death_rate"],
    ]

    # Parameter bounds (all positive values)
    bounds = [(0.1, 50.0), (0.1, 30.0), (0.1, 20.0), (0.0, 1.0)]

    log += "## Optimization Process\\n"
    log += "Starting parameter optimization using SciPy's L-BFGS-B algorithm...\\n\\n"

    # Run optimization
    optimization_start = time.time()
    result = optimize.minimize(objective_function, initial_params, method="L-BFGS-B", bounds=bounds)
    optimization_time = time.time() - optimization_start

    # Extract optimized parameters
    optimized_g1, optimized_s, optimized_g2m, optimized_death = result.x

    # Calculate final error
    final_error = result.fun

    # Log optimization results
    log += "## Optimization Results\\n"
    log += f"- Optimization completed in {optimization_time:.2f} seconds\\n"
    log += f"- Optimization success: {result.success}\\n"
    log += f"- Final error value: {final_error:.4f}\\n\\n"

    log += "## Estimated Cell Cycle Phase Durations\\n"
    log += f"- G1 phase: {optimized_g1:.2f} hours\\n"
    log += f"- S phase: {optimized_s:.2f} hours\\n"
    log += f"- G2/M phase: {optimized_g2m:.2f} hours\\n"
    log += f"- Total cell cycle time: {optimized_g1 + optimized_s + optimized_g2m:.2f} hours\\n"
    log += f"- Cell death rate: {optimized_death:.4f} per hour\\n\\n"

    # Compare with initial estimates
    log += "## Comparison with Initial Estimates\\n"
    log += f"- G1 phase: {optimized_g1:.2f}h (initial: {initial_estimates['g1_duration']}h, "
    log += (
        f"change: {(optimized_g1 - initial_estimates['g1_duration']) / initial_estimates['g1_duration'] * 100:.1f}%)\\n"
    )

    log += f"- S phase: {optimized_s:.2f}h (initial: {initial_estimates['s_duration']}h, "
    log += f"change: {(optimized_s - initial_estimates['s_duration']) / initial_estimates['s_duration'] * 100:.1f}%)\\n"

    log += f"- G2/M phase: {optimized_g2m:.2f}h (initial: {initial_estimates['g2m_duration']}h, "
    log += f"change: {(optimized_g2m - initial_estimates['g2m_duration']) / initial_estimates['g2m_duration'] * 100:.1f}%)\\n"

    log += f"- Death rate: {optimized_death:.4f} (initial: {initial_estimates['death_rate']}, "
    log += f"change: {(optimized_death - initial_estimates['death_rate']) / (initial_estimates['death_rate'] if initial_estimates['death_rate'] > 0 else 1) * 100:.1f}%)\\n\\n"

    # Final summary
    log += "## Conclusion\\n"
    log += "The mathematical modeling and parameter optimization has estimated the cell cycle phase durations "
    log += "based on the provided dual-nucleoside pulse labeling data. "
    log += "These estimates provide insight into the proliferation dynamics of the studied cell population.\\n\\n"

    log += f"Analysis completed at: {time.strftime('%Y-%m-%d %H:%M:%S')}\\n"

    return log

# Execute the function
try:
    result = estimate_cell_cycle_phase_durations(
        flow_cytometry_data=auto_convert(os.environ.get("PARAM_FLOW_CYTOMETRY_DATA", "")),
        initial_estimates=auto_convert(os.environ.get("PARAM_INITIAL_ESTIMATES", "")),
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
    "function": "estimate_cell_cycle_phase_durations",
    "domain": "immunology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("estimate_cell_cycle_phase_durations_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("estimate_cell_cycle_phase_durations_output.txt", "w") as f:
    f.write("Biomni: Estimate Cell Cycle Phase Durations" + NL)
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
        biomni_function: "estimate_cell_cycle_phase_durations"
    END_VERSIONS
    """
}

workflow ESTIMATE_CELL_CYCLE_PHASE_DURATIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ESTIMATE_CELL_CYCLE_PHASE_DURATIONS(ch_input)

    emit:
    results = ESTIMATE_CELL_CYCLE_PHASE_DURATIONS.out.results
    output = ESTIMATE_CELL_CYCLE_PHASE_DURATIONS.out.output
    versions = ESTIMATE_CELL_CYCLE_PHASE_DURATIONS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ESTIMATE_CELL_CYCLE_PHASE_DURATIONS_WORKFLOW(ch_input)

    ESTIMATE_CELL_CYCLE_PHASE_DURATIONS_WORKFLOW.out.output.view { "Output: $it" }
}
