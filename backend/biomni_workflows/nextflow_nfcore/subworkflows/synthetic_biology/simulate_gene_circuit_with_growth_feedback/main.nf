#!/usr/bin/env nextflow
/*
 * synthetic_biology/simulate_gene_circuit_with_growth_feedback
 * Simulate gene regulatory circuit dynamics with growth feedback.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Toggle switch circuit (2 mutually repressing genes)
params.circuit_topology = '[[0, -1], [-1, 0]]'
params.kinetic_params = '{"basal_rates": [0.1, 0.1], "degradation_rates": [0.05, 0.05], "hill_coefficients": [2.0, 2.0], "threshold_constants": [0.5, 0.5]}'
params.growth_params = '{"max_growth_rate": 0.02, "growth_inhibition": 0.01, "gene_growth_weights": [0.3, 0.3]}'
params.simulation_time = '100'
params.time_points = '1000'

process SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("simulate_gene_circuit_with_growth_feedback_results.json"), emit: results
    tuple val(meta), path("simulate_gene_circuit_with_growth_feedback_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_CIRCUIT_TOPOLOGY="${params.circuit_topology?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_KINETIC_PARAMS="${params.kinetic_params?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GROWTH_PARAMS="${params.growth_params?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def simulate_gene_circuit_with_growth_feedback(
    circuit_topology,
    kinetic_params,
    growth_params,
    simulation_time=100,
    time_points=1000,
):
    '''Simulate gene regulatory circuit dynamics with growth feedback.

    Parameters
    ----------
    circuit_topology : numpy.ndarray
        Adjacency matrix representing the gene circuit topology.
        Positive values indicate activation, negative values indicate repression.
        Shape should be (n_genes, n_genes) where n_genes is the number of genes in the circuit.

    kinetic_params : dict
        Dictionary containing kinetic parameters:
        - 'basal_rates': list of basal expression rates for each gene
        - 'degradation_rates': list of degradation rates for each gene
        - 'hill_coefficients': list of Hill coefficients for regulatory interactions
        - 'threshold_constants': list of threshold constants for regulatory interactions

    growth_params : dict
        Dictionary containing growth-related parameters:
        - 'max_growth_rate': maximum cell growth rate
        - 'growth_inhibition': how gene expression affects growth
        - 'gene_growth_weights': weights for how each gene affects growth

    simulation_time : float, optional
        Total simulation time (default: 100)

    time_points : int, optional
        Number of time points to sample (default: 1000)

    Returns
    -------
    str
        Research log summarizing the simulation and results with file names of saved data

    '''
    import datetime
    import json
    import os

    import numpy as np
    from scipy.integrate import solve_ivp

    # Extract parameters
    n_genes = circuit_topology.shape[0]
    basal_rates = kinetic_params["basal_rates"]
    degradation_rates = kinetic_params["degradation_rates"]
    hill_coefficients = kinetic_params["hill_coefficients"]
    threshold_constants = kinetic_params["threshold_constants"]

    max_growth_rate = growth_params["max_growth_rate"]
    growth_inhibition = growth_params["growth_inhibition"]
    gene_growth_weights = growth_params["gene_growth_weights"]

    # Define the ODE system
    def gene_circuit_odes(t, state):
        # Extract state variables
        gene_expressions = state[:n_genes]
        cell_mass = state[n_genes]

        # Initialize derivatives
        dxdt = np.zeros(n_genes + 1)

        # Gene expression dynamics
        for i in range(n_genes):
            # Basal expression
            production = basal_rates[i]

            # Regulatory influences
            for j in range(n_genes):
                if circuit_topology[i, j] != 0:
                    # Calculate regulatory effect
                    regulation = gene_expressions[j] ** hill_coefficients[j] / (
                        threshold_constants[j] ** hill_coefficients[j] + gene_expressions[j] ** hill_coefficients[j]
                    )

                    if circuit_topology[i, j] > 0:  # Activation
                        production *= 1 + circuit_topology[i, j] * regulation
                    else:  # Repression
                        production *= 1 + circuit_topology[i, j] * (1 - regulation)

            # Dilution due to growth and degradation
            dilution = degradation_rates[i] + (dxdt[n_genes] / cell_mass if cell_mass > 0 else 0)

            # Final rate equation for gene i
            dxdt[i] = production - dilution * gene_expressions[i]

        # Cell growth dynamics
        growth_burden = sum(gene_growth_weights[i] * gene_expressions[i] for i in range(n_genes))
        dxdt[n_genes] = max_growth_rate * cell_mass / (1 + growth_inhibition * growth_burden)

        return dxdt

    # Initial conditions (starting with low gene expression and unit cell mass)
    initial_state = np.zeros(n_genes + 1)
    initial_state[:n_genes] = 0.1  # Low initial gene expression
    initial_state[n_genes] = 1.0  # Initial cell mass

    # Solve the ODE system
    t_span = (0, simulation_time)
    t_eval = np.linspace(0, simulation_time, time_points)

    solution = solve_ivp(
        gene_circuit_odes,
        t_span,
        initial_state,
        method="LSODA",
        t_eval=t_eval,
        rtol=1e-6,
        atol=1e-9,
    )

    # Extract results
    time_series = solution.t
    gene_expression_time_series = solution.y[:n_genes, :]
    cell_growth_time_series = solution.y[n_genes, :]

    # Save results to files
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    results_dir = "gene_circuit_results"

    if not os.path.exists(results_dir):
        os.makedirs(results_dir)

    # Save time series data
    data_filename = f"{results_dir}/gene_circuit_simulation_{timestamp}.npz"
    np.savez(
        data_filename,
        time=time_series,
        gene_expression=gene_expression_time_series,
        cell_growth=cell_growth_time_series,
    )

    # Save parameters for reference
    params_filename = f"{results_dir}/simulation_params_{timestamp}.json"
    params_dict = {
        "circuit_topology": circuit_topology.tolist(),
        "kinetic_params": kinetic_params,
        "growth_params": growth_params,
        "simulation_time": simulation_time,
        "time_points": time_points,
    }

    with open(params_filename, "w") as f:
        json.dump(params_dict, f, indent=2)

    # Create research log
    log = f'''Gene Regulatory Circuit Simulation with Growth Feedback - {timestamp}

SIMULATION SUMMARY:
- Simulated a gene regulatory circuit with {n_genes} genes
- Incorporated growth feedback mechanisms
- Total simulation time: {simulation_time} time units
- Collected {time_points} data points

PARAMETERS:
- Basal expression rates: {basal_rates}
- Degradation rates: {degradation_rates}
- Max growth rate: {max_growth_rate}
- Growth inhibition factor: {growth_inhibition}

RESULTS:
- Final gene expression levels: {gene_expression_time_series[:, -1].tolist()}
- Final cell mass: {cell_growth_time_series[-1]:.4f}
- Growth rate at end of simulation: {max_growth_rate / (1 + growth_inhibition * sum(gene_growth_weights[i] * gene_expression_time_series[i, -1] for i in range(n_genes))):.4f}

FILES:
- Time series data saved to: {data_filename}
- Simulation parameters saved to: {params_filename}
'''

    return log

# Execute the function
try:
    import numpy as np
    circuit_topo = auto_convert(os.environ.get("PARAM_CIRCUIT_TOPOLOGY", ""))
    if isinstance(circuit_topo, list):
        circuit_topo = np.array(circuit_topo)
    result = simulate_gene_circuit_with_growth_feedback(
        circuit_topology=circuit_topo,
        kinetic_params=auto_convert(os.environ.get("PARAM_KINETIC_PARAMS", "")),
        growth_params=auto_convert(os.environ.get("PARAM_GROWTH_PARAMS", "")),
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
    "function": "simulate_gene_circuit_with_growth_feedback",
    "domain": "synthetic_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("simulate_gene_circuit_with_growth_feedback_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("simulate_gene_circuit_with_growth_feedback_output.txt", "w") as f:
    f.write("Biomni: Simulate Gene Circuit With Growth Feedback" + NL)
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
        biomni_function: "simulate_gene_circuit_with_growth_feedback"
    END_VERSIONS
    """
}

workflow SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK(ch_input)

    emit:
    results = SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK.out.results
    output = SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK.out.output
    versions = SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK_WORKFLOW(ch_input)

    SIMULATE_GENE_CIRCUIT_WITH_GROWTH_FEEDBACK_WORKFLOW.out.output.view { "Output: $it" }
}
