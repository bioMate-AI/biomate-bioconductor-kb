#!/usr/bin/env nextflow
/*
 * physiology/simulate_thyroid_hormone_pharmacokinetics
 * Simulates the transport and binding of thyroid hormones across different tissue compartments
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Thyroid hormone PK model parameters
params.parameters = '{"transport_rates": {"plasma_to_liver": 0.5, "liver_to_plasma": 0.3, "plasma_to_tissue": 0.2, "tissue_to_plasma": 0.1}, "binding_constants": {"T4_TBG_on": 1.5, "T4_TBG_off": 0.01, "T3_TBG_on": 0.8, "T3_TBG_off": 0.02}, "metabolism_rates": {"T4_to_T3_liver": 0.1, "T3_clearance": 0.05}, "volumes": {"plasma": 3.0, "liver": 1.5, "tissue": 40.0}}'
params.initial_conditions = '{"T4_plasma": 100.0, "T3_plasma": 1.5, "T4_liver": 50.0, "T3_liver": 0.8, "T4_tissue": 20.0, "T3_tissue": 0.5}'
params.time_span = '[0, 48]'
params.time_points = '100'

process SIMULATE_THYROID_HORMONE_PHARMACOKINETICS {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("simulate_thyroid_hormone_pharmacokinetics_results.json"), emit: results
    tuple val(meta), path("simulate_thyroid_hormone_pharmacokinetics_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_PARAMETERS="${params.parameters?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_INITIAL_CONDITIONS="${params.initial_conditions?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TIME_SPAN="${params.time_span?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def simulate_thyroid_hormone_pharmacokinetics(parameters, initial_conditions, time_span=(0, 24), time_points=100):
    '''Simulates the transport and binding of thyroid hormones across different tissue compartments
    using an ODE-based pharmacokinetic model.

    Parameters
    ----------
    parameters : dict
        Dictionary containing model parameters:
        - transport_rates : dict of rate constants for hormone transport between compartments
        - binding_constants : dict of association/dissociation constants for hormone-protein binding
        - metabolism_rates : dict of rate constants for hormone metabolism in different tissues
        - volumes : dict of compartment volumes

    initial_conditions : dict
        Dictionary of initial concentrations for all molecular species in each compartment

    time_span : tuple, optional
        Start and end time for simulation in hours (default: (0, 24))

    time_points : int, optional
        Number of time points to output (default: 100)

    Returns
    -------
    str
        Research log summarizing the simulation and results

    '''
    import numpy as np
    import pandas as pd
    from scipy.integrate import solve_ivp

    # Extract parameters
    transport_rates = parameters.get("transport_rates", {})
    binding_constants = parameters.get("binding_constants", {})
    metabolism_rates = parameters.get("metabolism_rates", {})
    volumes = parameters.get("volumes", {})

    # Convert initial conditions dictionary to array for solver
    species_names = list(initial_conditions.keys())
    y0 = [initial_conditions[name] for name in species_names]

    # Define the ODE system
    def pk_ode_system(t, y):
        # Initialize derivatives
        dydt = np.zeros_like(y)

        # Map array indices back to named species for readability
        species = {name: y[i] for i, name in enumerate(species_names)}

        # Example: For each compartment, calculate concentration changes

        # Blood compartment (example)
        if "T4_blood_free" in species:
            blood_idx = species_names.index("T4_blood_free")
            # Transport from blood to tissues
            for tissue in ["liver", "thyroid", "kidney"]:
                tissue_key = f"T4_{tissue}_free"
                if tissue_key in species:
                    tissue_idx = species_names.index(tissue_key)
                    rate_key = f"blood_to_{tissue}"
                    if rate_key in transport_rates:
                        # Transport out of blood
                        dydt[blood_idx] -= (
                            transport_rates[rate_key] * species["T4_blood_free"] / volumes.get("blood", 1)
                        )
                        # Transport into tissue
                        dydt[tissue_idx] += (
                            transport_rates[rate_key] * species["T4_blood_free"] / volumes.get(tissue, 1)
                        )

        # Protein binding in blood (example)
        if "T4_blood_free" in species and "TBG_blood" in species and "T4_TBG_complex" in species:
            free_idx = species_names.index("T4_blood_free")
            protein_idx = species_names.index("TBG_blood")
            complex_idx = species_names.index("T4_TBG_complex")

            # Association
            if "k_on_T4_TBG" in binding_constants:
                association = binding_constants["k_on_T4_TBG"] * species["T4_blood_free"] * species["TBG_blood"]
                dydt[free_idx] -= association
                dydt[protein_idx] -= association
                dydt[complex_idx] += association

            # Dissociation
            if "k_off_T4_TBG" in binding_constants:
                dissociation = binding_constants["k_off_T4_TBG"] * species["T4_TBG_complex"]
                dydt[free_idx] += dissociation
                dydt[protein_idx] += dissociation
                dydt[complex_idx] -= dissociation

        # Metabolism (example for liver)
        if "T4_liver_free" in species and "T3_liver_free" in species:
            t4_idx = species_names.index("T4_liver_free")
            t3_idx = species_names.index("T3_liver_free")

            if "T4_to_T3_liver" in metabolism_rates:
                conversion = metabolism_rates["T4_to_T3_liver"] * species["T4_liver_free"]
                dydt[t4_idx] -= conversion
                dydt[t3_idx] += conversion

        return dydt

    # Solve the ODE system
    t_eval = np.linspace(time_span[0], time_span[1], time_points)
    solution = solve_ivp(
        pk_ode_system,
        time_span,
        y0,
        method="BDF",  # Equivalent to MATLAB's ode15s
        t_eval=t_eval,
        rtol=1e-4,
        atol=1e-6,
    )

    # Process results
    if solution.success:
        # Create dataframe with results
        results_df = pd.DataFrame(solution.y.T, columns=species_names)
        results_df.insert(0, "Time", solution.t)

        # Save to CSV
        output_file = "thyroid_hormone_pk_simulation_results.csv"
        results_df.to_csv(output_file, index=False)

        # Generate research log
        log = "## Thyroid Hormone Pharmacokinetic Simulation Results\\n\\n"
        log += f"- Simulation time span: {time_span[0]} to {time_span[1]} hours\\n"
        log += f"- Number of molecular species modeled: {len(species_names)}\\n"
        log += (
            f"- Compartments included: {', '.join({name.split('_')[1] for name in species_names if '_' in name})}\\n\\n"
        )

        log += "### Key Observations:\\n"
        # Find peak concentrations and times
        for species in species_names:
            if "free" in species:  # Focus on free hormone concentrations
                idx = species_names.index(species)
                peak_conc = np.max(solution.y[idx])
                peak_time = solution.t[np.argmax(solution.y[idx])]
                final_conc = solution.y[idx][-1]

                log += f"- {species}: Peak concentration of {peak_conc:.4g} at {peak_time:.2f} hours, "
                log += f"final concentration of {final_conc:.4g}\\n"

        log += f"\\nDetailed concentration profiles saved to: {output_file}\\n"

        return log
    else:
        return f"Simulation failed: {solution.message}"

# Execute the function
try:
    result = simulate_thyroid_hormone_pharmacokinetics(
        parameters=auto_convert(os.environ.get("PARAM_PARAMETERS", "")),
        initial_conditions=auto_convert(os.environ.get("PARAM_INITIAL_CONDITIONS", "")),
        time_span=auto_convert(os.environ.get("PARAM_TIME_SPAN", "")),
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
    "function": "simulate_thyroid_hormone_pharmacokinetics",
    "domain": "physiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("simulate_thyroid_hormone_pharmacokinetics_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("simulate_thyroid_hormone_pharmacokinetics_output.txt", "w") as f:
    f.write("Biomni: Simulate Thyroid Hormone Pharmacokinetics" + NL)
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
        biomni_function: "simulate_thyroid_hormone_pharmacokinetics"
    END_VERSIONS
    """
}

workflow SIMULATE_THYROID_HORMONE_PHARMACOKINETICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SIMULATE_THYROID_HORMONE_PHARMACOKINETICS(ch_input)

    emit:
    results = SIMULATE_THYROID_HORMONE_PHARMACOKINETICS.out.results
    output = SIMULATE_THYROID_HORMONE_PHARMACOKINETICS.out.output
    versions = SIMULATE_THYROID_HORMONE_PHARMACOKINETICS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SIMULATE_THYROID_HORMONE_PHARMACOKINETICS_WORKFLOW(ch_input)

    SIMULATE_THYROID_HORMONE_PHARMACOKINETICS_WORKFLOW.out.output.view { "Output: $it" }
}
