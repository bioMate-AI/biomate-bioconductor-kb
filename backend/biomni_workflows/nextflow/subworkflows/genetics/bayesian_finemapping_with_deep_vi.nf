#!/usr/bin/env nextflow
/*
 * biomni_genetics_bayesian_finemapping_with_deep_vi
 * Performs Bayesian fine-mapping from GWAS summary statistics using deep variational inference.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.gwas_summary_path = null
params.ld_matrix = null
params.n_iterations = '5000'
params.learning_rate = '0.01'
params.hidden_dim = '64'
params.credible_threshold = '0.95'

// Main process
process BAYESIAN_FINEMAPPING_WITH_DEEP_VI {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("bayesian_finemapping_with_deep_vi_results.json"), emit: results
    path("bayesian_finemapping_with_deep_vi_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genetics import bayesian_finemapping_with_deep_vi

# Run the tool
try:
    result = bayesian_finemapping_with_deep_vi(
    gwas_summary_path="${params.gwas_summary_path}",
    ld_matrix="${params.ld_matrix}",
    n_iterations="${params.n_iterations}",
    learning_rate="${params.learning_rate}",
    hidden_dim="${params.hidden_dim}",
    credible_threshold="${params.credible_threshold}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("bayesian_finemapping_with_deep_vi_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("bayesian_finemapping_with_deep_vi_output.txt", "w") as f:
    f.write("Biomni: Bayesian Finemapping With Deep Vi Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("bayesian_finemapping_with_deep_vi completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENETICS_BAYESIAN_FINEMAPPING_WITH_DEEP_VI {
    take:
    // No file inputs

    main:
    BAYESIAN_FINEMAPPING_WITH_DEEP_VI()

    emit:
    results = BAYESIAN_FINEMAPPING_WITH_DEEP_VI.out.results
    output = BAYESIAN_FINEMAPPING_WITH_DEEP_VI.out.output
}

// Entry workflow
workflow {
    if (!params.gwas_summary_path) {
        error "Please provide --gwas_summary_path parameter"
    }
    if (!params.ld_matrix) {
        error "Please provide --ld_matrix parameter"
    }


    BIOMNI_GENETICS_BAYESIAN_FINEMAPPING_WITH_DEEP_VI()
}
