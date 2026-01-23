#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_get_gene_coding_sequence
 * Retrieves the coding sequence(s) of a specified gene from NCBI Entrez.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.gene_name = null
params.organism = null
params.email = null

// Main process
process GET_GENE_CODING_SEQUENCE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_gene_coding_sequence_results.json"), emit: results
    path("get_gene_coding_sequence_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.molecular_biology import get_gene_coding_sequence

# Run the tool
try:
    result = get_gene_coding_sequence(
    gene_name="${params.gene_name}",
    organism="${params.organism}",
    email="${params.email}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_gene_coding_sequence_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("get_gene_coding_sequence_output.txt", "w") as f:
    f.write("Biomni: Get Gene Coding Sequence Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("get_gene_coding_sequence completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_GET_GENE_CODING_SEQUENCE {
    take:
    // No file inputs

    main:
    GET_GENE_CODING_SEQUENCE()

    emit:
    results = GET_GENE_CODING_SEQUENCE.out.results
    output = GET_GENE_CODING_SEQUENCE.out.output
}

// Entry workflow
workflow {
    if (!params.gene_name) {
        error "Please provide --gene_name parameter"
    }
    if (!params.organism) {
        error "Please provide --organism parameter"
    }


    BIOMNI_MOLECULAR_BIOLOGY_GET_GENE_CODING_SEQUENCE()
}
