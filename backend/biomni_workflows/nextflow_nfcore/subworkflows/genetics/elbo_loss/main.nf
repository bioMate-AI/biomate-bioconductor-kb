#!/usr/bin/env nextflow
/*
 * genetics/elbo_loss
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: ELBO loss calculation for variational autoencoder
params.reconstruction_loss = '0.5'
params.kl_divergence = '0.1'
params.beta = '1.0'

process ELBO_LOSS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("elbo_loss_results.json"), emit: results
    tuple val(meta), path("elbo_loss_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_RECONSTRUCTION_LOSS="${params.reconstruction_loss?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_KL_DIVERGENCE="${params.kl_divergence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BETA="${params.beta?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def elbo_loss(reconstruction_loss, kl_divergence, beta=1.0):
    '''Evidence Lower BOund loss: ELBO = reconstruction_loss + beta * KL_divergence
    Args: reconstruction_loss, kl_divergence, beta: KL weight
    '''
    # Validate inputs - use defaults if None
    if reconstruction_loss is None:
        reconstruction_loss = 0.5
    if kl_divergence is None:
        kl_divergence = 0.1
    if beta is None:
        beta = 1.0
    reconstruction_loss = float(reconstruction_loss)
    kl_divergence = float(kl_divergence)
    beta = float(beta)

    elbo = reconstruction_loss + beta * kl_divergence
    return {"elbo": float(elbo), "reconstruction": reconstruction_loss, "kl": kl_divergence, "beta": beta}

# Execute the function
try:
    result = elbo_loss(
        reconstruction_loss=auto_convert(os.environ.get("PARAM_RECONSTRUCTION_LOSS", "")),
        kl_divergence=auto_convert(os.environ.get("PARAM_KL_DIVERGENCE", "")),
        beta=auto_convert(os.environ.get("PARAM_BETA", "")),
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
    "function": "elbo_loss",
    "domain": "genetics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("elbo_loss_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("elbo_loss_output.txt", "w") as f:
    f.write("Biomni: Elbo Loss" + NL)
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
        biomni_function: "elbo_loss"
    END_VERSIONS
    """
}

workflow ELBO_LOSS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ELBO_LOSS(ch_input)

    emit:
    results = ELBO_LOSS.out.results
    output = ELBO_LOSS.out.output
    versions = ELBO_LOSS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ELBO_LOSS_WORKFLOW(ch_input)

    ELBO_LOSS_WORKFLOW.out.output.view { "Output: $it" }
}
