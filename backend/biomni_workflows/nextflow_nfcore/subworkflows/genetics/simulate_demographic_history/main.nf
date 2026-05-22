#!/usr/bin/env nextflow
/*
 * genetics/simulate_demographic_history
 * Simulate DNA sequences with specified demographic and coalescent histories using msprime.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.num_samples = '10'
params.sequence_length = '100000'
params.recombination_rate = '1e-08'
params.mutation_rate = '1e-08'
params.demographic_model = 'constant'
params.demographic_params = null
params.coalescent_model = 'kingman'
params.beta_coalescent_param = null
params.random_seed = null
params.output_file = 'simulated_sequences.vcf'

process SIMULATE_DEMOGRAPHIC_HISTORY {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("simulate_demographic_history_results.json"), emit: results
    tuple val(meta), path("simulate_demographic_history_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_NUM_SAMPLES="${params.num_samples?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SEQUENCE_LENGTH="${params.sequence_length?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_RECOMBINATION_RATE="${params.recombination_rate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MUTATION_RATE="${params.mutation_rate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DEMOGRAPHIC_MODEL="${params.demographic_model?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DEMOGRAPHIC_PARAMS="${params.demographic_params?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_COALESCENT_MODEL="${params.coalescent_model?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BETA_COALESCENT_PARAM="${params.beta_coalescent_param?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_RANDOM_SEED="${params.random_seed?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_FILE="${params.output_file?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import os
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



def simulate_demographic_history(
    num_samples=10,
    sequence_length=100000,
    recombination_rate=1e-8,
    mutation_rate=1e-8,
    demographic_model="constant",
    demographic_params=None,
    coalescent_model="kingman",
    beta_coalescent_param=None,
    random_seed=None,
    output_file="simulated_sequences.vcf",
):
    '''Simulate DNA sequences with specified demographic and coalescent histories using msprime.

    Parameters
    ----------
    num_samples : int
        Number of sample sequences to simulate
    sequence_length : int
        Length of the simulated sequence in base pairs
    recombination_rate : float
        Per-base recombination rate
    mutation_rate : float
        Per-base mutation rate
    demographic_model : str
        Type of demographic model to simulate. Options:
        - "constant": Constant population size
        - "bottleneck": Population bottleneck
        - "expansion": Population expansion
        - "contraction": Population contraction
        - "sawtooth": Sawtooth pattern of population size changes
    demographic_params : dict
        Parameters specific to the chosen demographic model. Supported formats::

            - For "constant": {"N": population size}
            - For "bottleneck": {
                "N_initial": initial pop size,
                "N_bottleneck": bottleneck pop size,
                "T_bottleneck": time of bottleneck (generations ago),
                "T_recovery": time of recovery (generations ago)
            }
            - For "expansion": {"N_initial": initial pop size, "N_final": final pop size, "T_expansion": time of expansion (generations ago)}
            - For "contraction": {"N_initial": initial pop size, "N_final": final pop size, "T_contraction": time of contraction (generations ago)}
            - For "sawtooth": {"N_values": list of population sizes, "times": list of times for changes}
    coalescent_model : str
        Type of coalescent model to use. Options:
        - "kingman": Standard Kingman coalescent
        - "beta": Beta-coalescent model
    beta_coalescent_param : float
        Parameter for beta-coalescent model (required if coalescent_model="beta")
    random_seed : int
        Seed for random number generator (for reproducibility)
    output_file : str
        Filename to save the simulated sequences (VCF format)

    Returns
    -------
    str
        Research log summarizing the simulation parameters and results

    '''
    import time

    import msprime

    start_time = time.time()
    log = []
    log.append("Demographic History Simulation using msprime")
    log.append("=============================================")
    log.append("Parameters:")
    log.append(f"  - Number of samples: {num_samples}")
    log.append(f"  - Sequence length: {sequence_length} bp")
    log.append(f"  - Recombination rate: {recombination_rate}")
    log.append(f"  - Mutation rate: {mutation_rate}")
    log.append(f"  - Demographic model: {demographic_model}")
    log.append(f"  - Coalescent model: {coalescent_model}")

    # Set up demographic model
    if demographic_params is None:
        demographic_params = {"N": 10000}  # Default to constant population of 10000

    if demographic_model == "constant":
        N = demographic_params.get("N", 10000)
        demography = msprime.Demography()
        demography.add_population(name="pop0", initial_size=N)
        log.append(f"  - Constant population size: N = {N}")

    elif demographic_model == "bottleneck":
        N_initial = demographic_params.get("N_initial", 10000)
        N_bottleneck = demographic_params.get("N_bottleneck", 1000)
        T_bottleneck = demographic_params.get("T_bottleneck", 1000)
        T_recovery = demographic_params.get("T_recovery", 500)

        demography = msprime.Demography()
        demography.add_population(name="pop0", initial_size=N_initial)
        demography.add_population_parameters_change(time=T_recovery, initial_size=N_bottleneck)
        demography.add_population_parameters_change(time=T_bottleneck, initial_size=N_initial)

        log.append("  - Bottleneck model:")
        log.append(f"    * Initial population size: {N_initial}")
        log.append(f"    * Bottleneck population size: {N_bottleneck}")
        log.append(f"    * Bottleneck time (generations ago): {T_bottleneck}")
        log.append(f"    * Recovery time (generations ago): {T_recovery}")

    elif demographic_model == "expansion":
        N_initial = demographic_params.get("N_initial", 1000)
        N_final = demographic_params.get("N_final", 10000)
        T_expansion = demographic_params.get("T_expansion", 1000)

        demography = msprime.Demography()
        demography.add_population(name="pop0", initial_size=N_final)
        demography.add_population_parameters_change(time=T_expansion, initial_size=N_initial)

        log.append("  - Expansion model:")
        log.append(f"    * Initial population size: {N_initial}")
        log.append(f"    * Final population size: {N_final}")
        log.append(f"    * Expansion time (generations ago): {T_expansion}")

    elif demographic_model == "contraction":
        N_initial = demographic_params.get("N_initial", 10000)
        N_final = demographic_params.get("N_final", 1000)
        T_contraction = demographic_params.get("T_contraction", 1000)

        demography = msprime.Demography()
        demography.add_population(name="pop0", initial_size=N_final)
        demography.add_population_parameters_change(time=T_contraction, initial_size=N_initial)

        log.append("  - Contraction model:")
        log.append(f"    * Initial population size: {N_initial}")
        log.append(f"    * Final population size: {N_final}")
        log.append(f"    * Contraction time (generations ago): {T_contraction}")

    elif demographic_model == "sawtooth":
        N_values = demographic_params.get("N_values", [10000, 5000, 15000, 7500])
        times = demographic_params.get("times", [500, 1000, 1500])

        if len(N_values) != len(times) + 1:
            raise ValueError("For sawtooth model, N_values should have one more element than times")

        demography = msprime.Demography()
        demography.add_population(name="pop0", initial_size=N_values[0])

        for i, time in enumerate(times):
            demography.add_population_parameters_change(time=time, initial_size=N_values[i + 1])

        log.append("  - Sawtooth model:")
        log.append(f"    * Population sizes: {N_values}")
        log.append(f"    * Change times (generations ago): {times}")

    else:
        raise ValueError(f"Unknown demographic model: {demographic_model}")

    # Set up coalescent model
    model = None
    if coalescent_model == "kingman":
        model = msprime.StandardCoalescent()
        log.append("  - Using standard Kingman coalescent")
    elif coalescent_model == "beta":
        if beta_coalescent_param is None:
            beta_coalescent_param = 1.5
        model = msprime.BetaCoalescent(alpha=beta_coalescent_param)
        log.append(f"  - Using Beta-coalescent with alpha = {beta_coalescent_param}")
    else:
        raise ValueError(f"Unknown coalescent model: {coalescent_model}")

    # Run simulation
    log.append("\\nRunning simulation...")

    ts = msprime.sim_ancestry(
        samples=num_samples,
        recombination_rate=recombination_rate,
        sequence_length=sequence_length,
        demography=demography,
        model=model,
        random_seed=random_seed,
    )

    # Add mutations
    mts = msprime.sim_mutations(ts, rate=mutation_rate, random_seed=random_seed)

    # Save to VCF
    with open(output_file, "w") as vcf_file:
        mts.write_vcf(vcf_file)

    # Calculate some basic statistics
    diversity = mts.diversity()
    num_sites = mts.num_sites
    num_trees = mts.num_trees

    # Log results
    end_time = time.time()
    runtime = end_time - start_time

    log.append(f"Simulation completed in {runtime:.2f} seconds")
    log.append("\\nResults:")
    log.append(f"  - Number of segregating sites: {num_sites}")
    log.append(f"  - Number of trees in ARG: {num_trees}")
    log.append(f"  - Nucleotide diversity (π): {diversity:.6f}")
    log.append(f"  - Output saved to: {os.path.abspath(output_file)}")

    return "\\n".join(log)

# Execute the function
try:
    result = simulate_demographic_history(
        num_samples=auto_convert(os.environ.get("PARAM_NUM_SAMPLES", "10")),
        sequence_length=auto_convert(os.environ.get("PARAM_SEQUENCE_LENGTH", "100000")),
        recombination_rate=auto_convert(os.environ.get("PARAM_RECOMBINATION_RATE", "1e-08")),
        mutation_rate=auto_convert(os.environ.get("PARAM_MUTATION_RATE", "1e-08")),
        demographic_model=auto_convert(os.environ.get("PARAM_DEMOGRAPHIC_MODEL", "constant")),
        demographic_params=auto_convert(os.environ.get("PARAM_DEMOGRAPHIC_PARAMS", "")),
        coalescent_model=auto_convert(os.environ.get("PARAM_COALESCENT_MODEL", "kingman")),
        beta_coalescent_param=auto_convert(os.environ.get("PARAM_BETA_COALESCENT_PARAM", "")),
        random_seed=auto_convert(os.environ.get("PARAM_RANDOM_SEED", "")),
        output_file=auto_convert(os.environ.get("PARAM_OUTPUT_FILE", "simulated_sequences.vcf")),
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
    "function": "simulate_demographic_history",
    "domain": "genetics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("simulate_demographic_history_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("simulate_demographic_history_output.txt", "w") as f:
    f.write("Biomni: Simulate Demographic History" + NL)
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
        biomni_function: "simulate_demographic_history"
    END_VERSIONS
    """
}

workflow SIMULATE_DEMOGRAPHIC_HISTORY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SIMULATE_DEMOGRAPHIC_HISTORY(ch_input)

    emit:
    results = SIMULATE_DEMOGRAPHIC_HISTORY.out.results
    output = SIMULATE_DEMOGRAPHIC_HISTORY.out.output
    versions = SIMULATE_DEMOGRAPHIC_HISTORY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SIMULATE_DEMOGRAPHIC_HISTORY_WORKFLOW(ch_input)

    SIMULATE_DEMOGRAPHIC_HISTORY_WORKFLOW.out.output.view { "Output: $it" }
}
