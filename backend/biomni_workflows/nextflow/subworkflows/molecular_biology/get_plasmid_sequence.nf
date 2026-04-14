#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_get_plasmid_sequence
 * Unified function to retrieve plasmid sequences from either Addgene or NCBI.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.identifier = null
params.is_addgene = false

// Main process
process GET_PLASMID_SEQUENCE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_plasmid_sequence_results.json"), emit: results
    path("get_plasmid_sequence_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.molecular_biology import get_plasmid_sequence

# Run the tool
try:
    result = get_plasmid_sequence(
    identifier="${params.identifier}",
    is_addgene=${params.is_addgene ? "True" : "False"}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_plasmid_sequence_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("get_plasmid_sequence_output.txt", "w") as f:
    f.write("Biomni: Get Plasmid Sequence Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("get_plasmid_sequence completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_GET_PLASMID_SEQUENCE {
    take:
    // No file inputs

    main:
    GET_PLASMID_SEQUENCE()

    emit:
    results = GET_PLASMID_SEQUENCE.out.results
    output = GET_PLASMID_SEQUENCE.out.output
}

// Entry workflow
workflow {
    if (!params.identifier) {
        error "Please provide --identifier parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_GET_PLASMID_SEQUENCE()
}
