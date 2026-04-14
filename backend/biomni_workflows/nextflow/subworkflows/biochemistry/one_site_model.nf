#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_one_site_model
 * One-site binding model for ITC data.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.x = null
params.Kd = null
params.dH = null
params.n = null

// Main process
process ONE_SITE_MODEL {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("one_site_model_results.json"), emit: results
    path("one_site_model_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.biochemistry import one_site_model

# Run the tool
try:
    result = one_site_model(
    x="${params.x}",
    Kd="${params.Kd}",
    dH="${params.dH}",
    n="${params.n}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("one_site_model_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("one_site_model_output.txt", "w") as f:
    f.write("Biomni: One Site Model Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("one_site_model completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_BIOCHEMISTRY_ONE_SITE_MODEL {
    take:
    // No file inputs

    main:
    ONE_SITE_MODEL()

    emit:
    results = ONE_SITE_MODEL.out.results
    output = ONE_SITE_MODEL.out.output
}

// Entry workflow
workflow {
    if (!params.x) {
        error "Please provide --x parameter"
    }
    if (!params.Kd) {
        error "Please provide --Kd parameter"
    }
    if (!params.dH) {
        error "Please provide --dH parameter"
    }
    if (!params.n) {
        error "Please provide --n parameter"
    }


    BIOMNI_BIOCHEMISTRY_ONE_SITE_MODEL()
}
