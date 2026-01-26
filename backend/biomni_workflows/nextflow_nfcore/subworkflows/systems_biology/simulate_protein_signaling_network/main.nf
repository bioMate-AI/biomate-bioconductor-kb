#!/usr/bin/env nextflow
/*
 * systems_biology/simulate_protein_signaling_network
 * Simulate protein signaling network dynamics using ODE-based logic modeling with normalized Hill functions.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.network_structure = null
params.reaction_params = null
params.species_params = null
params.simulation_time = '100'
params.time_points = '1000'

process SIMULATE_PROTEIN_SIGNALING_NETWORK {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("simulate_protein_signaling_network_results.json"), emit: results
    tuple val(meta), path("simulate_protein_signaling_network_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_NETWORK_STRUCTURE="${params.network_structure?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_REACTION_PARAMS="${params.reaction_params?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SPECIES_PARAMS="${params.species_params?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SIMULATION_TIME="${params.simulation_time?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TIME_POINTS="${params.time_points?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def simulate_protein_signaling_network(
    network_structure, reaction_params, species_params, simulation_time=100, time_points=1000
):
    '''
    Simulate protein signaling network dynamics using ODE-based logic modeling with normalized Hill functions.

    Parameters:
    -----------
    network_structure : dict
        Dictionary defining the network topology. Each key is a target protein and its value is a list of tuples
        (regulator, regulation_type) where regulation_type is 1 for activation and -1 for inhibition.

    reaction_params : dict
        Dictionary of reaction parameters. Keys are tuples (regulator, target) and values are dictionaries
        with keys 'W' (weight), 'n' (Hill coefficient), and 'EC50' (half-maximal effective concentration).

    species_params : dict
        Dictionary of species parameters. Keys are protein names and values are dictionaries
        with keys 'tau' (time constant), 'y0' (initial concentration), and 'ymax' (maximum concentration).

    simulation_time : float, optional
        Total simulation time in arbitrary time units. Default is 100.

    time_points : int, optional
        Number of time points for the simulation. Default is 1000.

    Returns:
    --------
    str
        Research log summarizing the simulation process and results.
    '''
    import csv

    import numpy as np
    from scipy.integrate import solve_ivp

    # Extract all unique protein species
    all_proteins = set(network_structure.keys())
    for _target, regulators in network_structure.items():
        for regulator, _ in regulators:
            all_proteins.add(regulator)

    # Create ordered list of proteins for indexing
    proteins = sorted(all_proteins)
    protein_indices = {protein: i for i, protein in enumerate(proteins)}

    # Define the normalized Hill function
    def hill_function(x, n, ec50):
        return x**n / (x**n + ec50**n)

    # Define the ODE system
    def ode_system(t, y):
        dydt = np.zeros_like(y)

        for target, regulators in network_structure.items():
            target_idx = protein_indices[target]
            target_params = species_params[target]

            # Calculate regulation term for each regulator
            regulation_terms = []
            for regulator, reg_type in regulators:
                regulator_idx = protein_indices[regulator]
                params = reaction_params.get((regulator, target), {})

                if not params:
                    continue

                x = y[regulator_idx]
                n = params["n"]
                ec50 = params["EC50"]
                weight = params["W"]

                # Apply Hill function based on regulation type
                if reg_type == 1:  # Activation
                    term = weight * hill_function(x, n, ec50)
                else:  # Inhibition
                    term = weight * (1 - hill_function(x, n, ec50))

                regulation_terms.append(term)

            # Combine regulation terms (if any)
            if regulation_terms:
                # Simple summation of regulation terms
                regulation = sum(regulation_terms) / len(regulation_terms)

                # Ensure regulation stays within [0, 1]
                regulation = max(0, min(1, regulation))

                # Calculate rate of change
                tau = target_params["tau"]
                ymax = target_params["ymax"]
                dydt[target_idx] = (1 / tau) * (regulation * ymax - y[target_idx])

        return dydt

    # Set up initial conditions
    y0 = np.zeros(len(proteins))
    for protein, params in species_params.items():
        if protein in protein_indices:
            y0[protein_indices[protein]] = params["y0"]

    # Set up time points
    t_span = (0, simulation_time)
    t_eval = np.linspace(0, simulation_time, time_points)

    # Solve the ODE system
    solution = solve_ivp(ode_system, t_span, y0, method="LSODA", t_eval=t_eval, rtol=1e-6, atol=1e-9)

    # Save results to CSV
    output_file = "protein_signaling_simulation_results.csv"
    with open(output_file, "w", newline="") as f:
        writer = csv.writer(f)
        # Write header
        header = ["Time"] + proteins
        writer.writerow(header)

        # Write data
        for i in range(len(solution.t)):
            row = [solution.t[i]] + list(solution.y[:, i])
            writer.writerow(row)

    # Generate research log
    log = "ODE-based Logic Modeling of Protein Signaling Networks\\n"
    log += "=============================================\\n\\n"
    log += f"Network structure: {len(network_structure)} target proteins, {len(proteins)} total proteins\\n"
    log += f"Simulation time: {simulation_time} time units\\n"
    log += f"Number of time points: {time_points}\\n\\n"

    log += "Simulation steps:\\n"
    log += "1. Initialized protein concentrations based on provided initial values\\n"
    log += "2. Set up ODE system using normalized Hill functions for protein interactions\\n"
    log += "3. Solved the ODE system using LSODA integration method\\n"
    log += "4. Saved time-series data for all protein concentrations\\n\\n"

    log += f"Results saved to: {output_file}\\n\\n"

    # Add summary statistics
    log += "Summary of final protein concentrations:\\n"
    for i, protein in enumerate(proteins):
        final_conc = solution.y[i, -1]
        log += f"- {protein}: {final_conc:.4f}\\n"

    return log

# Execute the function
try:
    result = simulate_protein_signaling_network(
        network_structure=auto_convert(os.environ.get("PARAM_NETWORK_STRUCTURE", "")),
        reaction_params=auto_convert(os.environ.get("PARAM_REACTION_PARAMS", "")),
        species_params=auto_convert(os.environ.get("PARAM_SPECIES_PARAMS", "")),
        simulation_time=auto_convert(os.environ.get("PARAM_SIMULATION_TIME", "100")),
        time_points=auto_convert(os.environ.get("PARAM_TIME_POINTS", "1000")),
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
    "function": "simulate_protein_signaling_network",
    "domain": "systems_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("simulate_protein_signaling_network_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("simulate_protein_signaling_network_output.txt", "w") as f:
    f.write("Biomni: Simulate Protein Signaling Network" + NL)
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
        biomni_function: "simulate_protein_signaling_network"
    END_VERSIONS
    """
}

workflow SIMULATE_PROTEIN_SIGNALING_NETWORK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SIMULATE_PROTEIN_SIGNALING_NETWORK(ch_input)

    emit:
    results = SIMULATE_PROTEIN_SIGNALING_NETWORK.out.results
    output = SIMULATE_PROTEIN_SIGNALING_NETWORK.out.output
    versions = SIMULATE_PROTEIN_SIGNALING_NETWORK.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SIMULATE_PROTEIN_SIGNALING_NETWORK_WORKFLOW(ch_input)

    SIMULATE_PROTEIN_SIGNALING_NETWORK_WORKFLOW.out.output.view { "Output: $it" }
}
