#!/usr/bin/env nextflow
/*
 * systems_biology/model_protein_dimerization_network
 * Model protein dimerization networks to find equilibrium concentrations of dimers.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Protein dimerization network
params.monomer_concentrations = '{"ProteinA": 10.0, "ProteinB": 8.0, "ProteinC": 5.0}'
params.dimerization_affinities = '{"ProteinA-ProteinB": 1.5, "ProteinB-ProteinC": 2.0, "ProteinA-ProteinA": 0.8}'
params.network_topology = '[["ProteinA", "ProteinB"], ["ProteinB", "ProteinC"], ["ProteinA", "ProteinA"]]'

process MODEL_PROTEIN_DIMERIZATION_NETWORK {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("model_protein_dimerization_network_results.json"), emit: results
    tuple val(meta), path("model_protein_dimerization_network_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_MONOMER_CONCENTRATIONS="${params.monomer_concentrations?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DIMERIZATION_AFFINITIES="${params.dimerization_affinities?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NETWORK_TOPOLOGY="${params.network_topology?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def model_protein_dimerization_network(monomer_concentrations, dimerization_affinities, network_topology):
    '''
    Model protein dimerization networks to find equilibrium concentrations of dimers.

    Parameters:
    -----------
    monomer_concentrations : dict
        Dictionary mapping monomer names to their initial concentrations (in arbitrary units)
    dimerization_affinities : dict
        Dictionary mapping dimer names (as 'A-B' strings) to their association constants (Ka)
    network_topology : list of tuples
        List of (monomer1, monomer2) pairs that can form dimers

    Returns:
    --------
    str
        Research log summarizing the modeling process and results
    '''
    import time

    import numpy as np
    from scipy.integrate import solve_ivp

    # Validate and normalise inputs
    if monomer_concentrations is None or not isinstance(monomer_concentrations, dict):
        monomer_concentrations = {"ProteinA": 10.0, "ProteinB": 8.0, "ProteinC": 5.0}
    if dimerization_affinities is None or not isinstance(dimerization_affinities, dict):
        dimerization_affinities = {"ProteinA-ProteinB": 1.5, "ProteinB-ProteinC": 2.0, "ProteinA-ProteinA": 0.8}
    if network_topology is None or not isinstance(network_topology, list):
        network_topology = [["ProteinA", "ProteinB"], ["ProteinB", "ProteinC"], ["ProteinA", "ProteinA"]]
    # Ensure each topology entry is a list/tuple of 2 elements
    network_topology = [list(pair) for pair in network_topology if len(pair) >= 2]

    # Start timing
    start_time = time.time()

    # Extract unique monomers and create mapping to indices
    all_monomers = list(monomer_concentrations.keys())
    monomer_to_idx = {monomer: i for i, monomer in enumerate(all_monomers)}

    # Create mapping from dimer indices to names
    dimer_pairs = []
    dimer_names = []
    dimer_affinities = []

    for m1, m2 in network_topology:
        dimer_name = f"{m1}-{m2}"
        if dimer_name in dimerization_affinities:
            affinity = dimerization_affinities[dimer_name]
        else:
            # Try reverse order
            dimer_name = f"{m2}-{m1}"
            if dimer_name in dimerization_affinities:
                affinity = dimerization_affinities[dimer_name]
            else:
                raise ValueError(f"No affinity found for dimer pair {m1}-{m2}")

        dimer_pairs.append((monomer_to_idx[m1], monomer_to_idx[m2]))
        dimer_names.append(dimer_name)
        dimer_affinities.append(affinity)

    # Initial conditions (monomer concentrations followed by dimer concentrations)
    num_monomers = len(all_monomers)
    num_dimers = len(dimer_pairs)
    y0 = np.zeros(num_monomers + num_dimers)

    for monomer, conc in monomer_concentrations.items():
        y0[monomer_to_idx[monomer]] = conc

    # Define ODE system
    def dimerization_odes(t, y):
        dydt = np.zeros_like(y)

        # Extract current concentrations
        monomer_concs = y[:num_monomers]
        dimer_concs = y[num_monomers:]

        # Calculate rate of change for each species
        for i, ((m1_idx, m2_idx), affinity) in enumerate(zip(dimer_pairs, dimer_affinities, strict=False)):
            # Formation rate: kon * [A] * [B]
            # Dissociation rate: koff * [AB]
            # At equilibrium: kon/koff = Ka (affinity)
            # For simplicity, set kon = Ka and koff = 1

            kon = affinity
            koff = 1.0

            # Dimer formation/dissociation
            dimer_idx = num_monomers + i

            # Rate of change
            formation_rate = kon * monomer_concs[m1_idx] * monomer_concs[m2_idx]
            dissociation_rate = koff * dimer_concs[i]
            net_rate = formation_rate - dissociation_rate

            # Update rates for monomers and dimers
            dydt[m1_idx] -= net_rate
            dydt[m2_idx] -= net_rate
            dydt[dimer_idx] += net_rate

        return dydt

    # Solve ODE system to equilibrium
    # Using a long enough time to reach equilibrium
    t_span = (0, 1000)  # Arbitrary long time to reach equilibrium

    sol = solve_ivp(
        dimerization_odes,
        t_span,
        y0,
        method="BDF",  # Good for stiff problems
        rtol=1e-6,
        atol=1e-9,
    )

    # Extract final concentrations (equilibrium)
    final_monomer_concs = {monomer: sol.y[idx][-1] for monomer, idx in monomer_to_idx.items()}
    final_dimer_concs = {dimer_name: sol.y[num_monomers + i][-1] for i, dimer_name in enumerate(dimer_names)}

    # Calculate time taken
    elapsed_time = time.time() - start_time

    # Generate research log
    log = "Protein Dimerization Network Modeling\\n"
    log += "=====================================\\n\\n"
    log += "Network summary:\\n"
    log += f"- Number of monomers: {num_monomers}\\n"
    log += f"- Number of possible dimers: {num_dimers}\\n\\n"

    log += "Initial conditions:\\n"
    for monomer, conc in monomer_concentrations.items():
        log += f"- {monomer}: {conc:.4f}\\n"
    log += "\\n"

    log += "Dimerization affinities:\\n"
    for dimer, affinity in zip(dimer_names, dimer_affinities, strict=False):
        log += f"- {dimer}: {affinity:.4e}\\n"
    log += "\\n"

    log += "Equilibrium concentrations:\\n"
    log += "Monomers:\\n"
    for monomer, conc in final_monomer_concs.items():
        log += f"- {monomer}: {conc:.4f}\\n"

    log += "\\nDimers:\\n"
    for dimer, conc in final_dimer_concs.items():
        log += f"- {dimer}: {conc:.4f}\\n"
    log += "\\n"

    log += f"Simulation completed in {elapsed_time:.2f} seconds.\\n"

    return log

# Execute the function
try:
    result = model_protein_dimerization_network(
        monomer_concentrations=auto_convert(os.environ.get("PARAM_MONOMER_CONCENTRATIONS", "")),
        dimerization_affinities=auto_convert(os.environ.get("PARAM_DIMERIZATION_AFFINITIES", "")),
        network_topology=auto_convert(os.environ.get("PARAM_NETWORK_TOPOLOGY", "")),
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
    "function": "model_protein_dimerization_network",
    "domain": "systems_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("model_protein_dimerization_network_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("model_protein_dimerization_network_output.txt", "w") as f:
    f.write("Biomni: Model Protein Dimerization Network" + NL)
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
        biomni_function: "model_protein_dimerization_network"
    END_VERSIONS
    """
}

workflow MODEL_PROTEIN_DIMERIZATION_NETWORK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    MODEL_PROTEIN_DIMERIZATION_NETWORK(ch_input)

    emit:
    results = MODEL_PROTEIN_DIMERIZATION_NETWORK.out.results
    output = MODEL_PROTEIN_DIMERIZATION_NETWORK.out.output
    versions = MODEL_PROTEIN_DIMERIZATION_NETWORK.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    MODEL_PROTEIN_DIMERIZATION_NETWORK_WORKFLOW(ch_input)

    MODEL_PROTEIN_DIMERIZATION_NETWORK_WORKFLOW.out.output.view { "Output: $it" }
}
