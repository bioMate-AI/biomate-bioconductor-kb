#!/usr/bin/env nextflow
/*
 * microbiology/simulate_generalized_lotka_volterra_dynamics
 * Simulate microbial community dynamics using the Generalized Lotka-Volterra (gLV) model.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: 3-species microbial community with competition/mutualism
params.initial_abundances = '[0.1, 0.2, 0.15]'
params.growth_rates = '[0.5, 0.4, 0.45]'
// Interaction matrix: diagonal=self-limitation, off-diagonal=species interactions
params.interaction_matrix = '[[-0.1, -0.02, 0.01], [-0.01, -0.1, -0.03], [0.02, -0.01, -0.1]]'
params.time_points = '[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 20, 25, 30, 40, 50]'
params.output_file = 'glv_simulation_results.csv'

process SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("simulate_generalized_lotka_volterra_dynamics_results.json"), emit: results
    tuple val(meta), path("simulate_generalized_lotka_volterra_dynamics_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_INITIAL_ABUNDANCES="${params.initial_abundances?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GROWTH_RATES="${params.growth_rates?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_INTERACTION_MATRIX="${params.interaction_matrix?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TIME_POINTS="${params.time_points?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def simulate_generalized_lotka_volterra_dynamics(
    initial_abundances,
    growth_rates,
    interaction_matrix,
    time_points,
    output_file="glv_simulation_results.csv",
):
    '''Simulate microbial community dynamics using the Generalized Lotka-Volterra (gLV) model.

    Parameters
    ----------
    initial_abundances : numpy.ndarray
        Initial abundances of each microbial species (1D array)
    growth_rates : numpy.ndarray
        Intrinsic growth rates for each microbial species (1D array)
    interaction_matrix : numpy.ndarray
        Matrix of interaction coefficients where A[i,j] represents the effect of species j on species i (2D array)
    time_points : numpy.ndarray
        Time points at which to evaluate the model
    output_file : str, optional
        Filename to save the simulation results (default: "glv_simulation_results.csv")

    Returns
    -------
    str
        Research log summarizing the simulation process and results

    '''
    import numpy as np
    import pandas as pd
    from scipy.integrate import odeint

    # Convert inputs to numpy arrays if they aren't already
    initial_abundances = np.asarray(initial_abundances)
    growth_rates = np.asarray(growth_rates)
    interaction_matrix = np.asarray(interaction_matrix)
    time_points = np.asarray(time_points)

    # Check input dimensions
    n_species = len(initial_abundances)
    if len(growth_rates) != n_species or interaction_matrix.shape != (
        n_species,
        n_species,
    ):
        raise ValueError(
            "Dimensions mismatch: growth_rates and interaction_matrix must match initial_abundances dimensions"
        )

    # Define the gLV differential equations
    def glv_equations(abundances, t, growth_rates, interaction_matrix):
        # Calculate growth and interaction terms for each species
        # dx_i/dt = r_i * x_i + x_i * sum(A_ij * x_j)
        dx_dt = abundances * (growth_rates + np.dot(interaction_matrix, abundances))
        return dx_dt

    # Integrate the ODE system
    simulation_results = odeint(
        glv_equations,
        initial_abundances,
        time_points,
        args=(growth_rates, interaction_matrix),
    )

    # Create a DataFrame with the results
    columns = [f"Species_{i + 1}" for i in range(n_species)]
    results_df = pd.DataFrame(simulation_results, columns=columns)
    results_df.insert(0, "Time", time_points)

    # Save results to CSV
    results_df.to_csv(output_file, index=False)

    # Generate summary statistics
    final_abundances = simulation_results[-1]
    dominant_species = np.argmax(final_abundances) + 1
    extinct_species = sum(final_abundances < 1e-6)

    # Create research log
    log = f'''
Generalized Lotka-Volterra (gLV) Model Simulation Results:
------------------------------------------------------
Number of microbial species: {n_species}
Simulation time range: {time_points[0]} to {time_points[-1]}
Number of time points: {len(time_points)}

Summary of dynamics:
- Initial total abundance: {np.sum(initial_abundances):.4f}
- Final total abundance: {np.sum(final_abundances):.4f}
- Dominant species at end of simulation: Species_{dominant_species} (abundance: {final_abundances[dominant_species - 1]:.4f})
- Number of species with near-zero abundance (< 1e-6): {extinct_species}

Simulation results have been saved to: {output_file}
'''

    return log

# Execute the function
try:
    result = simulate_generalized_lotka_volterra_dynamics(
        initial_abundances=auto_convert(os.environ.get("PARAM_INITIAL_ABUNDANCES", "")),
        growth_rates=auto_convert(os.environ.get("PARAM_GROWTH_RATES", "")),
        interaction_matrix=auto_convert(os.environ.get("PARAM_INTERACTION_MATRIX", "")),
        time_points=auto_convert(os.environ.get("PARAM_TIME_POINTS", "")),
        output_file=auto_convert(os.environ.get("PARAM_OUTPUT_FILE", "glv_simulation_results.csv")),
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
    "function": "simulate_generalized_lotka_volterra_dynamics",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("simulate_generalized_lotka_volterra_dynamics_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("simulate_generalized_lotka_volterra_dynamics_output.txt", "w") as f:
    f.write("Biomni: Simulate Generalized Lotka Volterra Dynamics" + NL)
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
        biomni_function: "simulate_generalized_lotka_volterra_dynamics"
    END_VERSIONS
    """
}

workflow SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS(ch_input)

    emit:
    results = SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS.out.results
    output = SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS.out.output
    versions = SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS_WORKFLOW(ch_input)

    SIMULATE_GENERALIZED_LOTKA_VOLTERRA_DYNAMICS_WORKFLOW.out.output.view { "Output: $it" }
}
