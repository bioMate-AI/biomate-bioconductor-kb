#!/usr/bin/env nextflow
/*
 * biomni_systems_biology_query_chatnt
 * Call ChatNT to answer a question about a DNA sequence.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.question = null
params.sequence = null
params.device = null

// Main process
process QUERY_CHATNT {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("query_chatnt_results.json"), emit: results
    path("query_chatnt_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.systems_biology import query_chatnt

# Run the tool
try:
    result = query_chatnt(
    question="${params.question}",
    sequence="${params.sequence}",
    device="${params.device}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("query_chatnt_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("query_chatnt_output.txt", "w") as f:
    f.write("Biomni: Query Chatnt Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("query_chatnt completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYSTEMS_BIOLOGY_QUERY_CHATNT {
    take:
    // No file inputs

    main:
    QUERY_CHATNT()

    emit:
    results = QUERY_CHATNT.out.results
    output = QUERY_CHATNT.out.output
}

// Entry workflow
workflow {
    if (!params.question) {
        error "Please provide --question parameter"
    }
    if (!params.sequence) {
        error "Please provide --sequence parameter"
    }


    BIOMNI_SYSTEMS_BIOLOGY_QUERY_CHATNT()
}
