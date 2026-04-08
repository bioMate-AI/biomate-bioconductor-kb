#!/usr/bin/env nextflow
/*
 * systems_biology/simulate_metabolic_network_perturbation
 * Construct and simulate kinetic models of metabolic networks and analyze their responses to perturbations.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Use COBRApy built-in textbook model (E. coli core)
params.model_file = 'textbook'
// Initial concentrations for some key metabolites
params.initial_concentrations = '{"glc__D_e": 10.0, "pyr_c": 1.0, "atp_c": 5.0}'
// Perturbation: increase glucose at time 20
params.perturbation_params = '{"time": 20.0, "metabolite": "glc__D_e", "factor": 2.0}'
params.simulation_time = '100'
params.time_points = '500'

process SIMULATE_METABOLIC_NETWORK_PERTURBATION {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("simulate_metabolic_network_perturbation_results.json"), emit: results
    tuple val(meta), path("simulate_metabolic_network_perturbation_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_MODEL_FILE="${params.model_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_INITIAL_CONCENTRATIONS="${params.initial_concentrations?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PERTURBATION_PARAMS="${params.perturbation_params?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SIMULATION_TIME="${params.simulation_time?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TIME_POINTS="${params.time_points?.toString()?.replace('"', '\\"') ?: 'null'}"

    # Set cache directory to current working directory
    export XDG_CACHE_HOME=\$(pwd)/.cache
    export HOME=\$(pwd)
    mkdir -p \$XDG_CACHE_HOME

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



def simulate_metabolic_network_perturbation(
    model_file, initial_concentrations, perturbation_params, simulation_time=100, time_points=1000
):
    '''
    Construct and simulate kinetic models of metabolic networks and analyze their responses to perturbations.

    Parameters:
    -----------
    model_file : str
        Path to the COBRA model file (SBML format)
    initial_concentrations : dict
        Dictionary mapping metabolite IDs to their initial concentrations
    perturbation_params : dict
        Dictionary with the following keys:
        - 'time': float, time at which perturbation is applied
        - 'metabolite': str, ID of the metabolite to perturb
        - 'factor': float, multiplication factor for the metabolite concentration
    simulation_time : float, optional
        Total simulation time (default: 100)
    time_points : int, optional
        Number of time points to simulate (default: 1000)

    Returns:
    --------
    str
        Research log summarizing the steps taken and results obtained
    '''

    import cobra
    import numpy as np
    import pandas as pd
    from scipy.integrate import solve_ivp

    # Step 1: Load the metabolic model
    try:
        if model_file == 'textbook' or model_file is None:
            model = cobra.io.load_model('textbook')
            log = f"Loaded COBRApy textbook model (E. coli core) with {len(model.reactions)} reactions and {len(model.metabolites)} metabolites.\\n\\n"
        elif model_file.endswith(".xml") or model_file.endswith(".sbml"):
            model = cobra.io.read_sbml_model(model_file)
            log = f"Loaded metabolic model from {model_file} with {len(model.reactions)} reactions and {len(model.metabolites)} metabolites.\\n\\n"
        elif model_file.endswith(".json"):
            model = cobra.io.load_json_model(model_file)
            log = f"Loaded metabolic model from {model_file} with {len(model.reactions)} reactions and {len(model.metabolites)} metabolites.\\n\\n"
        else:
            model = cobra.io.load_model(model_file)
            log = f"Loaded metabolic model {model_file} with {len(model.reactions)} reactions and {len(model.metabolites)} metabolites.\\n\\n"
    except Exception as e:
        return f"Error loading model: {str(e)}"

    # Step 2: Set up metabolite list and initial concentrations
    metabolites = list(model.metabolites)
    metabolite_ids = [m.id for m in metabolites]

    # Set default initial concentrations for metabolites not specified
    conc_array = np.ones(len(metabolites))
    for i, m_id in enumerate(metabolite_ids):
        if m_id in initial_concentrations:
            conc_array[i] = initial_concentrations[m_id]

    log += "Initial concentrations set up for all metabolites.\\n\\n"

    # Step 3: Define kinetic model using simple mass-action kinetics
    def mass_action_kinetics(reaction, concentrations, metabolite_ids):
        # Simple mass-action kinetics: product of substrate concentrations
        rate = 1.0
        for metabolite, coeff in reaction.metabolites.items():
            if coeff < 0:  # Substrate
                idx = metabolite_ids.index(metabolite.id)
                rate *= concentrations[idx] ** abs(coeff)
        return rate

    # Step 4: Define ODE system
    def ode_system(t, concentrations, metabolite_ids, reactions, perturbation):
        dC_dt = np.zeros(len(concentrations))

        # Apply perturbation if we're at or past the perturbation time
        if t >= perturbation["time"]:
            perturb_idx = metabolite_ids.index(perturbation["metabolite"])
            if not perturbation.get("applied", False):
                concentrations[perturb_idx] *= perturbation["factor"]
                perturbation["applied"] = True

        # Calculate reaction rates
        rates = {}
        for reaction in reactions:
            rates[reaction.id] = mass_action_kinetics(reaction, concentrations, metabolite_ids)

        # Update concentration changes based on stoichiometry and rates
        for i, metabolite_id in enumerate(metabolite_ids):
            for reaction in reactions:
                if metabolite_id in [m.id for m in reaction.metabolites]:
                    coeff = reaction.metabolites[model.metabolites.get_by_id(metabolite_id)]
                    dC_dt[i] += coeff * rates[reaction.id]

        return dC_dt

    log += "Kinetic model defined using mass-action kinetics for all reactions.\\n\\n"

    # Step 5: Simulate the system
    perturbation = perturbation_params.copy()
    perturbation["applied"] = False

    t_span = (0, simulation_time)
    t_eval = np.linspace(0, simulation_time, time_points)

    log += f"Starting simulation for {simulation_time} time units with perturbation of {perturbation['metabolite']} "
    log += f"by factor {perturbation['factor']} at time {perturbation['time']}.\\n\\n"

    try:
        solution = solve_ivp(
            lambda t, y: ode_system(t, y, metabolite_ids, model.reactions, perturbation),
            t_span,
            conc_array,
            t_eval=t_eval,
            method="LSODA",
        )

        log += f"Simulation completed successfully with {len(solution.t)} time points.\\n\\n"
    except Exception as e:
        return f"Error during simulation: {str(e)}"

    # Step 6: Calculate fluxes at each time point
    fluxes = np.zeros((len(solution.t), len(model.reactions)))
    reaction_ids = [r.id for r in model.reactions]

    for t_idx, t in enumerate(solution.t):
        concentrations = solution.y[:, t_idx]
        perturbation_temp = perturbation.copy()
        if t >= perturbation["time"]:
            perturbation_temp["applied"] = True

        for r_idx, reaction in enumerate(model.reactions):
            fluxes[t_idx, r_idx] = mass_action_kinetics(reaction, concentrations, metabolite_ids)

    log += "Calculated reaction fluxes for all time points.\\n\\n"

    # Step 7: Save results to files
    conc_df = pd.DataFrame(solution.y.T, columns=metabolite_ids)
    conc_df["time"] = solution.t
    conc_file = "metabolite_concentrations.csv"
    conc_df.to_csv(conc_file, index=False)

    flux_df = pd.DataFrame(fluxes, columns=reaction_ids)
    flux_df["time"] = solution.t
    flux_file = "reaction_fluxes.csv"
    flux_df.to_csv(flux_file, index=False)

    log += f"Results saved to {conc_file} and {flux_file}.\\n\\n"

    # Step 8: Analyze perturbation response
    perturb_time_idx = np.where(solution.t >= perturbation["time"])[0][0]
    pre_perturb = solution.y[:, perturb_time_idx - 1]
    post_perturb = solution.y[:, perturb_time_idx]

    # Find metabolites with significant changes
    significant_changes = []
    for i, m_id in enumerate(metabolite_ids):
        rel_change = abs(post_perturb[i] - pre_perturb[i]) / pre_perturb[i] if pre_perturb[i] > 0 else 0
        if rel_change > 0.05:  # 5% change threshold
            significant_changes.append((m_id, rel_change))

    log += "Perturbation Analysis Results:\\n"
    log += f"Perturbation of {perturbation['metabolite']} at time {perturbation['time']} by factor {perturbation['factor']}.\\n"
    log += f"Number of metabolites with significant immediate response: {len(significant_changes)}.\\n"

    if significant_changes:
        log += "Top 5 most affected metabolites (by relative concentration change):\\n"
        for m_id, change in sorted(significant_changes, key=lambda x: x[1], reverse=True)[:5]:
            log += f"  - {m_id}: {change * 100:.2f}% change\\n"

    log += "\\nSimulation and perturbation analysis completed successfully."

    return log

# Execute the function
try:
    result = simulate_metabolic_network_perturbation(
        model_file=auto_convert(os.environ.get("PARAM_MODEL_FILE", "")),
        initial_concentrations=auto_convert(os.environ.get("PARAM_INITIAL_CONCENTRATIONS", "")),
        perturbation_params=auto_convert(os.environ.get("PARAM_PERTURBATION_PARAMS", "")),
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
    "function": "simulate_metabolic_network_perturbation",
    "domain": "systems_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("simulate_metabolic_network_perturbation_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("simulate_metabolic_network_perturbation_output.txt", "w") as f:
    f.write("Biomni: Simulate Metabolic Network Perturbation" + NL)
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
        biomni_function: "simulate_metabolic_network_perturbation"
    END_VERSIONS
    """
}

workflow SIMULATE_METABOLIC_NETWORK_PERTURBATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SIMULATE_METABOLIC_NETWORK_PERTURBATION(ch_input)

    emit:
    results = SIMULATE_METABOLIC_NETWORK_PERTURBATION.out.results
    output = SIMULATE_METABOLIC_NETWORK_PERTURBATION.out.output
    versions = SIMULATE_METABOLIC_NETWORK_PERTURBATION.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SIMULATE_METABOLIC_NETWORK_PERTURBATION_WORKFLOW(ch_input)

    SIMULATE_METABOLIC_NETWORK_PERTURBATION_WORKFLOW.out.output.view { "Output: $it" }
}
