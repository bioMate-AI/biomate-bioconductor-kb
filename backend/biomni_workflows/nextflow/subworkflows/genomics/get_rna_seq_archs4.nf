#!/usr/bin/env nextflow
/*
 * biomni_genomics_get_rna_seq_archs4
 * Given a gene name, this function returns the steps it performs and the max K transcripts-per-million (TPM)
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.gene_name = null
params.K = 10

// Main process
process GET_RNA_SEQ_ARCHS4 {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("get_rna_seq_archs4_results.json"), emit: results
    path("get_rna_seq_archs4_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genomics import get_rna_seq_archs4

# Run the tool
try:
    result = get_rna_seq_archs4(
    gene_name="${params.gene_name}",
    K=${params.K}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("get_rna_seq_archs4_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("get_rna_seq_archs4_output.txt", "w") as f:
    f.write("Biomni: Get Rna Seq Archs4 Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("get_rna_seq_archs4 completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_GET_RNA_SEQ_ARCHS4 {
    take:
    // No file inputs

    main:
    GET_RNA_SEQ_ARCHS4()

    emit:
    results = GET_RNA_SEQ_ARCHS4.out.results
    output = GET_RNA_SEQ_ARCHS4.out.output
}

// Entry workflow
workflow {
    if (!params.gene_name) {
        error "Please provide --gene_name parameter"
    }


    BIOMNI_GENOMICS_GET_RNA_SEQ_ARCHS4()
}
