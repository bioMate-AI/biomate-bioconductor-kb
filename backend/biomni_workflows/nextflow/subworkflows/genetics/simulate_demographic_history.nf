#!/usr/bin/env nextflow
/*
 * biomni_genetics_simulate_demographic_history
 * Simulate DNA sequences with specified demographic and coalescent histories using msprime.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
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

// Main process
process SIMULATE_DEMOGRAPHIC_HISTORY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("simulate_demographic_history_results.json"), emit: results
    path("simulate_demographic_history_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genetics import simulate_demographic_history

# Run the tool
try:
    result = simulate_demographic_history(
    num_samples="${params.num_samples}",
    sequence_length="${params.sequence_length}",
    recombination_rate="${params.recombination_rate}",
    mutation_rate="${params.mutation_rate}",
    demographic_model="${params.demographic_model}",
    demographic_params="${params.demographic_params}",
    coalescent_model="${params.coalescent_model}",
    beta_coalescent_param="${params.beta_coalescent_param}",
    random_seed="${params.random_seed}",
    output_file="${params.output_file}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("simulate_demographic_history_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("simulate_demographic_history_output.txt", "w") as f:
    f.write("Biomni: Simulate Demographic History Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("simulate_demographic_history completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENETICS_SIMULATE_DEMOGRAPHIC_HISTORY {
    take:
    // No file inputs

    main:
    SIMULATE_DEMOGRAPHIC_HISTORY()

    emit:
    results = SIMULATE_DEMOGRAPHIC_HISTORY.out.results
    output = SIMULATE_DEMOGRAPHIC_HISTORY.out.output
}

// Entry workflow
workflow {



    BIOMNI_GENETICS_SIMULATE_DEMOGRAPHIC_HISTORY()
}
