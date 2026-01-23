#!/usr/bin/env nextflow
/*
 * biomni_genetics_elbo_loss
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.z_scores = null
params.ld_matrix = null
params.pips = null
params.n_samples = '10'

// Main process
process ELBO_LOSS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("elbo_loss_results.json"), emit: results
    path("elbo_loss_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genetics import elbo_loss

# Run the tool
try:
    result = elbo_loss(
    z_scores="${params.z_scores}",
    ld_matrix="${params.ld_matrix}",
    pips="${params.pips}",
    n_samples="${params.n_samples}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("elbo_loss_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("elbo_loss_output.txt", "w") as f:
    f.write("Biomni: Elbo Loss Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("elbo_loss completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENETICS_ELBO_LOSS {
    take:
    // No file inputs

    main:
    ELBO_LOSS()

    emit:
    results = ELBO_LOSS.out.results
    output = ELBO_LOSS.out.output
}

// Entry workflow
workflow {
    if (!params.z_scores) {
        error "Please provide --z_scores parameter"
    }
    if (!params.ld_matrix) {
        error "Please provide --ld_matrix parameter"
    }
    if (!params.pips) {
        error "Please provide --pips parameter"
    }


    BIOMNI_GENETICS_ELBO_LOSS()
}
