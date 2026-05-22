#!/usr/bin/env nextflow
/*
 * microbiology/model_bacterial_growth_dynamics
 * Model bacterial population dynamics over time using ordinary differential equations.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: E. coli growth in batch culture (logistic growth model)
params.initial_population = '1000'
params.growth_rate = '0.5'
params.clearance_rate = '0.01'
params.niche_size = '1e9'
params.simulation_time = '24'
params.time_step = '0.1'

process MODEL_BACTERIAL_GROWTH_DYNAMICS {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("model_bacterial_growth_dynamics_results.json"), emit: results
    tuple val(meta), path("model_bacterial_growth_dynamics_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_INITIAL_POPULATION="${params.initial_population?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GROWTH_RATE="${params.growth_rate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CLEARANCE_RATE="${params.clearance_rate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NICHE_SIZE="${params.niche_size?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SIMULATION_TIME="${params.simulation_time?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TIME_STEP="${params.time_step?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import numpy as np
from scipy.integrate import solve_ivp
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

def bacterial_dynamics(t, y, growth_rate, clearance_rate, niche_size):
    '''ODE for bacterial population dynamics with logistic growth and clearance.'''
    population = y[0]
    # Logistic growth with clearance
    dP_dt = growth_rate * population * (1 - population / niche_size) - clearance_rate * population
    return [dP_dt]

def model_bacterial_growth_dynamics(
    initial_population: float,
    growth_rate: float,
    clearance_rate: float,
    niche_size: float,
    simulation_time: float = 24.0,
    time_step: float = 0.1
) -> str:
    '''
    Model bacterial population dynamics over time using ODEs.

    Args:
        initial_population: Initial bacterial population size (CFU/ml or cells)
        growth_rate: Bacterial growth rate (per hour)
        clearance_rate: Rate at which bacteria are cleared (per hour)
        niche_size: Maximum carrying capacity (CFU/ml or cells)
        simulation_time: Total simulation time in hours (default: 24)
        time_step: Time step for output (default: 0.1)

    Returns:
        Research log summarizing the simulation results
    '''
    # Solve ODE
    t_span = (0, simulation_time)
    t_eval = np.arange(0, simulation_time + time_step, time_step)

    solution = solve_ivp(
        bacterial_dynamics,
        t_span,
        [initial_population],
        t_eval=t_eval,
        args=(growth_rate, clearance_rate, niche_size),
        method='RK45'
    )

    # Calculate key metrics
    final_population = solution.y[0][-1]
    max_population = np.max(solution.y[0])
    max_time = solution.t[np.argmax(solution.y[0])]

    # Determine growth phase
    if final_population > initial_population * 0.9 * niche_size / initial_population:
        phase = "stationary phase (near carrying capacity)"
    elif final_population > initial_population:
        phase = "exponential/log phase (still growing)"
    else:
        phase = "decline phase (clearance exceeds growth)"

    # Generate research log
    log = f'''## Bacterial Growth Dynamics Simulation

### Parameters
- Initial population: {initial_population:.2e} CFU/ml
- Growth rate: {growth_rate:.4f} per hour
- Clearance rate: {clearance_rate:.4f} per hour
- Niche size (carrying capacity): {niche_size:.2e} CFU/ml
- Simulation time: {simulation_time} hours

### Results
- Final population: {final_population:.2e} CFU/ml
- Maximum population: {max_population:.2e} CFU/ml (at t={max_time:.1f} h)
- Growth status: {phase}
- Net growth rate: {growth_rate - clearance_rate:.4f} per hour

### Time Course Data (selected points)
Time (h) | Population (CFU/ml)
---------|--------------------
'''
    # Add selected time points
    indices = np.linspace(0, len(solution.t) - 1, min(10, len(solution.t)), dtype=int)
    for idx in indices:
        log += f"{solution.t[idx]:8.1f} | {solution.y[0][idx]:.2e}\\n"

    return log

# Execute the function
try:
    result = model_bacterial_growth_dynamics(
        initial_population=auto_convert(os.environ.get("PARAM_INITIAL_POPULATION", "")),
        growth_rate=auto_convert(os.environ.get("PARAM_GROWTH_RATE", "")),
        clearance_rate=auto_convert(os.environ.get("PARAM_CLEARANCE_RATE", "")),
        niche_size=auto_convert(os.environ.get("PARAM_NICHE_SIZE", "")),
        simulation_time=auto_convert(os.environ.get("PARAM_SIMULATION_TIME", "24")),
        time_step=auto_convert(os.environ.get("PARAM_TIME_STEP", "0.1")),
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
    "function": "model_bacterial_growth_dynamics",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("model_bacterial_growth_dynamics_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("model_bacterial_growth_dynamics_output.txt", "w") as f:
    f.write("Biomni: Model Bacterial Growth Dynamics" + NL)
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
        biomni_function: "model_bacterial_growth_dynamics"
    END_VERSIONS
    """
}

workflow MODEL_BACTERIAL_GROWTH_DYNAMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    MODEL_BACTERIAL_GROWTH_DYNAMICS(ch_input)

    emit:
    results = MODEL_BACTERIAL_GROWTH_DYNAMICS.out.results
    output = MODEL_BACTERIAL_GROWTH_DYNAMICS.out.output
    versions = MODEL_BACTERIAL_GROWTH_DYNAMICS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    MODEL_BACTERIAL_GROWTH_DYNAMICS_WORKFLOW(ch_input)

    MODEL_BACTERIAL_GROWTH_DYNAMICS_WORKFLOW.out.output.view { "Output: $it" }
}
