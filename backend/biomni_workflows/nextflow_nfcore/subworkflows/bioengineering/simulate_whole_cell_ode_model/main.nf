#!/usr/bin/env nextflow
/*
 * bioengineering/simulate_whole_cell_ode_model
 * Simulate a whole-cell model represented as a system of ordinary differential equations (ODEs).
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Whole-cell ODE model parameters
params.initial_conditions = '{"mRNA": 1.0, "protein": 0.5, "metabolite": 2.0, "ATP": 5.0}'
params.parameters = '{"k_transcription": 0.5, "k_translation": 0.3, "k_mrna_deg": 0.1, "k_protein_deg": 0.05, "k_metabolism": 0.2, "k_atp_production": 0.4, "k_atp_consumption": 0.1}'
params.ode_function = null
params.time_span = '[0, 100]'
params.time_points = '1000'
params.method = 'LSODA'

process SIMULATE_WHOLE_CELL_ODE_MODEL {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("simulate_whole_cell_ode_model_results.json"), emit: results
    tuple val(meta), path("simulate_whole_cell_ode_model_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_INITIAL_CONDITIONS="${params.initial_conditions?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PARAMETERS="${params.parameters?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ODE_FUNCTION="${params.ode_function?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TIME_SPAN="${params.time_span?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TIME_POINTS="${params.time_points?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_METHOD="${params.method?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def simulate_whole_cell_ode_model(
    initial_conditions,
    parameters,
    ode_function=None,
    time_span=(0, 100),
    time_points=1000,
    method="LSODA",
):
    '''Simulate a whole-cell model represented as a system of ordinary differential equations (ODEs).

    Parameters
    ----------
    initial_conditions : dict or array-like
        Initial values for each state variable in the model. If dict, keys are variable names
        and values are initial concentrations/values. If array-like, order must match the
        order expected by the ODE function.
    parameters : dict
        Model parameters required by the ODE function. Keys are parameter names and
        values are parameter values.
    ode_function : callable, optional
        Function defining the system of ODEs. Should take arguments ``(t, y, *args)`` where
        ``t`` is time, ``y`` is the state vector, and ``args`` contains additional parameters.
        If None, a simple example whole-cell model will be used.
    time_span : tuple, default=(0, 100)
        Tuple of (start_time, end_time) for the simulation.
    time_points : int, default=1000
        Number of time points to evaluate.
    method : str, default='LSODA'
        Numerical integration method to use (e.g., 'RK45', 'LSODA', 'BDF').

    Returns
    -------
    str
        Research log summarizing the simulation steps and results. Results are saved
        to a CSV file and the filename is included in the log.

    '''
    from datetime import datetime

    import numpy as np
    import pandas as pd
    from scipy.integrate import solve_ivp

    # Validate inputs - use defaults if None
    if initial_conditions is None:
        initial_conditions = {"ATP": 1.0, "glucose": 5.0, "biomass": 0.1}
    if parameters is None:
        parameters = {"k_growth": 0.5, "k_uptake": 0.1, "yield": 0.4}
    if time_span is None:
        time_span = (0, 100)
    if time_points is None:
        time_points = 1000
    if method is None:
        method = "LSODA"
    time_points = int(time_points)

    # Define a default ODE function if none is provided
    if ode_function is None:

        def default_whole_cell_model(t, y, params):
            # Unpack state variables
            # Simple model with:
            # - mRNA (y[0])
            # - Protein (y[1])
            # - Metabolite (y[2])
            # - ATP (y[3])
            mRNA, protein, metabolite, atp = y

            # Unpack parameters
            k_transcription = params["k_transcription"]  # mRNA synthesis rate
            k_translation = params["k_translation"]  # Protein synthesis rate
            k_mrna_deg = params["k_mrna_deg"]  # mRNA degradation rate
            k_protein_deg = params["k_protein_deg"]  # Protein degradation rate
            k_metabolism = params["k_metabolism"]  # Metabolite production rate
            k_atp_production = params["k_atp_production"]  # ATP production rate
            k_atp_consumption = params["k_atp_consumption"]  # ATP consumption rate

            # ODEs
            dmRNA_dt = k_transcription - k_mrna_deg * mRNA
            dprotein_dt = k_translation * mRNA * atp - k_protein_deg * protein
            dmetabolite_dt = k_metabolism * protein - k_atp_production * metabolite
            datp_dt = k_atp_production * metabolite - k_atp_consumption * atp - k_translation * mRNA * atp

            return [dmRNA_dt, dprotein_dt, dmetabolite_dt, datp_dt]

        ode_function = default_whole_cell_model

    # Prepare initial conditions as array
    if isinstance(initial_conditions, dict):
        y0_values = list(initial_conditions.values())
        variable_names = list(initial_conditions.keys())
    else:
        y0_values = initial_conditions
        variable_names = [f"Variable_{i}" for i in range(len(initial_conditions))]

    # Set up time points
    t_eval = np.linspace(time_span[0], time_span[1], time_points)

    # Start research log
    log = []
    log.append("# Whole-Cell ODE Model Simulation")
    log.append(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    log.append("\\n## Simulation Setup")
    log.append(f"- Integration method: {method}")
    log.append(f"- Time span: {time_span[0]} to {time_span[1]} time units")
    log.append(f"- Number of time points: {time_points}")
    log.append(f"- Number of state variables: {len(y0_values)}")
    log.append("\\n## Initial Conditions")
    for _i, (name, value) in enumerate(zip(variable_names, y0_values, strict=False)):
        log.append(f"- {name}: {value}")

    log.append("\\n## Model Parameters")
    for param, value in parameters.items():
        log.append(f"- {param}: {value}")

    # Solve the ODE system
    log.append("\\n## Running Simulation")
    try:
        solution = solve_ivp(
            lambda t, y: ode_function(t, y, parameters),
            time_span,
            y0_values,
            method=method,
            t_eval=t_eval,
        )

        # Check if simulation was successful
        if solution.success:
            log.append("Simulation completed successfully.")
            log.append(f"- Number of function evaluations: {solution.nfev}")
            log.append(f"- Number of Jacobian evaluations: {solution.njev}")
            log.append(f"- Number of steps: {len(solution.t)}")

            # Create DataFrame with results
            results_df = pd.DataFrame(solution.y.T, columns=variable_names)
            results_df.insert(0, "Time", solution.t)

            # Save results to CSV
            filename = f"whole_cell_simulation_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
            results_df.to_csv(filename, index=False)

            log.append("\\n## Results Summary")
            log.append(f"Simulation results saved to: {filename}")

            # Calculate some basic statistics
            final_state = results_df.iloc[-1].drop("Time").to_dict()
            log.append("\\n## Final State")
            for var, value in final_state.items():
                log.append(f"- {var}: {value:.6f}")

        else:
            log.append(f"Simulation failed with message: {solution.message}")

    except Exception as e:
        log.append(f"Error during simulation: {str(e)}")

    # Return the research log
    return "\\n".join(log)

# Execute the function
try:
    result = simulate_whole_cell_ode_model(
        initial_conditions=auto_convert(os.environ.get("PARAM_INITIAL_CONDITIONS", "")),
        parameters=auto_convert(os.environ.get("PARAM_PARAMETERS", "")),
        ode_function=auto_convert(os.environ.get("PARAM_ODE_FUNCTION", "")),
        time_span=auto_convert(os.environ.get("PARAM_TIME_SPAN", "")),
        time_points=auto_convert(os.environ.get("PARAM_TIME_POINTS", "1000")),
        method=auto_convert(os.environ.get("PARAM_METHOD", "LSODA")),
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
    "function": "simulate_whole_cell_ode_model",
    "domain": "bioengineering",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("simulate_whole_cell_ode_model_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("simulate_whole_cell_ode_model_output.txt", "w") as f:
    f.write("Biomni: Simulate Whole Cell Ode Model" + NL)
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
        biomni_function: "simulate_whole_cell_ode_model"
    END_VERSIONS
    """
}

workflow SIMULATE_WHOLE_CELL_ODE_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SIMULATE_WHOLE_CELL_ODE_MODEL(ch_input)

    emit:
    results = SIMULATE_WHOLE_CELL_ODE_MODEL.out.results
    output = SIMULATE_WHOLE_CELL_ODE_MODEL.out.output
    versions = SIMULATE_WHOLE_CELL_ODE_MODEL.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SIMULATE_WHOLE_CELL_ODE_MODEL_WORKFLOW(ch_input)

    SIMULATE_WHOLE_CELL_ODE_MODEL_WORKFLOW.out.output.view { "Output: $it" }
}
