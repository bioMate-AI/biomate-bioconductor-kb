#!/usr/bin/env nextflow
/*
 * systems_biology/simulate_renin_angiotensin_system_dynamics
 * Simulate the time-dependent concentrations of renin-angiotensin system (RAS) components.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: RAS system initial concentrations (nM)
params.initial_concentrations = '{"renin": 1.0, "angiotensinogen": 1000.0, "angiotensin_I": 0.5, "angiotensin_II": 0.1, "ACE2_angiotensin_II": 0.05, "angiotensin_1_7": 0.02}'
// Kinetic rate constants (per hour)
params.rate_constants = '{"k_ren": 0.1, "k_agt": 5.0, "k_ace": 2.0, "k_ace2": 0.5, "k_at1r": 1.0, "k_mas": 0.3}'
// Feedback parameters
params.feedback_params = '{"fb_ang_II": 0.8, "fb_ace2": 0.5}'
params.simulation_time = '48'
params.time_points = '100'

process SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("simulate_renin_angiotensin_system_dynamics_results.json"), emit: results
    tuple val(meta), path("simulate_renin_angiotensin_system_dynamics_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_INITIAL_CONCENTRATIONS="${params.initial_concentrations?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_RATE_CONSTANTS="${params.rate_constants?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FEEDBACK_PARAMS="${params.feedback_params?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def simulate_renin_angiotensin_system_dynamics(
    initial_concentrations, rate_constants, feedback_params, simulation_time=48, time_points=100
):
    '''
    Simulate the time-dependent concentrations of renin-angiotensin system (RAS) components.

    Parameters:
    -----------
    initial_concentrations : dict
        Initial concentrations of RAS components with keys:
        'renin', 'angiotensinogen', 'angiotensin_I', 'angiotensin_II',
        'ACE2_angiotensin_II', 'angiotensin_1_7'

    rate_constants : dict
        Kinetic rate constants with keys:
        'k_ren' (renin production), 'k_agt' (angiotensinogen production),
        'k_ace' (ACE conversion rate), 'k_ace2' (ACE2 conversion rate),
        'k_at1r' (AT1R binding rate), 'k_mas' (Mas receptor binding rate)

    feedback_params : dict
        Parameters controlling feedback mechanisms with keys:
        'fb_ang_II' (angiotensin II feedback), 'fb_ace2' (ACE2 feedback)

    simulation_time : float, optional
        Total simulation time in hours (default: 48)

    time_points : int, optional
        Number of time points to evaluate (default: 100)

    Returns:
    --------
    str
        Research log summarizing the simulation steps and results
    '''

    import numpy as np
    import pandas as pd
    from scipy.integrate import solve_ivp

    # Extract initial concentrations
    y0 = [
        initial_concentrations["renin"],
        initial_concentrations["angiotensinogen"],
        initial_concentrations["angiotensin_I"],
        initial_concentrations["angiotensin_II"],
        initial_concentrations["ACE2_angiotensin_II"],
        initial_concentrations["angiotensin_1_7"],
    ]

    # Define the system of ODEs
    def ras_ode_system(t, y):
        renin, agt, ang_I, ang_II, ace2_ang_II, ang_1_7 = y

        # Production rates with feedback
        renin_production = rate_constants["k_ren"] * (1 / (1 + feedback_params["fb_ang_II"] * ang_II))
        agt_production = rate_constants["k_agt"]

        # Conversion rates
        ang_I_formation = renin * agt
        ang_II_formation = rate_constants["k_ace"] * ang_I
        ace2_binding = rate_constants["k_ace2"] * ang_II
        ang_1_7_formation = ace2_ang_II

        # Clearance/degradation (simplified as proportional to concentration)
        renin_clearance = 0.1 * renin
        agt_clearance = 0.05 * agt
        ang_I_clearance = 0.2 * ang_I
        ang_II_clearance = 0.3 * ang_II + rate_constants["k_at1r"] * ang_II
        ace2_ang_II_clearance = 0.15 * ace2_ang_II
        ang_1_7_clearance = 0.25 * ang_1_7 + rate_constants["k_mas"] * ang_1_7

        # ODEs
        drenin_dt = renin_production - renin_clearance
        dagt_dt = agt_production - agt_clearance - ang_I_formation
        dang_I_dt = ang_I_formation - ang_I_clearance - ang_II_formation
        dang_II_dt = ang_II_formation - ang_II_clearance - ace2_binding
        dace2_ang_II_dt = ace2_binding - ace2_ang_II_clearance - ang_1_7_formation
        dang_1_7_dt = ang_1_7_formation - ang_1_7_clearance

        return [drenin_dt, dagt_dt, dang_I_dt, dang_II_dt, dace2_ang_II_dt, dang_1_7_dt]

    # Time points for simulation
    t_span = (0, simulation_time)
    t_eval = np.linspace(0, simulation_time, time_points)

    # Solve the ODE system
    solution = solve_ivp(ras_ode_system, t_span, y0, method="RK45", t_eval=t_eval, rtol=1e-6)

    # Create DataFrame with results
    component_names = [
        "Renin",
        "Angiotensinogen",
        "Angiotensin I",
        "Angiotensin II",
        "ACE2-Angiotensin II",
        "Angiotensin 1-7",
    ]
    results_df = pd.DataFrame(solution.y.T, columns=component_names)
    results_df.insert(0, "Time (hours)", solution.t)

    # Save results to CSV
    results_file = "ras_simulation_results.csv"
    results_df.to_csv(results_file, index=False)

    # Create research log
    log = f'''RAS ODE Modeling Simulation Log:

1. Initialized RAS component concentrations:
   - Renin: {initial_concentrations["renin"]}
   - Angiotensinogen: {initial_concentrations["angiotensinogen"]}
   - Angiotensin I: {initial_concentrations["angiotensin_I"]}
   - Angiotensin II: {initial_concentrations["angiotensin_II"]}
   - ACE2-Angiotensin II complex: {initial_concentrations["ACE2_angiotensin_II"]}
   - Angiotensin 1-7: {initial_concentrations["angiotensin_1_7"]}

2. Applied rate constants:
   - Renin production (k_ren): {rate_constants["k_ren"]}
   - Angiotensinogen production (k_agt): {rate_constants["k_agt"]}
   - ACE conversion rate (k_ace): {rate_constants["k_ace"]}
   - ACE2 conversion rate (k_ace2): {rate_constants["k_ace2"]}
   - AT1R binding rate (k_at1r): {rate_constants["k_at1r"]}
   - Mas receptor binding rate (k_mas): {rate_constants["k_mas"]}

3. Feedback parameters:
   - Angiotensin II feedback (fb_ang_II): {feedback_params["fb_ang_II"]}
   - ACE2 feedback (fb_ace2): {feedback_params["fb_ace2"]}

4. Simulation parameters:
   - Total simulation time: {simulation_time} hours
   - Number of time points: {time_points}

5. Solved system of ODEs using SciPy's solve_ivp with RK45 method.

6. Final concentrations at {simulation_time} hours:
   - Renin: {results_df["Renin"].iloc[-1]:.4f}
   - Angiotensinogen: {results_df["Angiotensinogen"].iloc[-1]:.4f}
   - Angiotensin I: {results_df["Angiotensin I"].iloc[-1]:.4f}
   - Angiotensin II: {results_df["Angiotensin II"].iloc[-1]:.4f}
   - ACE2-Angiotensin II complex: {results_df["ACE2-Angiotensin II"].iloc[-1]:.4f}
   - Angiotensin 1-7: {results_df["Angiotensin 1-7"].iloc[-1]:.4f}

7. Results saved to file: {results_file}

8. Key observations:
   - The model captures the conversion of Angiotensinogen to Angiotensin I via Renin
   - Angiotensin I is converted to Angiotensin II via ACE
   - Angiotensin II binds with ACE2 to form the ACE2-Angiotensin II complex
   - The complex is converted to Angiotensin 1-7
   - Feedback mechanisms regulate the production rates
'''

    return log

# Execute the function
try:
    result = simulate_renin_angiotensin_system_dynamics(
        initial_concentrations=auto_convert(os.environ.get("PARAM_INITIAL_CONCENTRATIONS", "")),
        rate_constants=auto_convert(os.environ.get("PARAM_RATE_CONSTANTS", "")),
        feedback_params=auto_convert(os.environ.get("PARAM_FEEDBACK_PARAMS", "")),
        simulation_time=auto_convert(os.environ.get("PARAM_SIMULATION_TIME", "48")),
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
    "function": "simulate_renin_angiotensin_system_dynamics",
    "domain": "systems_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("simulate_renin_angiotensin_system_dynamics_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("simulate_renin_angiotensin_system_dynamics_output.txt", "w") as f:
    f.write("Biomni: Simulate Renin Angiotensin System Dynamics" + NL)
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
        biomni_function: "simulate_renin_angiotensin_system_dynamics"
    END_VERSIONS
    """
}

workflow SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS(ch_input)

    emit:
    results = SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS.out.results
    output = SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS.out.output
    versions = SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS_WORKFLOW(ch_input)

    SIMULATE_RENIN_ANGIOTENSIN_SYSTEM_DYNAMICS_WORKFLOW.out.output.view { "Output: $it" }
}
