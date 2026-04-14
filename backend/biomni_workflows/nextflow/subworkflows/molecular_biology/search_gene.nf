#!/usr/bin/env nextflow
/*
 * biomni_molecular_biology_search_gene
 * Search for gene ID in NCBI database.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'

// Main process
process SEARCH_GENE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("search_gene_results.json"), emit: results
    path("search_gene_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.molecular_biology import search_gene

# Run the tool
try:
    result = search_gene(

    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("search_gene_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("search_gene_output.txt", "w") as f:
    f.write("Biomni: Search Gene Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("search_gene completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MOLECULAR_BIOLOGY_SEARCH_GENE {
    take:
    // No file inputs

    main:
    SEARCH_GENE()

    emit:
    results = SEARCH_GENE.out.results
    output = SEARCH_GENE.out.output
}

// Entry workflow
workflow {



    BIOMNI_MOLECULAR_BIOLOGY_SEARCH_GENE()
}
