#!/usr/bin/env nextflow
/*
 * microbiology/simulate_microbial_population_dynamics
 * Performs stochastic simulation of microbial population dynamics using the Gillespie algorithm.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.initial_populations = null
params.growth_rates = null
params.clearance_rates = null
params.carrying_capacities = null
params.max_time = '100'
params.num_simulations = '100'
params.time_points = '100'

process SIMULATE_MICROBIAL_POPULATION_DYNAMICS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("simulate_microbial_population_dynamics_results.json"), emit: results
    tuple val(meta), path("simulate_microbial_population_dynamics_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_INITIAL_POPULATIONS="${params.initial_populations?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GROWTH_RATES="${params.growth_rates?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CLEARANCE_RATES="${params.clearance_rates?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CARRYING_CAPACITIES="${params.carrying_capacities?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MAX_TIME="${params.max_time?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NUM_SIMULATIONS="${params.num_simulations?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def simulate_microbial_population_dynamics(
    initial_populations,
    growth_rates,
    clearance_rates,
    carrying_capacities,
    max_time=100,
    num_simulations=100,
    time_points=100,
):
    '''Performs stochastic simulation of microbial population dynamics using the Gillespie algorithm.

    Parameters
    ----------
    initial_populations : list of int
        Initial population sizes for each microbial species
    growth_rates : list of float
        Per capita growth rates for each species
    clearance_rates : list of float
        Per capita death/clearance rates for each species
    carrying_capacities : list of float
        Maximum sustainable population for each species
    max_time : float, optional
        Maximum simulation time (default: 100)
    num_simulations : int, optional
        Number of stochastic simulations to run (default: 100)
    time_points : int, optional
        Number of time points to record for trajectories (default: 100)

    Returns
    -------
    str
        Research log summarizing the simulation results, including extinction probabilities and timelines

    '''
    import numpy as np
    from scipy import stats

    # Ensure parameters have correct types
    if initial_populations is None:
        return "Error: initial_populations is required"
    if not isinstance(initial_populations, list):
        initial_populations = [initial_populations]
    if growth_rates is None:
        growth_rates = [0.5] * len(initial_populations)
    if not isinstance(growth_rates, list):
        growth_rates = [growth_rates]
    if clearance_rates is None:
        clearance_rates = [0.1] * len(initial_populations)
    if not isinstance(clearance_rates, list):
        clearance_rates = [clearance_rates]
    if carrying_capacities is None:
        carrying_capacities = [1000] * len(initial_populations)
    if not isinstance(carrying_capacities, list):
        carrying_capacities = [carrying_capacities]
    max_time = int(max_time) if max_time else 100
    num_simulations = int(num_simulations) if num_simulations else 100
    time_points = int(time_points) if time_points else 100

    # Validate inputs
    num_species = len(initial_populations)
    if not (len(growth_rates) == len(clearance_rates) == len(carrying_capacities) == num_species):
        return "Error: All input lists must have the same length (number of species)"

    # Initialize tracking variables
    extinction_counts = np.zeros(num_species)
    extinction_times = [[] for _ in range(num_species)]

    # Time points for trajectory recording
    time_grid = np.linspace(0, max_time, time_points)
    avg_trajectories = np.zeros((num_species, time_points))

    # Run multiple simulations
    for _sim in range(num_simulations):
        # Initialize population and time for this simulation
        population = np.array(initial_populations, dtype=float)
        time = 0.0

        # For recording trajectories at specific time points
        trajectory = np.zeros((num_species, time_points))
        next_time_point_idx = 0

        # Track which species have gone extinct in this simulation
        extinct_in_sim = [False] * num_species

        # Run simulation until max_time is reached or all populations are extinct
        while time < max_time and np.any(population > 0):
            # Record current state if we've reached the next time point
            while next_time_point_idx < time_points and time >= time_grid[next_time_point_idx]:
                trajectory[:, next_time_point_idx] = population
                next_time_point_idx += 1

            # Calculate event rates
            # Growth rates are adjusted for carrying capacity (logistic growth)
            adjusted_growth_rates = [
                growth_rates[i] * population[i] * (1 - population[i] / carrying_capacities[i])
                if population[i] > 0
                else 0
                for i in range(num_species)
            ]
            death_rates = [clearance_rates[i] * population[i] if population[i] > 0 else 0 for i in range(num_species)]

            # Flatten rates for easier processing
            all_rates = adjusted_growth_rates + death_rates
            total_rate = sum(all_rates)

            # If no events possible, end simulation
            if total_rate == 0:
                break

            # Time until next event (exponentially distributed)
            dt = np.random.exponential(1.0 / total_rate)
            time += dt

            # If we've exceeded max_time, break
            if time > max_time:
                break

            # Select which event occurs
            event_idx = np.random.choice(len(all_rates), p=np.array(all_rates) / total_rate)

            # Apply the event
            if event_idx < num_species:  # Growth event
                population[event_idx] += 1
            else:  # Death event
                species_idx = event_idx - num_species
                population[species_idx] -= 1

                # Check for new extinctions
                if population[species_idx] == 0 and not extinct_in_sim[species_idx]:
                    extinction_counts[species_idx] += 1
                    extinction_times[species_idx].append(time)
                    extinct_in_sim[species_idx] = True

        # Fill in any remaining time points
        while next_time_point_idx < time_points:
            trajectory[:, next_time_point_idx] = population
            next_time_point_idx += 1

        # Add this simulation's trajectory to the average
        avg_trajectories += trajectory

        # Check for species that never went extinct in this simulation
        for i in range(num_species):
            if population[i] > 0 and not extinct_in_sim[i]:
                # Record as "no extinction" by adding a None to extinction_times
                extinction_times[i].append(None)

    # Calculate average trajectories
    avg_trajectories /= num_simulations

    # Calculate extinction probabilities and statistics
    extinction_probs = extinction_counts / num_simulations

    # Calculate median extinction times (ignoring None values)
    median_extinction_times = []
    for times in extinction_times:
        valid_times = [t for t in times if t is not None]
        if valid_times:
            median_extinction_times.append(np.median(valid_times))
        else:
            median_extinction_times.append(float("inf"))

    # Generate research log
    log = "# Microbial Population Dynamics Simulation Results\\n\\n"
    log += f"Simulations run: {num_simulations}\\n"
    log += f"Maximum simulation time: {max_time}\\n\\n"

    log += "## Species Parameters\\n"
    for i in range(num_species):
        log += f"\\nSpecies {i + 1}:\\n"
        log += f"  Initial population: {initial_populations[i]}\\n"
        log += f"  Growth rate: {growth_rates[i]}\\n"
        log += f"  Clearance rate: {clearance_rates[i]}\\n"
        log += f"  Carrying capacity: {carrying_capacities[i]}\\n"

    log += "\\n## Extinction Analysis\\n"
    for i in range(num_species):
        log += f"\\nSpecies {i + 1}:\\n"
        log += f"  Extinction probability: {extinction_probs[i]:.2f}\\n"

        if extinction_probs[i] > 0:
            valid_times = [t for t in extinction_times[i] if t is not None]
            if valid_times:
                log += f"  Median extinction time: {np.median(valid_times):.2f}\\n"
                log += f"  Mean extinction time: {np.mean(valid_times):.2f}\\n"
                log += f"  Standard deviation: {np.std(valid_times):.2f}\\n"

                # Calculate confidence intervals if we have enough data
                if len(valid_times) >= 10:
                    ci = stats.t.interval(
                        0.95,
                        len(valid_times) - 1,
                        loc=np.mean(valid_times),
                        scale=stats.sem(valid_times),
                    )
                    log += f"  95% CI for extinction time: ({ci[0]:.2f}, {ci[1]:.2f})\\n"
            else:
                log += "  No extinctions observed in any simulations\\n"

    # Save average trajectories to CSV file
    filename = "population_trajectories.csv"
    header = "Time," + ",".join([f"Species_{i + 1}" for i in range(num_species)])
    data = np.column_stack((time_grid, avg_trajectories.T))
    np.savetxt(filename, data, delimiter=",", header=header, comments="")

    log += "\\n## Population Trajectories\\n"
    log += f"Average population trajectories saved to '{filename}'\\n"

    return log

# Execute the function
try:
    result = simulate_microbial_population_dynamics(
        initial_populations=auto_convert(os.environ.get("PARAM_INITIAL_POPULATIONS", "")),
        growth_rates=auto_convert(os.environ.get("PARAM_GROWTH_RATES", "")),
        clearance_rates=auto_convert(os.environ.get("PARAM_CLEARANCE_RATES", "")),
        carrying_capacities=auto_convert(os.environ.get("PARAM_CARRYING_CAPACITIES", "")),
        max_time=auto_convert(os.environ.get("PARAM_MAX_TIME", "100")),
        num_simulations=auto_convert(os.environ.get("PARAM_NUM_SIMULATIONS", "100")),
        time_points=auto_convert(os.environ.get("PARAM_TIME_POINTS", "100")),
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
    "function": "simulate_microbial_population_dynamics",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("simulate_microbial_population_dynamics_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("simulate_microbial_population_dynamics_output.txt", "w") as f:
    f.write("Biomni: Simulate Microbial Population Dynamics" + NL)
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
        biomni_function: "simulate_microbial_population_dynamics"
    END_VERSIONS
    """
}

workflow SIMULATE_MICROBIAL_POPULATION_DYNAMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SIMULATE_MICROBIAL_POPULATION_DYNAMICS(ch_input)

    emit:
    results = SIMULATE_MICROBIAL_POPULATION_DYNAMICS.out.results
    output = SIMULATE_MICROBIAL_POPULATION_DYNAMICS.out.output
    versions = SIMULATE_MICROBIAL_POPULATION_DYNAMICS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SIMULATE_MICROBIAL_POPULATION_DYNAMICS_WORKFLOW(ch_input)

    SIMULATE_MICROBIAL_POPULATION_DYNAMICS_WORKFLOW.out.output.view { "Output: $it" }
}
