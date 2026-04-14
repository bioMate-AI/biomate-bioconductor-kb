#!/usr/bin/env nextflow
/*
 * biomni_bioengineering_exp_decay
 * 
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.x = null
params.a = null
params.tau = null
params.c = null

// Main process
process EXP_DECAY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("exp_decay_results.json"), emit: results
    path("exp_decay_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.bioengineering import exp_decay

# Run the tool
try:
    result = exp_decay(
    x="${params.x}",
    a="${params.a}",
    tau="${params.tau}",
    c="${params.c}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("exp_decay_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("exp_decay_output.txt", "w") as f:
    f.write("Biomni: Exp Decay Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("exp_decay completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOENGINEERING_EXP_DECAY {
    take:
    // No file inputs

    main:
    EXP_DECAY()

    emit:
    results = EXP_DECAY.out.results
    output = EXP_DECAY.out.output
}

// Entry workflow
workflow {
    if (!params.x) {
        error "Please provide --x parameter"
    }
    if (!params.a) {
        error "Please provide --a parameter"
    }
    if (!params.tau) {
        error "Please provide --tau parameter"
    }
    if (!params.c) {
        error "Please provide --c parameter"
    }


    BIOMNI_BIOENGINEERING_EXP_DECAY()
}
